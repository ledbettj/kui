//! The config file, `~/.config/wacli/config.toml`.

use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result, bail};
use serde::{Deserialize, Serialize};

#[derive(Debug, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct Config {
  /// CurseForge API key, from console.curseforge.com
  #[serde(skip_serializing_if = "Option::is_none")]
  pub api_key: Option<String>,

  /// The game's Interface/AddOns folder. A leading `~/` is the home folder.
  #[serde(skip_serializing_if = "Option::is_none")]
  pub addons_dir: Option<PathBuf>,

  /// Folders that don't match by fingerprint, tied to a CurseForge project ID
  #[serde(skip_serializing_if = "BTreeMap::is_empty")]
  pub link: BTreeMap<String, u32>,

  /// Folders left alone when updating
  #[serde(skip_serializing_if = "BTreeSet::is_empty")]
  pub ignore: BTreeSet<String>,
}

impl Config {
  pub fn path() -> Result<PathBuf> {
    let dir = dirs::config_dir().context("can't find a config folder")?;
    Ok(dir.join("wacli").join("config.toml"))
  }

  /// The config file, or an empty config if there isn't one yet
  pub fn load() -> Result<Self> {
    Self::load_from(&Self::path()?)
  }

  pub fn load_from(path: &Path) -> Result<Self> {
    match fs::read_to_string(path) {
      Ok(text) => toml::from_str(&text).with_context(|| format!("reading {}", path.display())),
      Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(Self::default()),
      Err(e) => Err(e).with_context(|| format!("reading {}", path.display())),
    }
  }

  pub fn save(&self) -> Result<()> {
    self.save_to(&Self::path()?)
  }

  /// Written to a temporary file and renamed into place, readable only by
  /// you since it holds the API key
  pub fn save_to(&self, path: &Path) -> Result<()> {
    let dir = path.parent().context("config path has no folder")?;
    fs::create_dir_all(dir).with_context(|| format!("creating {}", dir.display()))?;

    let text = toml::to_string_pretty(self)?;
    let tmp = path.with_extension("toml.tmp");
    let mut file = private_file(&tmp).with_context(|| format!("writing {}", tmp.display()))?;
    file.write_all(text.as_bytes())?;
    file.sync_all()?;
    fs::rename(&tmp, path).with_context(|| format!("writing {}", path.display()))?;
    Ok(())
  }

  #[allow(dead_code)] // until the commands use it
  pub fn api_key(&self) -> Result<&str> {
    match self.api_key.as_deref() {
      Some(key) if !key.is_empty() => Ok(key),
      _ => bail!("no CurseForge API key; set one with `wacli set-key`"),
    }
  }

  #[allow(dead_code)] // until the commands use it
  pub fn addons_dir(&self) -> Result<PathBuf> {
    let Some(dir) = &self.addons_dir else {
      bail!(
        "no addons folder; set addons_dir in {}",
        Self::path()?.display()
      );
    };
    Ok(expand_home(dir))
  }
}

#[cfg(unix)]
fn private_file(path: &Path) -> std::io::Result<fs::File> {
  use std::os::unix::fs::OpenOptionsExt;
  fs::OpenOptions::new()
    .write(true)
    .create(true)
    .truncate(true)
    .mode(0o600)
    .open(path)
}

#[cfg(not(unix))]
fn private_file(path: &Path) -> std::io::Result<fs::File> {
  fs::File::create(path)
}

fn expand_home(path: &Path) -> PathBuf {
  match (path.strip_prefix("~"), dirs::home_dir()) {
    (Ok(rest), Some(home)) => home.join(rest),
    _ => path.to_path_buf(),
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn round_trips() {
    let tmp = tempfile::tempdir().unwrap();
    let path = tmp.path().join("sub/config.toml");

    let mut config = Config::load_from(&path).unwrap();
    assert!(config.api_key.is_none());

    config.api_key = Some("$2a$10$dollar$signs".into());
    config.addons_dir = Some("~/Games/WoW/Interface/AddOns".into());
    config.link.insert("Auctionator".into(), 6124);
    config.ignore.insert("ForeverDungeonJournal".into());
    config.save_to(&path).unwrap();

    let back = Config::load_from(&path).unwrap();
    assert_eq!(back.api_key().unwrap(), "$2a$10$dollar$signs");
    assert_eq!(back.link["Auctionator"], 6124);
    assert!(back.ignore.contains("ForeverDungeonJournal"));
    assert!(
      back
        .addons_dir()
        .unwrap()
        .ends_with("Games/WoW/Interface/AddOns")
    );
    assert!(!back.addons_dir().unwrap().starts_with("~"));

    #[cfg(unix)]
    {
      use std::os::unix::fs::PermissionsExt;
      let mode = fs::metadata(&path).unwrap().permissions().mode();
      assert_eq!(mode & 0o777, 0o600);
    }
  }

  #[test]
  fn missing_key_says_how_to_set_it() {
    let err = Config::default().api_key().unwrap_err().to_string();
    assert!(err.contains("set-key"));
  }
}
