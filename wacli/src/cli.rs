//! Command line parsing and one function per command.

use std::io::{self, BufRead, Write};

use anyhow::{Result, bail};
use clap::{Parser, Subcommand};

use crate::config::Config;

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
    }
  }
}

fn list() -> Result<()> {
  Ok(())
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
