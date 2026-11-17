//! Putting addon folders into AddOns and taking them out.
//!
//! Everything is unpacked into a hidden folder inside AddOns first, then
//! swapped in with renames. If any step fails, what was already swapped is
//! put back, so a failed install leaves the old version as it was.

use std::collections::BTreeSet;
use std::fs;
use std::io::{self, Cursor};
use std::path::{Component, Path, PathBuf};

use anyhow::{Context, Result, bail};
use tempfile::TempDir;
use zip::ZipArchive;

pub struct Installer {
  addons_dir: PathBuf,
  /// For tests: fail after this many renames, to check rollback
  #[cfg(test)]
  fail_after: Option<usize>,
}

/// A rename done during a swap, so it can be undone
struct Moved {
  from: PathBuf,
  to: PathBuf,
}

impl Installer {
  pub fn new(addons_dir: impl Into<PathBuf>) -> Self {
    Self {
      addons_dir: addons_dir.into(),
      #[cfg(test)]
      fail_after: None,
    }
  }

  /// Install an addon from its zip, replacing `old_folders` (what the
  /// installed version has, which may differ from the new one). Returns
  /// the folders installed.
  pub fn install_zip(&self, zip: &[u8], old_folders: &[String]) -> Result<Vec<String>> {
    let staging = self.staging()?;
    let unpacked = staging.path().join("new");
    let folders = unpack(zip, &unpacked)?;

    for name in folders.iter().chain(old_folders) {
      self.check_not_symlink(name)?;
    }

    let aside = staging.path().join("old");
    fs::create_dir(&aside)?;
    let mut steps = Vec::new();
    let result = (|| -> Result<()> {
      // Out of the way first: everything being replaced or dropped
      let replaced: BTreeSet<&String> = folders.iter().chain(old_folders).collect();
      for name in replaced {
        let path = self.addons_dir.join(name);
        if path.exists() {
          self.rename(&path, &aside.join(name), &mut steps)?;
        }
      }
      for name in &folders {
        self.rename(
          &unpacked.join(name),
          &self.addons_dir.join(name),
          &mut steps,
        )?;
      }
      Ok(())
    })();

    if let Err(e) = result {
      undo(steps);
      return Err(e);
    }
    // The old folders go when `staging` is dropped
    Ok(folders.into_iter().collect())
  }

  /// Delete addon folders. They're all moved aside before any are deleted,
  /// so a failure leaves them all in place.
  pub fn remove(&self, folders: &[String]) -> Result<()> {
    for name in folders {
      self.check_not_symlink(name)?;
    }
    let staging = self.staging()?;
    let mut steps = Vec::new();
    for name in folders {
      let path = self.addons_dir.join(name);
      if !path.exists() {
        continue;
      }
      if let Err(e) = self.rename(&path, &staging.path().join(name), &mut steps) {
        undo(steps);
        return Err(e);
      }
    }
    drop(staging);
    Ok(())
  }

  /// A hidden folder inside AddOns (so renames never cross filesystems),
  /// deleted when dropped
  fn staging(&self) -> Result<TempDir> {
    tempfile::Builder::new()
      .prefix(".wacli-")
      .tempdir_in(&self.addons_dir)
      .with_context(|| format!("writing to {}", self.addons_dir.display()))
  }

  /// Symlinked folders are addons you're developing, which wacli leaves be
  fn check_not_symlink(&self, name: &str) -> Result<()> {
    let path = self.addons_dir.join(name);
    if fs::symlink_metadata(&path).is_ok_and(|m| m.is_symlink()) {
      bail!("{name} is a symlink in AddOns, which wacli won't replace");
    }
    Ok(())
  }

  fn rename(&self, from: &Path, to: &Path, steps: &mut Vec<Moved>) -> Result<()> {
    #[cfg(test)]
    if self.fail_after == Some(steps.len()) {
      bail!("failing on purpose");
    }
    fs::rename(from, to)
      .with_context(|| format!("moving {} to {}", from.display(), to.display()))?;
    steps.push(Moved {
      from: from.to_path_buf(),
      to: to.to_path_buf(),
    });
    Ok(())
  }
}

/// Put renames back, newest first. Best effort: the error that started
/// this is what gets reported.
fn undo(steps: Vec<Moved>) {
  for step in steps.into_iter().rev() {
    let _ = fs::rename(&step.to, &step.from);
  }
}

/// Unpack `zip` into `dest`, returning its top-level folders. Files at the
/// top level (readmes and such) are skipped; anything that could land
/// outside `dest` fails the whole thing.
fn unpack(zip: &[u8], dest: &Path) -> Result<BTreeSet<String>> {
  let mut archive = ZipArchive::new(Cursor::new(zip)).context("reading the addon's zip")?;
  let mut folders = BTreeSet::new();

  for i in 0..archive.len() {
    let mut entry = archive.by_index(i)?;
    let name = entry.name().map_or_else(|_| "?".into(), |n| n.into_owned());
    // The zip crate would quietly unpack `/etc/x` as `etc/x`; an addon has
    // no business with either
    if name.starts_with(['/', '\\']) {
      bail!("the zip has an unsafe path: {name}");
    }
    let Some(path) = entry.enclosed_name() else {
      bail!("the zip has an unsafe path: {}", name);
    };
    if entry.is_symlink() {
      bail!("the zip has a symlink: {}", name);
    }
    let mut parts = path.components();
    let Some(Component::Normal(top)) = parts.next() else {
      bail!("the zip has an unsafe path: {}", name);
    };
    let top = top
      .to_str()
      .context("the zip has a folder name that isn't UTF-8")?;
    let in_folder = parts.next().is_some();
    if !in_folder && !entry.is_dir() {
      continue;
    }
    folders.insert(top.to_owned());

    let out = dest.join(&path);
    if entry.is_dir() {
      fs::create_dir_all(&out)?;
    } else {
      if let Some(parent) = out.parent() {
        fs::create_dir_all(parent)?;
      }
      let mut file = fs::File::create(&out)?;
      io::copy(&mut entry, &mut file).with_context(|| format!("unpacking {name}"))?;
    }
  }

  if folders.is_empty() {
    bail!("the zip has no addon folders in it");
  }
  Ok(folders)
}

#[cfg(test)]
mod tests {
  use std::io::Write;

  use zip::write::{SimpleFileOptions, ZipWriter};

  use super::*;

  fn zip(files: &[(&str, &str)]) -> Vec<u8> {
    let mut writer = ZipWriter::new(Cursor::new(Vec::new()));
    for (name, text) in files {
      writer
        .start_file(*name, SimpleFileOptions::default())
        .unwrap();
      writer.write_all(text.as_bytes()).unwrap();
    }
    writer.finish().unwrap().into_inner()
  }

  fn read(root: &Path, rel: &str) -> String {
    fs::read_to_string(root.join(rel)).unwrap()
  }

  fn entries(root: &Path) -> Vec<String> {
    let mut names: Vec<String> = fs::read_dir(root)
      .unwrap()
      .map(|e| e.unwrap().file_name().into_string().unwrap())
      .collect();
    names.sort();
    names
  }

  fn old_install(root: &Path) {
    for (rel, text) in [
      ("Grid2/Grid2.toc", "old"),
      ("Grid2/Stale.lua", "gone after update"),
      ("Grid2Options/Options.lua", "old"),
      ("Grid2Dropped/Dropped.lua", "old"),
    ] {
      let path = root.join(rel);
      fs::create_dir_all(path.parent().unwrap()).unwrap();
      fs::write(path, text).unwrap();
    }
  }

  const OLD: &[&str] = &["Grid2", "Grid2Options", "Grid2Dropped"];

  fn names(list: &[&str]) -> Vec<String> {
    list.iter().map(|s| s.to_string()).collect()
  }

  #[test]
  fn replaces_folders_and_drops_old_ones() {
    let tmp = tempfile::tempdir().unwrap();
    let root = tmp.path();
    old_install(root);
    fs::create_dir(root.join("Other")).unwrap();

    let new = zip(&[
      ("Grid2/Grid2.toc", "new"),
      ("Grid2Options/Options.lua", "new"),
      ("Grid2LDB/LDB.lua", "new"),
      ("README.txt", "skipped"),
    ]);
    let installed = Installer::new(root).install_zip(&new, &names(OLD)).unwrap();

    assert_eq!(installed, ["Grid2", "Grid2LDB", "Grid2Options"]);
    assert_eq!(
      entries(root),
      ["Grid2", "Grid2LDB", "Grid2Options", "Other"]
    );
    assert_eq!(read(root, "Grid2/Grid2.toc"), "new");
    assert!(!root.join("Grid2/Stale.lua").exists());
    assert_eq!(read(root, "Grid2LDB/LDB.lua"), "new");
  }

  #[test]
  fn fresh_install() {
    let tmp = tempfile::tempdir().unwrap();
    let new = zip(&[("Foo/Foo.toc", "x")]);
    let installed = Installer::new(tmp.path()).install_zip(&new, &[]).unwrap();
    assert_eq!(installed, ["Foo"]);
    assert_eq!(entries(tmp.path()), ["Foo"]);
  }

  #[test]
  fn failure_puts_everything_back() {
    let tmp = tempfile::tempdir().unwrap();
    let root = tmp.path();
    old_install(root);

    let new = zip(&[
      ("Grid2/Grid2.toc", "new"),
      ("Grid2Options/Options.lua", "new"),
    ]);
    // Fail partway, at each step in turn: after moving old folders aside,
    // and after moving some new ones in
    for fail_after in 0..5 {
      let mut installer = Installer::new(root);
      installer.fail_after = Some(fail_after);
      assert!(installer.install_zip(&new, &names(OLD)).is_err());

      assert_eq!(
        entries(root),
        names(&["Grid2", "Grid2Dropped", "Grid2Options"])
      );
      assert_eq!(read(root, "Grid2/Grid2.toc"), "old");
      assert_eq!(read(root, "Grid2/Stale.lua"), "gone after update");
    }
  }

  #[test]
  fn unsafe_zips_are_refused() {
    let tmp = tempfile::tempdir().unwrap();
    let root = tmp.path();
    let installer = Installer::new(root);

    let escape = zip(&[("Foo/Foo.toc", "x"), ("../escape.lua", "x")]);
    assert!(installer.install_zip(&escape, &[]).is_err());
    let absolute = zip(&[("/etc/evil", "x")]);
    assert!(installer.install_zip(&absolute, &[]).is_err());
    let empty = zip(&[("README.txt", "x")]);
    assert!(installer.install_zip(&empty, &[]).is_err());

    assert!(entries(root).is_empty());
    assert!(!tmp.path().parent().unwrap().join("escape.lua").exists());
  }

  #[cfg(unix)]
  #[test]
  fn symlinked_folders_are_left_alone() {
    let tmp = tempfile::tempdir().unwrap();
    let root = tmp.path();
    let dev = tempfile::tempdir().unwrap();
    std::os::unix::fs::symlink(dev.path(), root.join("KUI")).unwrap();

    let new = zip(&[("KUI/KUI.toc", "x")]);
    let err = Installer::new(root).install_zip(&new, &[]).unwrap_err();
    assert!(err.to_string().contains("symlink"));
    assert!(Installer::new(root).remove(&names(&["KUI"])).is_err());
    assert!(fs::symlink_metadata(root.join("KUI")).unwrap().is_symlink());
  }

  #[test]
  fn removes_folders() {
    let tmp = tempfile::tempdir().unwrap();
    let root = tmp.path();
    old_install(root);
    Installer::new(root)
      .remove(&names(&["Grid2", "Grid2Options", "NotThere"]))
      .unwrap();
    assert_eq!(entries(root), ["Grid2Dropped"]);
  }
}
