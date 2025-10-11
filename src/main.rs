use std::path::PathBuf;

use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(version, about, long_about = None)]
struct Cli {
    /// Set a custom config file
    #[arg(long, value_name = "FILE")]
    config: Option<PathBuf>,

    /// Set a custom calendar file
    #[arg(short, long, value_name = "FILE")]
    calendar: Option<PathBuf>,

    /// Show events for a specific date, format: YYYY/MM/DD
    #[arg(short, long)]
    date: Option<String>,

    /// Show events up to <n> days in the past
    #[arg(short, long, value_name = "n")]
    past: Option<u32>,

    /// Show events up to <n> days in the future
    #[arg(short, long, value_name = "n")]
    future: Option<u32>,

    #[command(subcommand)]
    command: Option<Commands>,
}

#[derive(Subcommand)]
enum Commands {
    /// Edit the calendar file
    #[clap(alias = "e")]
    Edit,

    /// Display a calendar using cal(1)
    #[clap(alias = "c")]
    Cal {
        /// The number of months to display, default 1
        #[clap(value_name = "n")]
        n: Option<u32>,
    },
}

// struct Quand {
//     config_path: PathBuf,
//     calendar_path: PathBuf,
//     editor: String,
//     header: bool,
//     past: u32,
//     future: u32,
// }

fn main() {
    let cli = Cli::parse();

    if let Some(config_path) = cli.config.as_deref() {
        println!("Value for config: {}", config_path.display());
    }

    if let Some(calendar_path) = cli.calendar.as_deref() {
        println!("Value for calendar path: {}", calendar_path.display());
    }

    if let Some(date) = cli.date.as_deref() {
        println!("Value for date: {}", date);
    }

    // You can check for the existence of subcommands, and if found use their
    // matches just as you would the top level cmd
    match &cli.command {
        Some(Commands::Edit) => {
            println!("EDIT");
        }
        Some(Commands::Cal { n }) => {
            println!("cal {}", n.unwrap_or(1))
        }
        None => {}
    }

    // Continued program logic goes here...
}
