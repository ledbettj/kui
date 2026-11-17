mod cli;
mod config;
mod curse;
mod fingerprint;
mod installer;
mod inventory;
mod scanner;

fn main() -> anyhow::Result<()> {
  cli::Cli::run()
}
