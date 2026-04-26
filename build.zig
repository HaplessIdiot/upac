// ── Imports ─────────────────────────────────────────────────────────────────────
// Unified build script for UPAC package manager.
// This script builds the Rust static library, Zig shared libraries, and links them together.
const std = @import("std");

pub fn build(b: *std.Build) void {
    // ── Standard Options ───────────────────────────────────────────────────────────────
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const strip = b.option(bool, "strip", "Strip debug symbols") orelse false;
    const stack_check = b.option(bool, "stack-check", "Check for stack overflows") orelse false;

    // ── Build Core Library (libupac) ─────────────────────────────────────────────
    const upac_lib = b.addSharedLibrary(.{
        .name = "upac",
        .root_source_file = b.path("upac-lib/src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    upac_lib.linkLibC();
    upac_lib.linkSystemLibrary("ostree-1");
    upac_lib.linkSystemLibrary("glib-2.0");
    upac_lib.linkSystemLibrary("gio-2.0");
    upac_lib.linkSystemLibrary("gobject-2.0");

    upac_lib.root_module.strip = strip;
    upac_lib.root_module.stack_check = stack_check;

    b.installArtifact(upac_lib);

    // ── Build Backend: ALPM ───────────────────────────────────────────────────
    const upac_alpm = b.addSharedLibrary(.{
        .name = "upac-alpm",
        .root_source_file = b.path("upac-alpm/src/backend.zig"),
        .target = target,
        .optimize = optimize,
    });

    upac_alpm.linkLibC();
    upac_alpm.linkSystemLibrary("archive");
    upac_alpm.linkLibupac(upac_lib);

    upac_alpm.root_module.strip = strip;
    upac_alpm.root_module.stack_check = stack_check;
    upac_alpm.bundle_compiler_rt = false;
    upac_alpm.link_gc_sections = false;

    b.installArtifact(upac_alpm);

    // ── Build Backend: RPM ──────────────────────────────────────────────────────────
    const upac_rpm = b.addSharedLibrary(.{
        .name = "upac-rpm",
        .root_source_file = b.path("upac-rpm/src/backend.zig"),
        .target = target,
        .optimize = optimize,
    });

    upac_rpm.linkLibC();
    upac_rpm.linkSystemLibrary("archive");
    upac_rpm.linkLibupac(upac_lib);

    upac_rpm.root_module.strip = strip;
    upac_rpm.root_module.stack_check = stack_check;
    upac_rpm.bundle_compiler_rt = false;
    upac_rpm.link_gc_sections = false;

    b.installArtifact(upac_rpm);

    // ── Build Backend: DEB ────────────────────────────────────────────────────
    const upac_deb = b.addSharedLibrary(.{
        .name = "upac-deb",
        .root_source_file = b.path("upac-deb/src/backend.zig"),
        .target = target,
        .optimize = optimize,
    });

    upac_deb.linkLibC();
    upac_deb.linkSystemLibrary("archive");
    upac_deb.linkLibupac(upac_lib);

    upac_deb.root_module.strip = strip;
    upac_deb.root_module.stack_check = stack_check;
    upac_deb.bundle_compiler_rt = false;
    upac_deb.link_gc_sections = false;

    b.installArtifact(upac_deb);

    // ── Build Rust Static Library ────────────────────────────────────────────
    // Run cargo build to create the static library
    const cargo_run = b.addRunProgram(.{
        .argv = &.{ "cargo", "build", "--lib" },
        .cwd = b.path("upac-cli"),
    });

    const cargo_step = b.step("cargo-build", "Build Rust static library");
    cargo_step.dependOn(&cargo_run.step);

    // Find the static library file (depends on optimization mode)
    const static_lib_path = if (optimize == .Debug)
        b.path("upac-cli/target/debug/libupac.rlib")
    else
        b.path("upac-cli/target/release/libupac.rlib");

    // ── Build Final Executable ───────────────────────────────────────────────
    const exe = b.addExecutable(.{
        .name = "upac",
        .root_source_file = b.path("upac-cli/src/linker.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Link the Rust static library
    exe.addObjectFile(static_lib_path);

    // Link system libraries required by Rust
    exe.linkLibC();
    exe.linkSystemLibrary("unwind");
    exe.linkSystemLibrary("pthread");
    exe.linkSystemLibrary("dl");
    exe.linkSystemLibrary("m");

    // Link the core shared library
    exe.linkLibupac(upac_lib);

    // Enable rdynamic for global symbol visibility
    // This allows backend plugins to access symbols from the main executable
    exe.rdynamic = true;

    // Install the executable
    b.installArtifact(exe);
}