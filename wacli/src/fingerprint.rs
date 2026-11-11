//! CurseForge fingerprints of addon folders.
//!
//! These must give exactly the numbers CurseForge matches against, so
//! keep the hash and the choice of files as they are: an "improvement"
//! here means addons stop matching.

use std::collections::{HashMap, HashSet};
use std::fs;
use std::io;
use std::path::{Component, Path, PathBuf};
use std::sync::LazyLock;

use regex::Regex;

/// The MurmurHash2 multiplier
const M: u32 = 0x5bd1_e995;

/// Bytes CurseForge leaves out: tab, line feed, carriage return and space
fn is_skipped(b: u8) -> bool {
  matches!(b, 9 | 10 | 13 | 32)
}

/// One file's fingerprint: MurmurHash2 (seed 1) of its bytes, with the
/// whitespace bytes left out of both the data and the length.
pub fn fingerprint(bytes: &[u8]) -> u32 {
  let kept = || bytes.iter().copied().filter(|&b| !is_skipped(b));

  let mut h = 1 ^ kept().count() as u32;
  let mut k: u32 = 0;
  let mut shift = 0;
  for b in kept() {
    k |= u32::from(b) << shift;
    shift += 8;
    if shift == 32 {
      let mut mixed = k.wrapping_mul(M);
      mixed = (mixed ^ (mixed >> 24)).wrapping_mul(M);
      h = h.wrapping_mul(M) ^ mixed;
      k = 0;
      shift = 0;
    }
  }
  if shift > 0 {
    h = (h ^ k).wrapping_mul(M);
  }
  h = (h ^ (h >> 13)).wrapping_mul(M);
  h ^ (h >> 15)
}

/// An addon folder's fingerprint: the fingerprints of the files the game
/// loads (its tocs, Bindings.xml, and whatever they include), sorted,
/// written out as one string of digits, and fingerprinted again.
pub fn folder_fingerprint(dir: &Path) -> io::Result<u32> {
  let mut hashes: Vec<u32> = loaded_files(dir)?
    .iter()
    // A file that can't be read is left out
    .filter_map(|path| fs::read(path).ok())
    .map(|bytes| fingerprint(&bytes))
    .collect();
  hashes.sort_unstable();

  let digits: String = hashes.iter().map(u32::to_string).collect();
  Ok(fingerprint(digits.as_bytes()))
}

static BINDINGS: LazyLock<Regex> = LazyLock::new(|| re(r"(?i)^[^/\\]+[/\\]bindings\.xml$"));
static TOC_INCLUDE: LazyLock<Regex> =
  LazyLock::new(|| re(r"(?i)^\s*([^\n\r\x{2028}\x{2029}]+\.(?:xml|lua))\s*$"));
static XML_INCLUDE_START: LazyLock<Regex> =
  LazyLock::new(|| re(r#"(?i)<(?:Include|Script)\s+file=["']"#));
static XML_INCLUDE_END: LazyLock<Regex> = LazyLock::new(|| re(r"^\s*/>"));
static TOC_COMMENT: LazyLock<Regex> = LazyLock::new(|| re(r"(?m)\s*#.*$"));
static XML_COMMENT: LazyLock<Regex> = LazyLock::new(|| re(r"(?s)<!--.*?-->"));

fn re(pattern: &str) -> Regex {
  Regex::new(pattern).expect("fingerprint regexes are valid")
}

/// Toc suffixes after `-`, `_` or `|`
const FLAVORS: &[&str] = &[
  "mainline", "bcc", "tbc", "classic", "vanilla", "wrath", "wotlkc", "cata", "mists", "forever",
  "camelot",
];

/// A toc named after its folder: `grid2/grid2.toc`, `grid2/grid2_camelot.toc`.
/// `rel` is lowercased and relative to the AddOns folder.
///
/// Does the work of the regex `^([^/]+)[\\/]\1([-|_](flavors))?\.toc$`.
fn is_folder_toc(rel: &str) -> bool {
  let Some((folder, name)) = rel.split_once('/') else {
    return false;
  };
  let Some(rest) = name
    .strip_prefix(folder)
    .and_then(|r| r.strip_suffix(".toc"))
  else {
    return false;
  };
  if folder.is_empty() || rest.contains('/') {
    return false;
  }
  match rest.as_bytes().first() {
    None => true,
    Some(b'-' | b'_' | b'|') => FLAVORS.contains(&&rest[1..]),
    _ => false,
  }
}

/// The file a toc line loads.
///
/// Does the work of the regex `^\s*((?:(?<!\.\.).)+\.(?:xml|lua))\s*$`.
/// The lookbehind rejects any character right after a `..`, and a match
/// always goes on past one to the extension, so any `..` at all means no
/// match.
fn toc_include(line: &str) -> Option<&str> {
  let path = TOC_INCLUDE.captures(line)?.get(1)?.as_str();
  (!path.contains("..")).then_some(path)
}

/// The file an xml line loads.
///
/// Does the work of the regex
/// `<(?:Include|Script)\s+file=["']((?:(?<!\.\.).)+)["']\s*/>`, case
/// insensitive, with `.` matching anything. The path is greedy, so it runs
/// to the last closing quote that fits, and the lookbehind stops it from
/// going on past a `..` (it may end on one).
fn xml_include(line: &str) -> Option<&str> {
  XML_INCLUDE_START.find_iter(line).find_map(|start| {
    let rest = &line[start.end()..];
    let limit = rest.find("..").map_or(rest.len(), |i| i + 2);
    let end = rest
      .char_indices()
      .filter(|&(i, c)| (1..=limit).contains(&i) && (c == '"' || c == '\''))
      .map(|(i, _)| i)
      .rev()
      .find(|&i| XML_INCLUDE_END.is_match(&rest[i + 1..]))?;
    Some(&rest[..end])
  })
}

/// Lowercased, for matching paths the way the game does: authors write
/// `Foo.lua` in the toc and ship `foo.lua`.
fn key(path: &Path) -> String {
  path.to_string_lossy().to_lowercase()
}

/// The files a folder's fingerprint covers
fn loaded_files(dir: &Path) -> io::Result<HashSet<PathBuf>> {
  let mut files = Vec::new();
  list_files(dir, &mut files)?;

  let mut scan = Scan {
    real: files.iter().map(|p| (key(p), p.clone())).collect(),
    matched: HashSet::new(),
  };

  // Paths are tested relative to the AddOns folder: "grid2/grid2.toc"
  let parent = dir.parent().unwrap_or(Path::new(""));
  let mut tocs = Vec::new();
  for file in &files {
    let rel = file.strip_prefix(parent).unwrap_or(file);
    let rel = rel.to_string_lossy().to_lowercase();
    if is_folder_toc(&rel) {
      tocs.push(file);
    } else if BINDINGS.is_match(&rel) {
      // Hashed, but not followed for includes
      scan.matched.insert(file.clone());
    }
  }

  for toc in tocs {
    scan.include(toc);
  }
  Ok(scan.matched)
}

fn list_files(dir: &Path, out: &mut Vec<PathBuf>) -> io::Result<()> {
  for entry in fs::read_dir(dir)? {
    let path = entry?.path();
    if fs::metadata(&path)?.is_dir() {
      list_files(&path, out)?;
    } else {
      out.push(path);
    }
  }
  Ok(())
}

struct Scan {
  /// Lowercased path to the path on disk
  real: HashMap<String, PathBuf>,
  matched: HashSet<PathBuf>,
}

impl Scan {
  fn include(&mut self, path: &Path) {
    let Some(real) = self.real.get(&key(path)).cloned() else {
      return;
    };
    if !self.matched.insert(real.clone()) {
      return;
    }

    // Only tocs and xml can include other files. The extension check is
    // case sensitive.
    let ext = real.extension().and_then(|e| e.to_str());
    let (comment, find_include): (&Regex, fn(&str) -> Option<&str>) = match ext {
      Some("toc") => (&TOC_COMMENT, toc_include),
      Some("xml") => (&XML_COMMENT, xml_include),
      _ => return,
    };
    let Ok(bytes) = fs::read(&real) else {
      return;
    };
    let text = String::from_utf8_lossy(&bytes);
    let text = comment.replace_all(&text, "");

    let dir = real.parent().unwrap_or(Path::new(""));
    for line in text.split('\n') {
      let Some(name) = find_include(trim(line)) else {
        continue;
      };
      let name = trim(name);
      // Stop reading this file's includes here, rather than skipping
      // just this one
      if name.chars().any(|c| c == '|' || c < ' ') {
        break;
      }
      self.include(&join(dir, &name.replace('\\', "/")));
    }
  }
}

/// JavaScript's trim, which also takes off a byte order mark
fn trim(s: &str) -> &str {
  s.trim_matches(|c: char| c.is_whitespace() || c == '\u{feff}')
}

/// Node's path.join: a leading slash is just a separator, and `.` and `..`
/// are resolved
fn join(base: &Path, rel: &str) -> PathBuf {
  let mut out = base.to_path_buf();
  for part in Path::new(rel).components() {
    match part {
      Component::Normal(name) => out.push(name),
      Component::ParentDir => {
        out.pop();
      }
      Component::CurDir | Component::RootDir | Component::Prefix(_) => {}
    }
  }
  out
}

#[cfg(test)]
mod tests {
  use super::*;

  /// MurmurHash2 answers from an independent implementation (a CurseForge
  /// client for Minecraft), which uses the same per-file fingerprint
  #[test]
  fn known_fingerprints() {
    assert_eq!(fingerprint(b""), 1_540_447_798);
    assert_eq!(fingerprint(b"Hello, world!"), 2_173_663_876);
    assert_eq!(
      fingerprint(b"The quick brown fox jumps over the lazy dog"),
      3_751_777_527
    );
    let all: Vec<u8> = (0..=255).collect();
    assert_eq!(fingerprint(&all), 2_094_645_347);
  }

  #[test]
  fn whitespace_does_not_count() {
    assert_eq!(fingerprint(b"a b\tc\r\nd"), 3_376_380_438);
    assert_eq!(fingerprint(b" \t\r\n"), fingerprint(b""));
    // Other control bytes do count
    assert_ne!(fingerprint(b"ab\x0bcd"), fingerprint(b"abcd"));
  }

  /// Addon folders that exercise the toc name check (the regex backreference),
  /// the `..` guard (its lookbehinds), and plain includes
  fn write_fixtures(root: &Path) {
    let w = |rel: &str, text: &str| {
      let path = root.join(rel);
      fs::create_dir_all(path.parent().unwrap()).unwrap();
      fs::write(path, text).unwrap();
    };

    // Plain: a toc with lua and xml includes, nested xml, a library folder
    w(
      "Plain/Plain.toc",
      "## Interface: 16001\n## Title: Plain\nCore.lua\nUI.xml\n",
    );
    w("Plain/Core.lua", "local x = 1\n");
    w(
      "Plain/UI.xml",
      "<Ui>\n  <Script file=\"UI.lua\"/>\n  <Include file=\"Libs\\Lib\\Lib.xml\"/>\n</Ui>\n",
    );
    w("Plain/UI.lua", "print('ui')\n");
    w(
      "Plain/Libs/Lib/Lib.xml",
      "<Ui><Script file=\"Lib.lua\"/></Ui>\n",
    );
    w("Plain/Libs/Lib/Lib.lua", "lib\n");
    w("Plain/Media/readme.txt", "not loaded\n");

    // Flavor: which tocs count as the folder's own
    w("Flavor/Flavor.toc", "Base.lua\n");
    w("Flavor/Flavor_Camelot.toc", "Camelot.lua\n");
    w("Flavor/Flavor-Mainline.toc", "Mainline.lua\n");
    w("Flavor/Flavor|Vanilla.toc", "Pipe.lua\n");
    w("Flavor/Flavor_Bogus.toc", "Bogus.lua\n");
    w("Flavor/FlavorX.toc", "X.lua\n");
    w("Flavor/Other.toc", "Other.lua\n");
    w("Flavor/Sub/Flavor.toc", "Deep.lua\n");
    for name in [
      "Base", "Camelot", "Mainline", "Pipe", "Bogus", "X", "Other", "Deep",
    ] {
      w(&format!("Flavor/{name}.lua"), &format!("-- {name}\n"));
    }

    // Dots: paths containing `..`, which are never followed (Good2.lua and
    // Inner.lua exist, so following them would change the hash). One.lua
    // and Two.lua share a line, so the greedy path swallows both.
    w(
      "Dots/Dots.toc",
      "Good.lua\nsub/../Good2.lua\na..b.lua\n..\\Plain\\Core.lua\nDots.xml\n",
    );
    w(
      "Dots/Dots.xml",
      concat!(
        "<Ui>\n",
        "<Script file=\"sub\\..\\Inner.lua\"/>\n",
        "<Script file=\"weird..\"/>\n",
        "<script FILE='Case.lua'  />\n",
        "<Script file=\"One.lua\"/> <Script file=\"Two.lua\"/>\n",
        "</Ui>\n",
      ),
    );
    for name in ["Good", "Good2", "a..b", "Inner", "Case", "One", "Two"] {
      w(&format!("Dots/{name}.lua"), &format!("-- {name}\n"));
    }
    w("Dots/weird..", "-- weird\n");
  }

  /// Expected values come from the original regexes run as they are, by both
  /// fancy-regex and a Python port, which agreed
  #[test]
  fn fixture_fingerprints() {
    let tmp = tempfile::tempdir().unwrap();
    let root = tmp.path();
    write_fixtures(root);

    let cases: [(&str, u32, &[&str]); 3] = [
      (
        "Plain",
        4_079_964_503,
        &[
          "Plain/Core.lua",
          "Plain/Libs/Lib/Lib.lua",
          "Plain/Libs/Lib/Lib.xml",
          "Plain/Plain.toc",
          "Plain/UI.lua",
          "Plain/UI.xml",
        ],
      ),
      (
        "Flavor",
        3_638_020_520,
        &[
          "Flavor/Base.lua",
          "Flavor/Camelot.lua",
          "Flavor/Flavor-Mainline.toc",
          "Flavor/Flavor.toc",
          "Flavor/Flavor_Camelot.toc",
          "Flavor/Flavor|Vanilla.toc",
          "Flavor/Mainline.lua",
          "Flavor/Pipe.lua",
        ],
      ),
      (
        "Dots",
        3_362_544_452,
        &[
          "Dots/Case.lua",
          "Dots/Dots.toc",
          "Dots/Dots.xml",
          "Dots/Good.lua",
          "Dots/weird..",
        ],
      ),
    ];

    for (name, want, want_files) in cases {
      let dir = root.join(name);
      let mut files: Vec<String> = loaded_files(&dir)
        .unwrap()
        .iter()
        .map(|p| p.strip_prefix(root).unwrap().display().to_string())
        .collect();
      files.sort();
      assert_eq!(files, want_files, "{name} files");
      assert_eq!(
        folder_fingerprint(&dir).unwrap(),
        want,
        "{name} fingerprint"
      );
    }
  }
}
