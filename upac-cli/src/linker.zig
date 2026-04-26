// ── Imports ─────────────────────────────────────────────────────────────────────
// Zig build bridge: links the Rust static library and provides the final executable.
const std = @import("std");
const os = std.os;

// ── External Rust ABI ───────────────────────────────────────────────────────
// Declare the C-compatible function exported from the Rust static library.
// Rust signature: fn rust_main(argc: c_int, argv: *const *const std::ffi::c_char) -> c_int
// This is a pointer to an array of C string pointers (char** in C)
extern fn rust_main(argc: os.linux.c_int, argv: [*:null]?[*:0]u8) callconv(.C) os.linux.c_int;

// ── Main Entry Point ───────────────────────────────────────────────────────────────
// The main entry point for the final executable.
// Captures raw argc/argv from the OS and bridges them to the Rust CLI.
pub fn main() !void {
    // Get the command-line arguments from the OS
    const args = try std.process.argsAlloc(std.heap.page_allocator);
    defer std.process.argsFree(std.heap.page_allocator, args);

    // Convert the argument slice to the format expected by rust_main
    // argv is [*:null]?[*:0]u8 - array of pointers to null-terminated strings
    const argv_ptrs = try std.heap.page_allocator.alloc([*:0]u8, args.len);
    defer std.heap.page_allocator.free(argv_ptrs);

    for (args, 0..) |arg, i| {
        argv_ptrs[i] = arg.ptr;
    }

    // Call the Rust main function and exit with its return code
    const exit_code = @call(.{}, rust_main, .{ @intCast(os.linux.c_int, args.len), argv_ptrs.ptr });

    os.exit(@intCast(os.linux.c_int, exit_code));
}