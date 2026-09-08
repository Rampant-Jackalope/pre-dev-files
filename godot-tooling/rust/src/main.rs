//! cargo xtask build-extension [--release] [--target <triple>] [--out <dir>]
//!                              [--package <pkg>] [--artifact <name>] [--lib-name <name>]
//!
//! Builds the Godot GDExtension shared library and copies it into a flat
//! bin/ folder with a filename Godot's loader can parse.
//!
//! Godot's loader reads one flat bin/ folder and picks a file by parsing
//! its NAME for os/build_type/arch. So here, the directory is FIXED (one
//! folder, matches .gdextension [libraries] paths) and the FILENAME carries
//! all the platform info:
//!     lib_rj.linux.debug.x86_64.so
//!
//! All of package/artifact/lib-name/out-dir default to the constants below
//! and can be overridden per invocation with flags, for use across crates
//! without editing this file.
//!
//! Usage:
//!     cargo run -p xtask -- build-extension
//!     cargo run -p xtask -- build-extension --release --target aarch64-unknown-linux-gnu
//!     cargo run -p xtask -- build-extension --package server --artifact server_extension --lib-name sv
use clap::{Parser, Subcommand};
use std::{fs, path::PathBuf, process::Command, string::ToString};

// Defaults. Each one can be overridden per-invocation with a flag; these
// constants just set what happens when the flag is omitted.

// Placeholder base name for the compiled extension (matches the
// .gdextension [libraries] table). Override with --lib-name.
const DEFAULT_GODOT_LIB_NAME: &str = "rj";
// Package name (for `cargo build -p ...`). Override with --package.
const DEFAULT_EXTENSION_PACKAGE: &str = "rj_ext";
// [lib] name in the target crate's Cargo.toml: what the compiled artifact
// is actually called on disk, which can differ from the package name
// above. Override with --artifact.
const DEFAULT_EXTENSION_ARTIFACT: &str = "rj_extension";
// Where the renamed file gets copied to. Override with --out.
const DEFAULT_OUT_DIR: &str = "godot_project/bin";

#[derive(Parser)]
#[command(name = "xtask", bin_name = "cargo run -p xtask --")]
struct Cli {
  #[command(subcommand)]
  command: Commands,
}

#[derive(Subcommand)]
enum Commands {
  /// Build the GDExtension shared library and copy it into a Godot-readable bin/ folder.
  BuildExtension {
    /// Build in release mode instead of debug.
    #[arg(long)]
    release: bool,

    /// Cross-compilation target triple, e.g. aarch64-unknown-linux-gnu.
    #[arg(long)]
    target: Option<String>,

    /// Directory the renamed library gets copied into.
    #[arg(long, default_value = DEFAULT_OUT_DIR)]
    out: PathBuf,

    /// Crate to build (passed to `cargo build -p`).
    #[arg(long, default_value_t = DEFAULT_EXTENSION_PACKAGE.to_string())]
    package: String,

    /// The [lib] name in that crate's Cargo.toml (the on-disk artifact name).
    #[arg(long, default_value_t = DEFAULT_EXTENSION_ARTIFACT.to_string())]
    artifact: String,

    /// Godot-facing base name, no lib_ prefix and no extension.
    #[arg(long, default_value_t = DEFAULT_GODOT_LIB_NAME.to_string())]
    lib_name: String,
  },
}

fn main() {
  let cli = Cli::parse();
  match cli.command {
    Commands::BuildExtension {
      release,
      target,
      out,
      package,
      artifact,
      lib_name,
    } => build_extension(release, target, out, package, artifact, lib_name),
  }
}

fn cargo_build(pkg: &str, target: &Option<String>, release: bool) {
  let mut cmd = Command::new("cargo"); // swap for "cross" here if cross-compiling without native toolchains
  cmd.arg("build").arg("-p").arg(pkg);
  if release {
    cmd.arg("--release");
  }
  if let Some(t) = target {
    cmd.arg("--target").arg(t);
  }
  let status = cmd.status().expect("failed to invoke cargo");
  assert!(status.success(), "cargo build failed for {pkg}");
}

/// Returns (os_tag, arch_tag) using plain, unambiguous names.
fn os_arch(target: &Option<String>) -> (&'static str, &'static str) {
  match target {
    Some(t) => {
      let os = if t.contains("windows") {
        "windows"
      } else if t.contains("apple") {
        "macos"
      } else if t.contains("linux") {
        "linux"
      } else {
        panic!("unrecognized target triple: {t}");
      };
      let arch = if t.contains("x86_64") {
        "x86_64"
      } else if t.contains("aarch64") {
        "arm64"
      } else if t.contains("i686") {
        "x86_32"
      } else if t.contains("riscv64") {
        "rv64"
      } else {
        "unknown"
      };
      (os, arch)
    }
    None => (
      match std::env::consts::OS {
        "windows" => "windows",
        "macos" => "macos",
        "linux" => "linux",
        other => panic!("unsupported host OS: {other}"),
      },
      match std::env::consts::ARCH {
        "x86_64" => "x86_64",
        "aarch64" => "arm64",
        "x86" => "x86_32",
        "riscv64" => "rv64",
        other => panic!("unsupported host arch: {other}"),
      },
    ),
  }
}

fn target_subdir(target: &Option<String>, release: bool) -> String {
  let profile = if release { "release" } else { "debug" };
  match target {
    Some(t) => format!("target/{t}/{profile}"),
    None => format!("target/{profile}"),
  }
}

// build-extension: fixed directory, platform-encoded filename
fn build_extension(
  release: bool,
  target: Option<String>,
  out_dir: PathBuf,
  package: String,
  artifact: String,
  godot_lib_name: String,
) {
  cargo_build(&package, &target, release);

  let (os, arch) = os_arch(&target);
  let (ext, prefix) = match os {
    "windows" => ("dll", ""),
    "macos" => ("dylib", "lib"),
    "linux" => ("so", "lib"),
    _ => unreachable!(),
  };

  let src =
    PathBuf::from(target_subdir(&target, release)).join(format!("{prefix}{artifact}.{ext}"));

  let build_type = if release { "release" } else { "debug" };
  let filename = if os == "macos" {
    // macos entries in the .gdextension file carry no arch suffix.
    format!("lib_{godot_lib_name}.{os}.{build_type}.{ext}")
  } else {
    format!("lib_{godot_lib_name}.{os}.{build_type}.{arch}.{ext}")
  };
  let dst = out_dir.join(filename);

  fs::create_dir_all(&out_dir).expect("failed to create godot bin dir");
  fs::copy(&src, &dst)
    .unwrap_or_else(|e| panic!("failed to copy {} -> {}: {e}", src.display(), dst.display()));
  println!("-> {}", dst.display());
}
