mod cli;
mod config;
mod curse;
mod fingerprint;
mod scanner;

fn main() -> anyhow::Result<()> {
  cli::Cli::run()
}
