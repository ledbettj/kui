//! What's installed: addon folders grouped into CurseForge addons, each with
//! its installed file and newest release.

use std::collections::{BTreeSet, HashMap};
use std::thread;

use anyhow::Result;

use crate::config::Config;
use crate::curse::{Curse, FOREVER, File, Match, Project};
use crate::scanner::{Folder, Scanner};

#[derive(Debug)]
pub struct Inventory {
  /// Sorted by name
  pub addons: Vec<Addon>,
  /// Folders CurseForge doesn't recognise and the config doesn't link
  pub unknown: Vec<Folder>,
}

/// One CurseForge addon and the folders it installed
#[derive(Debug)]
pub struct Addon {
  pub project: Project,
  pub folders: Vec<Folder>,
  /// What's installed, when the fingerprints matched. `None` for a linked
  /// folder, whose version CurseForge can't tell.
  pub installed: Option<File>,
  /// The newest stable release for forever
  pub latest: Option<File>,
  /// Folders whose files differ from what CurseForge has for the installed
  /// version
  pub modified: Vec<String>,
  pub ignored: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Status {
  UpToDate,
  OutOfDate,
  /// No stable release for forever on CurseForge
  NoRelease,
  /// Linked by hand, so the installed version is unknown
  Linked,
}

impl Addon {
  pub fn status(&self) -> Status {
    match (&self.installed, &self.latest) {
      (_, None) => Status::NoRelease,
      (None, Some(_)) => Status::Linked,
      // File IDs only go up, so a newer upload has a higher one. An alpha
      // newer than the latest release counts as up to date.
      (Some(installed), Some(latest)) if latest.id > installed.id => Status::OutOfDate,
      _ => Status::UpToDate,
    }
  }

  pub fn is_out_of_date(&self) -> bool {
    !self.ignored && self.status() == Status::OutOfDate
  }

  /// The installed version from the addon's toc, or CurseForge's name for
  /// the file when the toc doesn't say. The first folder is the addon's
  /// main one, as CurseForge lists them.
  pub fn installed_version(&self) -> String {
    let toc = self.folders.first().and_then(Folder::toc_version);
    toc
      .or_else(|| self.installed.as_ref().map(version))
      .unwrap_or_else(|| "?".into())
  }
}

/// A file's version as CurseForge shows it, less any `.zip`
pub fn version(file: &File) -> String {
  let name = &file.display_name;
  name.strip_suffix(".zip").unwrap_or(name).to_owned()
}

impl Inventory {
  /// Scan the AddOns folder and look everything up on CurseForge
  pub fn load(config: &Config, scanner: &Scanner, curse: &Curse) -> Result<Self> {
    let folders = scanner.scan()?;
    let fingerprints: Vec<u32> = folders.iter().map(|f| f.fingerprint).collect();
    let matches = curse.match_fingerprints(&fingerprints)?;

    let mut ids: BTreeSet<u32> = matches.iter().map(|m| m.project_id).collect();
    ids.extend(config.link.values());
    let ids: Vec<u32> = ids.into_iter().collect();
    let projects = curse.projects(&ids)?;

    // One request per addon, so they go out together
    let latest = thread::scope(|s| {
      let handles: Vec<_> = ids
        .iter()
        .map(|&id| (id, s.spawn(move || curse.latest_release(id, FOREVER))))
        .collect();
      handles
        .into_iter()
        .map(|(id, h)| Ok((id, h.join().expect("lookup thread panicked")?)))
        .collect::<Result<HashMap<u32, Option<File>>>>()
    })?;

    Ok(Self::assemble(config, folders, matches, projects, latest))
  }

  /// Group folders into addons. Kept apart from `load` so it can be tested
  /// without CurseForge.
  pub fn assemble(
    config: &Config,
    folders: Vec<Folder>,
    matches: Vec<Match>,
    projects: Vec<Project>,
    mut latest: HashMap<u32, Option<File>>,
  ) -> Self {
    let mut projects: HashMap<u32, Project> = projects.into_iter().map(|p| (p.id, p)).collect();
    let mut folders: Vec<Option<Folder>> = folders.into_iter().map(Some).collect();
    let mut addons = Vec::new();

    for m in matches {
      // A match claims its folders by name, which also catches a folder of
      // the addon that someone edited
      let mut claimed = Vec::new();
      let mut modified = Vec::new();
      for module in &m.file.modules {
        let slot = folders
          .iter_mut()
          .find(|f| f.as_ref().is_some_and(|f| f.name == module.name));
        if let Some(folder) = slot.and_then(Option::take) {
          if folder.fingerprint != module.fingerprint {
            modified.push(folder.name.clone());
          }
          claimed.push(folder);
        }
      }
      let Some(project) = projects.get(&m.project_id).cloned() else {
        // Not something we can show; leave the folders unknown
        folders.extend(claimed.into_iter().map(Some));
        continue;
      };
      addons.push(Addon {
        ignored: claimed.iter().any(|f| config.ignore.contains(&f.name)),
        latest: latest.get(&m.project_id).cloned().flatten(),
        project,
        folders: claimed,
        installed: Some(m.file),
        modified,
      });
    }

    let mut unknown = Vec::new();
    for folder in folders.into_iter().flatten() {
      let linked = config
        .link
        .get(&folder.name)
        .and_then(|id| projects.remove(id));
      match linked {
        Some(project) => addons.push(Addon {
          ignored: config.ignore.contains(&folder.name),
          latest: latest.remove(&project.id).flatten(),
          project,
          folders: vec![folder],
          installed: None,
          modified: Vec::new(),
        }),
        None => unknown.push(folder),
      }
    }

    addons.sort_by_key(|a| a.project.name.to_lowercase());
    Self { addons, unknown }
  }
}

#[cfg(test)]
mod tests {
  use std::path::PathBuf;

  use super::*;

  fn folder(name: &str, fingerprint: u32) -> Folder {
    Folder {
      name: name.into(),
      path: PathBuf::from(name),
      fingerprint,
    }
  }

  fn project(id: u32, name: &str) -> Project {
    serde_json::from_value(serde_json::json!({ "id": id, "name": name, "slug": name })).unwrap()
  }

  fn file(id: u32, project_id: u32, version: &str, modules: &[(&str, u32)]) -> File {
    let modules: Vec<_> = modules
      .iter()
      .map(|(name, fingerprint)| serde_json::json!({ "name": name, "fingerprint": fingerprint }))
      .collect();
    serde_json::from_value(serde_json::json!({
      "id": id, "modId": project_id, "displayName": version, "fileName": "x.zip",
      "releaseType": 1, "fileDate": "2026-11-01T00:00:00Z", "fileLength": 1,
      "modules": modules,
    }))
    .unwrap()
  }

  fn matched(file: File) -> Match {
    Match {
      project_id: file.project_id,
      file,
      latest_files: Vec::new(),
    }
  }

  #[test]
  fn groups_folders_and_works_out_status() {
    let mut config = Config::default();
    config.link.insert("Edited".into(), 30);
    config.ignore.insert("Old".into());

    let folders = vec![
      folder("Grid2", 1),
      folder("Grid2Options", 2),
      folder("Details", 3),
      folder("Details_Plugin", 999), // edited by hand
      folder("Edited", 4),
      folder("Old", 5),
      folder("Mystery", 6),
    ];
    let matches = vec![
      matched(file(
        100,
        10,
        "4.1.11",
        &[("Grid2", 1), ("Grid2Options", 2)],
      )),
      matched(file(
        200,
        20,
        "Details.1",
        &[("Details", 3), ("Details_Plugin", 7)],
      )),
      matched(file(400, 40, "old.zip", &[("Old", 5)])),
    ];
    let projects = vec![
      project(10, "Grid2"),
      project(20, "Details!"),
      project(30, "Edited"),
      project(40, "Old"),
    ];
    let latest = HashMap::from([
      (10, Some(file(100, 10, "4.1.11", &[]))),
      (20, Some(file(201, 20, "Details.2", &[]))),
      (30, Some(file(300, 30, "3.0", &[]))),
      (40, Some(file(401, 40, "new", &[]))),
    ]);

    let inv = Inventory::assemble(&config, folders, matches, projects, latest);
    let by_name = |n: &str| inv.addons.iter().find(|a| a.project.name == n).unwrap();

    let names: Vec<&str> = inv.addons.iter().map(|a| a.project.name.as_str()).collect();
    assert_eq!(names, ["Details!", "Edited", "Grid2", "Old"]);
    assert_eq!(
      inv
        .unknown
        .iter()
        .map(|f| f.name.as_str())
        .collect::<Vec<_>>(),
      ["Mystery"]
    );

    let grid2 = by_name("Grid2");
    assert_eq!(grid2.folders.len(), 2);
    assert_eq!(grid2.status(), Status::UpToDate);

    let details = by_name("Details!");
    assert_eq!(details.status(), Status::OutOfDate);
    assert_eq!(details.modified, ["Details_Plugin"]);
    assert!(details.is_out_of_date());

    let edited = by_name("Edited");
    assert_eq!(edited.status(), Status::Linked);
    assert!(edited.installed.is_none());

    let old = by_name("Old");
    assert_eq!(old.status(), Status::OutOfDate);
    assert!(old.ignored);
    assert!(!old.is_out_of_date());
    assert_eq!(old.installed_version(), "old");
  }

  #[test]
  fn no_release_and_newer_alpha() {
    let folders = vec![folder("A", 1), folder("B", 2)];
    let matches = vec![
      matched(file(500, 1, "alpha", &[("A", 1)])),
      matched(file(600, 2, "b", &[("B", 2)])),
    ];
    let projects = vec![project(1, "A"), project(2, "B")];
    // A's newest release is older than the alpha that's installed
    let latest = HashMap::from([(1, Some(file(400, 1, "rel", &[]))), (2, None)]);

    let inv = Inventory::assemble(&Config::default(), folders, matches, projects, latest);
    assert_eq!(inv.addons[0].status(), Status::UpToDate);
    assert_eq!(inv.addons[1].status(), Status::NoRelease);
  }
}
