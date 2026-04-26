// ── Imports ─────────────────────────────────────────────────────────────────
use clap::{Parser, Subcommand};

use colored::Colorize;

use std::env;
use std::ffi::{c_int, CStr};
use std::os::unix::ffi::OsStrExt;
use std::path::{Path, PathBuf};

mod backends;

// Define commands modules inline (matching original structure)
mod commands {
    pub mod install;
    pub mod remove;
    pub mod rollback;

    pub mod diff;
    pub mod list;

    pub mod init;
}

pub mod config;
pub mod upac;

pub mod ffi;
pub mod types;

// ── CLI arguments ─────────────────────────────────────────────────────────────
// Automatic generation of Cli structure parser
#[derive(Parser)]
#[command(name = "upac", about = "A modular Linux package manager", version)]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

// Enumerate all available CLI subcommands
#[derive(Subcommand)]
enum Command {
    Install(commands::install::InstallArgs),
    Remove(commands::remove::RemoveArgs),
    Rollback(commands::rollback::RollbackArgs),

    List(commands::list::ListArgs),
    Diff(commands::diff::DiffArgs),
    Init(commands::init::InitArgs),
}

// ── C ABI Entry Point ─────────────────────────────────────────────────────
// Expose a C-compatible ABI function for the Zig linker to call.
// This function converts raw C argc/argv to Rust strings and executes the CLI.
#[no_mangle]
pub extern "C" fn rust_main(argc: c_int, argv: *const *const std::ffi::c_char) -> c_int {
    // Convert raw C arguments to a Vec of strings
    let args: Vec<std::string::String> = unsafe {
        std::slice::from_raw_parts(argv, argc as usize)
    }
    .iter()
    .map(|&arg| {
        // arg is *const std::ffi::c_char, we need to convert to &str
        let c_str = unsafe { CStr::from_ptr(arg) };
        c_str.to_string_lossy().into_owned()
    })
    .collect();

    // Parse arguments using clap's try_parse_from for programmatic invocation
    let cli_result = Cli::try_parse_from(&args);

    match cli_result {
        Ok(cli) => {
            // Load configuration
            let config = match check_default_config_path() {
                Some(path) => match config::Config::load(&path) {
                    Ok(cfg) => cfg,
                    Err(e) => {
                        eprintln!("{} {e}", "Error:".red().bold());
                        return 1;
                    }
                },
                None => {
                    eprintln!(
                        "{} {}",
                        "Error:".red().bold(),
                        "no default config path found"
                    );
                    return 1;
                }
            };

            // Execute the appropriate command
            let result = match cli.command {
                Command::Install(args) => commands::install::run(config, args),
                Command::Remove(args) => commands::remove::run(config, args),
                Command::List(args) => commands::list::run(config, args),
                Command::Diff(args) => commands::diff::run(config, args),
                Command::Rollback(args) => commands::rollback::run(config, args),
                Command::Init(args) => commands::init::run(config, args),
            };

            match result {
                Ok(()) => 0,
                Err(e) => {
                    eprintln!("{} {e}", "Error:".red().bold());
                    1
                }
            }
        }
        Err(e) => {
            // For parse errors, exit with code 1 but don't print full error
            // as clap handles error output automatically
            eprintln!("{}", e);
            1
        }
    }
}

// ── Standard Entry Point ───────────────────────────────────────────────────
// The main entry point for direct execution.
// Simply call the FFI entry point with the actual OS arguments.
fn main() {
    // Get args and collect them
    let args: Vec<std::string::String> = env::args().collect();
    let argc = args.len() as c_int;
    
    // Convert to CStrings
    let c_strings: Vec<std::ffi::CString> = args.iter()
        .map(|s| std::ffi::CString::new(s.as_str()).unwrap())
        .collect();
    
    // Get pointers
    let argv: Vec<*const std::ffi::c_char> = c_strings.iter()
        .map(|s| s.as_ptr())
        .collect();
    
    let exit_code = rust_main(argc, argv.as_ptr());
    std::process::exit(exit_code);
}

// ── Helpers ───────────────────────────────────────────────────────────────────
// Standard path validation function
fn check_default_config_path() -> Option<PathBuf> {
    let path = Path::new("/etc/upac/config.toml");

    if std::fs::metadata(path).is_ok() {
        Some(path.to_path_buf())
    } else {
        None
    }
}