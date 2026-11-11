//! A small client for the CurseForge API (api.curseforge.com), covering
//! only what wacli needs.

// Some of it is for install and update, still to come
#![allow(dead_code)]

use std::time::Duration;

use anyhow::{Context, Result, bail};
use serde::Deserialize;
use serde::de::DeserializeOwned;

const API: &str = "https://api.curseforge.com/v1";

/// CurseForge's game ID for World of Warcraft
const WOW: u32 = 1;

/// CurseForge's game version for WoW forever (interface 16001)
pub const FOREVER: &str = "1.60.1";

/// Most results the API returns in one page
const PAGE_SIZE: u32 = 50;

/// Sent when the config doesn't set one
const DEFAULT_USER_AGENT: &str = concat!("wacli/", env!("CARGO_PKG_VERSION"));

pub struct Curse {
  agent: ureq::Agent,
  api: String,
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
  /// `user_agent` is sent with every request, or wacli's own when `None`
  pub fn new(key: impl Into<String>, user_agent: Option<&str>) -> Self {
    Self::with_api(API, key, user_agent)
  }

  fn with_api(api: &str, key: impl Into<String>, user_agent: Option<&str>) -> Self {
    let agent = ureq::Agent::config_builder()
      .timeout_global(Some(Duration::from_secs(30)))
      .user_agent(user_agent.unwrap_or(DEFAULT_USER_AGENT))
      // ureq unpacks gzipped responses itself
      .accept_encoding("gzip")
      .build()
      .into();
    Self {
      agent,
      api: api.to_owned(),
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
      .post(format!("{}/fingerprints/{WOW}", self.api))
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

  /// Several projects in one request, in no particular order
  pub fn projects(&self, ids: &[u32]) -> Result<Vec<Project>> {
    if ids.is_empty() {
      return Ok(Vec::new());
    }
    let request = self
      .agent
      .post(format!("{}/mods", self.api))
      .header("x-api-key", &self.key)
      .header("Accept", "application/json");
    let body = serde_json::json!({ "modIds": ids });
    let result: Data<Vec<Project>> = read(request.send_json(body))?;
    Ok(result.data)
  }

  /// The newest stable release of an addon for `game_version`
  pub fn latest_release(&self, project_id: u32, game_version: &str) -> Result<Option<File>> {
    let mut files = self.files(project_id, game_version)?;
    files.retain(|f| f.release_type == ReleaseType::Release);
    Ok(files.into_iter().max_by_key(|f| f.id))
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
      .get(format!("{}/{path}", self.api))
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

#[cfg(test)]
mod tests {
  use std::io::{BufRead, BufReader, Read, Write};
  use std::net::TcpListener;
  use std::thread;

  use flate2::Compression;
  use flate2::write::GzEncoder;

  use super::*;

  /// Answers one request with a gzipped `body`, handing back the request's
  /// headers, lowercased
  fn serve_once(body: &str) -> (String, thread::JoinHandle<Vec<String>>) {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let url = format!("http://{}", listener.local_addr().unwrap());

    let mut gz = GzEncoder::new(Vec::new(), Compression::default());
    gz.write_all(body.as_bytes()).unwrap();
    let gzipped = gz.finish().unwrap();

    let server = thread::spawn(move || {
      let (stream, _) = listener.accept().unwrap();
      let mut reader = BufReader::new(stream.try_clone().unwrap());
      let mut headers = Vec::new();
      let mut length = 0;
      loop {
        let mut line = String::new();
        reader.read_line(&mut line).unwrap();
        let line = line.trim_end().to_lowercase();
        if line.is_empty() {
          break;
        }
        if let Some(n) = line.strip_prefix("content-length:") {
          length = n.trim().parse().unwrap();
        }
        headers.push(line);
      }
      reader.read_exact(&mut vec![0; length]).unwrap();

      let mut stream = stream;
      write!(
        stream,
        "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Encoding: gzip\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
        gzipped.len()
      )
      .unwrap();
      stream.write_all(&gzipped).unwrap();
      headers
    });
    (url, server)
  }

  const PROJECT: &str =
    r#"{"data":{"id":15226,"name":"Grid2","slug":"grid2","allowModDistribution":true}}"#;

  #[test]
  fn sends_headers_and_unpacks_gzip() {
    let (url, server) = serve_once(PROJECT);
    let curse = Curse::with_api(&url, "the-key", Some("Custom/1.0"));
    let project = curse.project(15226).unwrap();
    assert_eq!(project.name, "Grid2");
    assert_eq!(project.allow_mod_distribution, Some(true));

    let headers = server.join().unwrap();
    assert!(headers.iter().any(|h| h.starts_with("get /mods/15226 ")));
    assert!(headers.contains(&"user-agent: custom/1.0".to_owned()));
    assert!(headers.contains(&"accept-encoding: gzip".to_owned()));
    assert!(headers.contains(&"x-api-key: the-key".to_owned()));
  }

  #[test]
  fn default_user_agent_on_posts_too() {
    let (url, server) = serve_once(r#"{"data":{"exactMatches":[]}}"#);
    let curse = Curse::with_api(&url, "the-key", None);
    assert!(curse.match_fingerprints(&[1, 2]).unwrap().is_empty());

    let headers = server.join().unwrap();
    assert!(
      headers
        .iter()
        .any(|h| h.starts_with("post /fingerprints/1 "))
    );
    let ua = format!("user-agent: {}", DEFAULT_USER_AGENT.to_lowercase());
    assert!(headers.contains(&ua));
    assert!(headers.contains(&"accept-encoding: gzip".to_owned()));
  }
}
