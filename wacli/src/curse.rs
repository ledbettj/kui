//! A small client for the CurseForge API (api.curseforge.com), covering
//! only what wacli needs.

// Not called by any command yet
#![allow(dead_code)]

use std::time::Duration;

use anyhow::{Context, Result, bail};
use serde::Deserialize;
use serde::de::DeserializeOwned;

const API: &str = "https://api.curseforge.com/v1";

/// CurseForge's game ID for World of Warcraft
const WOW: u32 = 1;

/// Most results the API returns in one page
const PAGE_SIZE: u32 = 50;

pub struct Curse {
  agent: ureq::Agent,
  key: String,
}

/// An addon on CurseForge (the API calls these mods)
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Project {
  pub id: u32,
  pub name: String,
  pub slug: String,
  #[serde(default)]
  pub summary: String,
  #[serde(default)]
  pub links: Links,
  #[serde(default)]
  pub download_count: f64,
  /// Whether the author lets other apps download it. When this is false,
  /// files come with no download URL.
  pub allow_mod_distribution: Option<bool>,
  #[serde(default)]
  pub latest_files: Vec<File>,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Links {
  pub website_url: Option<String>,
}

/// One released file (version) of an addon
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct File {
  pub id: u32,
  #[serde(rename = "modId")]
  pub project_id: u32,
  pub display_name: String,
  pub file_name: String,
  pub release_type: ReleaseType,
  pub file_date: String,
  pub file_length: u64,
  /// Missing when the author doesn't allow downloads from other apps
  pub download_url: Option<String>,
  #[serde(default)]
  pub game_versions: Vec<String>,
  #[serde(default)]
  pub dependencies: Vec<Dependency>,
  /// The folders this file unpacks to, with their fingerprints
  #[serde(default)]
  pub modules: Vec<Module>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(try_from = "u8")]
pub enum ReleaseType {
  Release,
  Beta,
  Alpha,
}

impl TryFrom<u8> for ReleaseType {
  type Error = String;

  fn try_from(n: u8) -> Result<Self, String> {
    match n {
      1 => Ok(Self::Release),
      2 => Ok(Self::Beta),
      3 => Ok(Self::Alpha),
      _ => Err(format!("unknown release type {n}")),
    }
  }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Dependency {
  #[serde(rename = "modId")]
  pub project_id: u32,
  pub relation_type: u8,
}

impl Dependency {
  pub fn is_required(&self) -> bool {
    self.relation_type == 3
  }
}

#[derive(Debug, Clone, Deserialize)]
pub struct Module {
  /// Folder name
  pub name: String,
  pub fingerprint: u32,
}

/// An installed file CurseForge recognised by its fingerprints
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Match {
  #[serde(rename = "id")]
  pub project_id: u32,
  pub file: File,
  #[serde(default)]
  pub latest_files: Vec<File>,
}

#[derive(Deserialize)]
struct Data<T> {
  data: T,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct FingerprintMatches {
  exact_matches: Vec<Match>,
}

impl Curse {
  pub fn new(key: impl Into<String>) -> Self {
    let agent = ureq::Agent::config_builder()
      .timeout_global(Some(Duration::from_secs(30)))
      .user_agent(concat!("wacli/", env!("CARGO_PKG_VERSION")))
      .build()
      .into();
    Self {
      agent,
      key: key.into(),
    }
  }

  /// The installed files CurseForge recognises, from folder fingerprints.
  /// Fingerprints it doesn't know are left out.
  pub fn match_fingerprints(&self, fingerprints: &[u32]) -> Result<Vec<Match>> {
    if fingerprints.is_empty() {
      return Ok(Vec::new());
    }
    let request = self
      .agent
      .post(format!("{API}/fingerprints/{WOW}"))
      .header("x-api-key", &self.key)
      .header("Accept", "application/json");
    let body = serde_json::json!({ "fingerprints": fingerprints });
    let result: Data<FingerprintMatches> = read(request.send_json(body))?;
    Ok(result.data.exact_matches)
  }

  /// Addons matching `query` that have files for `game_version`, most
  /// popular first
  pub fn search(&self, query: &str, game_version: &str) -> Result<Vec<Project>> {
    let request = self
      .get("mods/search")
      .query("gameId", WOW.to_string())
      .query("searchFilter", query)
      .query("gameVersion", game_version)
      .query("sortField", "2") // popularity
      .query("sortOrder", "desc")
      .query("pageSize", "20");
    let result: Data<Vec<Project>> = read(request.call())?;
    Ok(result.data)
  }

  pub fn project(&self, id: u32) -> Result<Project> {
    let result: Data<Project> = read(self.get(&format!("mods/{id}")).call())?;
    Ok(result.data)
  }

  /// An addon's newest files for `game_version`, newest first. Only the
  /// newest page of files, which is plenty to pick an update from.
  pub fn files(&self, project_id: u32, game_version: &str) -> Result<Vec<File>> {
    let request = self
      .get(&format!("mods/{project_id}/files"))
      .query("gameVersion", game_version)
      .query("pageSize", PAGE_SIZE.to_string());
    let result: Data<Vec<File>> = read(request.call())?;
    Ok(result.data)
  }

  fn get(&self, path: &str) -> ureq::RequestBuilder<ureq::typestate::WithoutBody> {
    self
      .agent
      .get(format!("{API}/{path}"))
      .header("x-api-key", &self.key)
      .header("Accept", "application/json")
  }
}

fn read<T: DeserializeOwned>(
  response: Result<ureq::http::Response<ureq::Body>, ureq::Error>,
) -> Result<T> {
  match response {
    Ok(mut response) => response
      .body_mut()
      .read_json()
      .context("reading CurseForge's response"),
    Err(ureq::Error::StatusCode(401 | 403)) => {
      bail!("CurseForge rejected the API key; check it, or set a new one with `wacli set-key`")
    }
    Err(ureq::Error::StatusCode(404)) => bail!("CurseForge has no such addon"),
    Err(e) => Err(e).context("talking to CurseForge"),
  }
}
