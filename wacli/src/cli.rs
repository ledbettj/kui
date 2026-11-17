//! Command line parsing and one function per command.

use std::collections::BTreeSet;
use std::io::{self, BufRead, Write};
use std::path::PathBuf;

use anstyle::{AnsiColor, Style};
use anyhow::{Context, Result, bail};
use clap::{Parser, Subcommand};

use crate::config::{Config, expand_home};
use crate::curse::{Curse, FOREVER, File, Project};
use crate::installer::Installer;
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

fn update(yes: bool) -> Result<()> {
  let (config, scanner, curse) = setup()?;
  let inventory = Inventory::load(&config, &scanner, &curse)?;
  let addons = &inventory.addons;
  let stale: Vec<&Addon> = addons.iter().filter(|a| a.is_out_of_date()).collect();

  println!(
    "{} addon{} installed, {} out of date",
    addons.len(),
    plural(addons.len()),
    stale.len()
  );
  if stale.is_empty() {
    return Ok(());
  }

  // Newer versions can need addons that aren't installed yet
  let mut needs: Vec<(Project, File)> = Vec::new();
  for addon in &stale {
    let latest = addon
      .latest
      .as_ref()
      .expect("out of date addons have a release");
    for (project, file) in dependencies(&curse, latest, &inventory)? {
      if !needs.iter().any(|(p, _)| p.id == project.id) {
        needs.push((project, file));
      }
    }
  }

  println!();
  println!("update the following:");
  for addon in &stale {
    let mut line = format!("{} {}", addon.project.name, versions(addon));
    if !addon.modified.is_empty() {
      line.push_str(&format!(
        " (your edits to {} get replaced)",
        addon.modified.join(", ")
      ));
    }
    println!("{line}");
  }
  if !needs.is_empty() {
    println!();
    println!("and install these, which the new versions need:");
    for (p, f) in &needs {
      println!("{} {} ({})", p.name, version(f), page(p));
    }
  }
  println!();
  if !confirm("update?", true, yes)? {
    return Ok(());
  }

  // One failure doesn't stop the rest
  let installer = Installer::new(scanner.addons_dir());
  let mut failed = Vec::new();
  for (p, f) in &needs {
    match curse
      .download(f)
      .and_then(|zip| installer.install_zip(&zip, &[]))
    {
      Ok(_) => println!("installed {} {}", p.name, version(f)),
      Err(e) => {
        println!("couldn't install {}: {e:#}", p.name);
        failed.push(p.name.clone());
      }
    }
  }
  for addon in &stale {
    let latest = addon
      .latest
      .as_ref()
      .expect("out of date addons have a release");
    let old: Vec<String> = addon.folders.iter().map(|f| f.name.clone()).collect();
    match curse
      .download(latest)
      .and_then(|zip| installer.install_zip(&zip, &old))
    {
      Ok(_) => println!("updated {} to {}", addon.project.name, version(latest)),
      Err(e) => {
        println!("couldn't update {}: {e:#}", addon.project.name);
        failed.push(addon.project.name.clone());
      }
    }
  }
  if !failed.is_empty() {
    bail!("{} didn't go through: {}", failed.len(), failed.join(", "));
  }
  Ok(())
}

fn install(name: &str, yes: bool) -> Result<()> {
  let (config, scanner, curse) = setup()?;
  let inventory = Inventory::load(&config, &scanner, &curse)?;
  let (project, others) = find_project(&curse, name)?;

  if let Some(addon) = inventory.addons.iter().find(|a| a.project.id == project.id) {
    println!(
      "{} {} is already installed; `wacli update` keeps it up to date",
      addon.project.name,
      addon.installed_version()
    );
    return Ok(());
  }
  let file = curse
    .latest_release(project.id, FOREVER)?
    .with_context(|| format!("{} has no stable release for forever", project.name))?;
  let needs = dependencies(&curse, &file, &inventory)?;

  println!(
    "found {} {} ({})",
    project.name,
    version(&file),
    page(&project)
  );
  if !others.is_empty() {
    let others: Vec<String> = others
      .iter()
      .map(|p| format!("{} ({})", p.name, p.id))
      .collect();
    println!(
      "(also matched: {}; install one by its number)",
      others.join(", ")
    );
  }
  if !needs.is_empty() {
    println!();
    println!("it needs these, which will be installed too:");
    for (p, f) in &needs {
      println!("  {} {} ({})", p.name, version(f), page(p));
    }
  }
  println!();
  if !confirm("install?", true, yes)? {
    return Ok(());
  }

  let installer = Installer::new(scanner.addons_dir());
  for (p, f) in needs.iter().chain([&(project.clone(), file.clone())]) {
    let zip = curse.download(f)?;
    let folders = installer.install_zip(&zip, &[])?;
    println!(
      "installed {} {} ({})",
      p.name,
      version(f),
      folders.join(", ")
    );
  }
  Ok(())
}

/// An addon by CurseForge ID or by search, with any other close matches
fn find_project(curse: &Curse, name: &str) -> Result<(Project, Vec<Project>)> {
  if let Ok(id) = name.parse::<u32>() {
    return Ok((curse.project(id)?, Vec::new()));
  }
  let mut found = curse.search(name, FOREVER)?;
  if found.is_empty() {
    bail!("nothing on CurseForge for forever matches {name:?}");
  }
  // An exact name or slug wins over popularity
  let wanted = name.to_lowercase();
  let exact = found
    .iter()
    .position(|p| p.name.to_lowercase() == wanted || p.slug == wanted);
  let best = found.remove(exact.unwrap_or(0));
  found.truncate(3);
  if exact.is_some() {
    found.clear();
  }
  Ok((best, found))
}

/// The addons `file` requires that aren't installed, and theirs in turn,
/// in the order to install them
fn dependencies(curse: &Curse, file: &File, inventory: &Inventory) -> Result<Vec<(Project, File)>> {
  let mut seen: BTreeSet<u32> = inventory.addons.iter().map(|a| a.project.id).collect();
  seen.insert(file.project_id);
  // Folders the addon's own zip brings, which some bundle their
  // dependencies into
  let bundled: BTreeSet<&str> = file.modules.iter().map(|m| m.name.as_str()).collect();
  let mut needs = Vec::new();
  let mut queue: Vec<u32> = required(file);
  while let Some(id) = queue.pop() {
    if !seen.insert(id) {
      continue;
    }
    let project = curse.project(id)?;
    match curse.latest_release(id, FOREVER)? {
      Some(dep)
        if dep
          .modules
          .iter()
          .all(|m| bundled.contains(m.name.as_str())) => {}
      Some(dep) => {
        queue.extend(required(&dep));
        needs.push((project, dep));
      }
      None => println!(
        "warning: it needs {}, which has no stable release for forever",
        project.name
      ),
    }
  }
  // Dependencies of dependencies go first
  needs.reverse();
  Ok(needs)
}

fn required(file: &File) -> Vec<u32> {
  file
    .dependencies
    .iter()
    .filter(|d| d.is_required())
    .map(|d| d.project_id)
    .collect()
}

fn page(project: &Project) -> String {
  project
    .links
    .website_url
    .clone()
    .unwrap_or_else(|| format!("https://www.curseforge.com/wow/addons/{}", project.slug))
}

fn uninstall(name: &str, yes: bool) -> Result<()> {
  let (config, scanner, curse) = setup()?;
  let inventory = Inventory::load(&config, &scanner, &curse)?;
  let wanted = name.to_lowercase();

  let matches: Vec<&Addon> = inventory
    .addons
    .iter()
    .filter(|a| {
      a.project.name.to_lowercase() == wanted
        || a.project.slug == wanted
        || a.folders.iter().any(|f| f.name.to_lowercase() == wanted)
    })
    .collect();
  let (label, folders): (String, Vec<String>) = match matches.as_slice() {
    [addon] => (
      format!("{} {}", addon.project.name, addon.installed_version()),
      addon.folders.iter().map(|f| f.name.clone()).collect(),
    ),
    [] => match inventory
      .unknown
      .iter()
      .find(|f| f.name.to_lowercase() == wanted)
    {
      Some(folder) => (folder.name.clone(), vec![folder.name.clone()]),
      None => bail!("nothing installed matches {name:?}; `wacli list` shows what is"),
    },
    several => {
      let names: Vec<&str> = several.iter().map(|a| a.project.name.as_str()).collect();
      bail!("{name:?} matches more than one addon: {}", names.join(", "));
    }
  };

  if folders.len() > 1 {
    println!("removes {}", folders.join(", "));
  }
  if !confirm(&format!("uninstall {label}?"), false, yes)? {
    return Ok(());
  }
  Installer::new(scanner.addons_dir()).remove(&folders)?;
  println!("removed {label} (its saved settings in WTF are kept)");
  Ok(())
}

/// Ask a yes/no question. `yes` (from --yes) answers it without asking,
/// and an empty answer takes the default.
fn confirm(question: &str, default: bool, yes: bool) -> Result<bool> {
  if yes {
    return Ok(true);
  }
  print!("{question} {} ", if default { "(Y/n)" } else { "(y/N)" });
  io::stdout().flush()?;
  let mut line = String::new();
  if io::stdin().lock().read_line(&mut line)? == 0 {
    // No input to read: take that as no
    println!();
    return Ok(false);
  }
  Ok(match line.trim().to_lowercase().as_str() {
    "" => default,
    "y" | "yes" => true,
    _ => false,
  })
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
