//! Command line parsing and one function per command.

use clap::{Parser, Subcommand};

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
}

impl Cli {
  pub fn run() {
    match Self::parse().command {
      Command::List => list(),
      Command::Update { yes } => update(yes),
      Command::Install { name, yes } => install(&name, yes),
      Command::Uninstall { name, yes } => uninstall(&name, yes),
      Command::Link { folder, project } => link(&folder, project),
      Command::Ignore { folder, remove } => ignore(&folder, remove),
    }
  }
}

fn list() {}

fn update(_yes: bool) {}

fn install(_name: &str, _yes: bool) {}

fn uninstall(_name: &str, _yes: bool) {}

fn link(_folder: &str, _project: u32) {}

fn ignore(_folder: &str, _remove: bool) {}
