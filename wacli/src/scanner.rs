//! Finding and fingerprinting the addon folders in the AddOns folder.

// Not called by any command yet
#![allow(dead_code)]

use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result, bail};

use crate::fingerprint::folder_fingerprint;

pub struct Scanner {
  addons_dir: PathBuf,
}

/// One folder in AddOns
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Folder {
  pub name: String,
  pub path: PathBuf,
  pub fingerprint: u32,
}

impl Scanner {
  pub fn new(addons_dir: impl Into<PathBuf>) -> Self {
    Self {
      addons_dir: addons_dir.into(),
    }
  }

  pub fn addons_dir(&self) -> &Path {
    &self.addons_dir
  }

  /// Every addon folder, sorted by name. Symlinked folders (addons you're
  /// developing) and hidden ones are left out.
  pub fn scan(&self) -> Result<Vec<Folder>> {
    let entries = fs::read_dir(&self.addons_dir)
      .with_context(|| format!("reading {}", self.addons_dir.display()))?;

    let mut folders = Vec::new();
    for entry in entries {
      let entry = entry?;
      let Some(name) = entry.file_name().to_str().map(str::to_owned) else {
        continue;
      };
      if name.starts_with('.') || !entry.file_type()?.is_dir() {
        continue;
      }
      folders.push(self.fingerprint(name)?);
    }
    folders.sort_by(|a, b| a.name.cmp(&b.name));
    Ok(folders)
  }

  /// One folder by name
  pub fn folder(&self, name: &str) -> Result<Folder> {
    let path = self.addons_dir.join(name);
    let meta = fs::symlink_metadata(&path);
    match meta {
      Ok(meta) if meta.is_dir() => self.fingerprint(name.to_owned()),
      Ok(meta) if meta.is_symlink() => bail!("{name} is a symlink, which wacli leaves alone"),
      _ => bail!("no addon folder {name} in {}", self.addons_dir.display()),
    }
  }

  fn fingerprint(&self, name: String) -> Result<Folder> {
    let path = self.addons_dir.join(&name);
    let fingerprint =
      folder_fingerprint(&path).with_context(|| format!("fingerprinting {}", path.display()))?;
    Ok(Folder {
      name,
      path,
      fingerprint,
    })
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  fn addon(root: &Path, name: &str) {
    let dir = root.join(name);
    fs::create_dir_all(&dir).unwrap();
    fs::write(dir.join(format!("{name}.toc")), format!("{name}.lua\n")).unwrap();
    fs::write(dir.join(format!("{name}.lua")), name).unwrap();
  }

  #[test]
  fn scans_real_folders_only() {
    let tmp = tempfile::tempdir().unwrap();
    let root = tmp.path();
    addon(root, "Zeta");
    addon(root, "Alpha");
    addon(root, ".hidden");
    fs::write(root.join("stray.txt"), "not a folder").unwrap();
    #[cfg(unix)]
    std::os::unix::fs::symlink(root.join("Alpha"), root.join("Linked")).unwrap();

    let scanner = Scanner::new(root);
    let folders = scanner.scan().unwrap();
    let names: Vec<&str> = folders.iter().map(|f| f.name.as_str()).collect();
    assert_eq!(names, ["Alpha", "Zeta"]);
    assert_eq!(
      folders[0].fingerprint,
      folder_fingerprint(&root.join("Alpha")).unwrap()
    );

    assert_eq!(scanner.folder("Zeta").unwrap(), folders[1]);
    assert!(scanner.folder("Missing").is_err());
    #[cfg(unix)]
    assert!(
      scanner
        .folder("Linked")
        .unwrap_err()
        .to_string()
        .contains("symlink")
    );
  }

  #[test]
  fn missing_addons_dir_is_an_error() {
    let tmp = tempfile::tempdir().unwrap();
    let err = Scanner::new(tmp.path().join("nope")).scan().unwrap_err();
    assert!(err.to_string().contains("nope"));
  }
}
