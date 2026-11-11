//! Command line parsing and one function per command.

use std::io::{self, BufRead, Write};
use std::path::PathBuf;

use anstyle::{AnsiColor, Style};
use anyhow::{Result, bail};
use clap::{Parser, Subcommand};

use crate::config::{Config, expand_home};
use crate::curse::Curse;
use crate::inventory::{Addon, Inventory, Status, version};
use crate::scanner::Scanner;

/// Keep WoW forever addons up to date, without the CurseForge app.
#[derive(Debug, Parser)]
#[command(version, about)]
pub struct Cli {
  #[command(subcommand)]
  command: Command,
}

#[derive(Debug, Subcommand)]
enum Command {
  /// List installed addons and whether each is up to date
  List,

  /// Update out of date addons
  Update {
    /// Don't ask before updating
    #[arg(short, long)]
    yes: bool,
  },

  /// Search CurseForge for an addon and install it
  Install {
    /// Name or CurseForge project ID
    name: String,

    /// Don't ask before installing
    #[arg(short, long)]
    yes: bool,
  },

  /// Remove an installed addon and all of its folders
  Uninstall {
    /// Addon name or folder
    name: String,

    /// Don't ask before removing
    #[arg(short, long)]
    yes: bool,
  },

  /// Tie an unrecognised folder to a CurseForge project
  ///
  /// For a folder that doesn't match by fingerprint (one you've edited,
  /// say), so it still gets updates.
  Link {
    /// Addon folder name
    folder: String,

    /// CurseForge project ID
    project: u32,
  },

  /// Leave an addon alone when updating
  Ignore {
    /// Addon folder name
    folder: String,

    /// Stop ignoring it
    #[arg(short, long)]
    remove: bool,
  },

  /// Save your CurseForge API key
  ///
  /// Get one at console.curseforge.com. Leave KEY out to be asked for it,
  /// which keeps it out of your shell history (and saves quoting the `$`s).
  SetKey {
    /// The key; asked for when left out
    key: Option<String>,
  },

  /// Save where the game's Interface/AddOns folder is
  SetDir {
    /// The AddOns folder
    path: PathBuf,
  },
}

impl Cli {
  pub fn run() -> Result<()> {
    match Self::parse().command {
      Command::List => list(),
      Command::Update { yes } => update(yes),
      Command::Install { name, yes } => install(&name, yes),
      Command::Uninstall { name, yes } => uninstall(&name, yes),
      Command::Link { folder, project } => link(&folder, project),
      Command::Ignore { folder, remove } => ignore(&folder, remove),
      Command::SetKey { key } => set_key(key),
      Command::SetDir { path } => set_dir(&path),
    }
  }
}

/// The config, a scanner for the AddOns folder and a CurseForge client
fn setup() -> Result<(Config, Scanner, Curse)> {
  let config = Config::load()?;
  let scanner = Scanner::new(config.addons_dir()?);
  let curse = Curse::new(config.api_key()?, config.user_agent.as_deref());
  Ok((config, scanner, curse))
}

fn list() -> Result<()> {
  let (config, scanner, curse) = setup()?;
  let inventory = Inventory::load(&config, &scanner, &curse)?;
  let addons = &inventory.addons;

  let out_of_date = addons.iter().filter(|a| a.is_out_of_date()).count();
  println!(
    "{} addon{} installed, {out_of_date} out of date",
    addons.len(),
    plural(addons.len())
  );
  if !addons.is_empty() {
    println!();
  }

  let name_width = addons.iter().map(|a| a.project.name.chars().count()).max();
  let version_width = addons.iter().map(|a| versions(a).chars().count()).max();
  let (name_width, version_width) = (name_width.unwrap_or(0), version_width.unwrap_or(0));
  for addon in addons {
    // Padded before colouring, so the escape codes don't throw the
    // columns off
    let notes = describe(addon);
    let versions = versions(addon);
    let versions = if notes.is_empty() {
      versions
    } else {
      format!("{versions:version_width$}")
    };
    let style = style(addon);
    let line = format!(
      "{:name_width$}  {style}{versions}{style:#}  {notes}",
      addon.project.name
    );
    anstream::println!("{}", line.trim_end());
  }

  if !inventory.unknown.is_empty() {
    let names: Vec<&str> = inventory.unknown.iter().map(|f| f.name.as_str()).collect();
    println!();
    println!("Not recognised: {}", names.join(", "));
    println!("(not from CurseForge, or edited; tie one to an addon with `wacli link`)");
  }
  Ok(())
}

/// "1.1" or "1.1 -> 1.2"
fn versions(addon: &Addon) -> String {
  let installed = addon.installed_version();
  match (&addon.latest, addon.status()) {
    (Some(latest), Status::OutOfDate | Status::Linked) if version(latest) != installed => {
      format!("{installed} -> {}", version(latest))
    }
    _ => installed,
  }
}

/// Green when up to date, yellow when out of date, plain otherwise
fn style(addon: &Addon) -> Style {
  let color = match addon.status() {
    _ if addon.ignored => return Style::new(),
    Status::UpToDate => AnsiColor::Green,
    Status::OutOfDate => AnsiColor::Yellow,
    Status::NoRelease | Status::Linked => return Style::new(),
  };
  Style::new().fg_color(Some(color.into()))
}

/// Anything the colour doesn't already say
fn describe(addon: &Addon) -> String {
  let mut notes = Vec::new();
  match addon.status() {
    Status::NoRelease => notes.push("no forever release".to_owned()),
    Status::Linked => notes.push("linked".to_owned()),
    Status::UpToDate | Status::OutOfDate => {}
  }
  if addon.ignored {
    notes.push("ignored".to_owned());
  }
  if !addon.modified.is_empty() {
    notes.push(format!("edited: {}", addon.modified.join(", ")));
  }
  notes.join(", ")
}

fn plural(n: usize) -> &'static str {
  if n == 1 { "" } else { "s" }
}

fn update(_yes: bool) -> Result<()> {
  Ok(())
}

fn install(_name: &str, _yes: bool) -> Result<()> {
  Ok(())
}

fn uninstall(_name: &str, _yes: bool) -> Result<()> {
  Ok(())
}

fn link(_folder: &str, _project: u32) -> Result<()> {
  Ok(())
}

fn ignore(_folder: &str, _remove: bool) -> Result<()> {
  Ok(())
}

fn set_key(key: Option<String>) -> Result<()> {
  let key = match key {
    Some(key) => key,
    None => {
      print!("CurseForge API key: ");
      io::stdout().flush()?;
      let mut line = String::new();
      io::stdin().lock().read_line(&mut line)?;
      line
    }
  };
  let key = key.trim();
  if key.is_empty() {
    bail!("no key given");
  }

  let mut config = Config::load()?;
  config.api_key = Some(key.to_owned());
  config.save()?;
  println!("saved to {}", Config::path()?.display());
  Ok(())
}

fn set_dir(path: &std::path::Path) -> Result<()> {
  // Made absolute but not resolved, so a symlinked game folder stays as
  // you wrote it
  let path = std::path::absolute(expand_home(path))?;
  if !path.is_dir() {
    bail!("no folder {}", path.display());
  }

  let mut config = Config::load()?;
  config.addons_dir = Some(path.clone());
  config.save()?;
  println!("addons folder set to {}", path.display());
  if path.file_name().is_none_or(|n| n != "AddOns") {
    println!("(that isn't called AddOns; it's usually <game>/Interface/AddOns)");
  }
  Ok(())
}
