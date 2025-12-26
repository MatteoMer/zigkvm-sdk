const std = @import("std");
const runtime = @import("zigkvm_runtime");
const build_options = @import("build_options");

/// Example: Using the zigkvm runtime API to execute and prove programs
///
/// This demonstrates the library-based approach to ZisK/Ligero:
/// - No CLI commands needed
/// - Programmatic control over execution and proving
/// - Thread-safe for parallel proving
///
/// Usage:
///   zig build -Dbackend=zisk run -- <guest.elf> <input_value>
///   zig build -Dbackend=ligero run -- <guest.wasm> <input_value>
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get backend from build options
    const backend: runtime.Backend = switch (build_options.backend) {
        .zisk => .zisk,
        .ligero => .ligero,
    };

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 3) {
        const backend_name = @tagName(backend);
        const ext = if (backend == .zisk) ".elf" else ".wasm";
        std.debug.print("Usage: {s} <guest{s}> <input_value>\n", .{ args[0], ext });
        std.debug.print("\nBackend: {s} (use -Dbackend=zisk or -Dbackend=ligero)\n", .{backend_name});
        std.debug.print("\nExample:\n", .{});
        if (backend == .zisk) {
            std.debug.print("  zig build -Dbackend=zisk run -- ../double-input/zig-out/bin/double-input-guest 42\n", .{});
        } else {
            std.debug.print("  zig build -Dbackend=ligero run -- ../double-input/zig-out/bin/double-input-guest.wasm 42\n", .{});
        }
        std.debug.print("\nThis will execute the guest program with input 42\n", .{});
        std.debug.print("and print the output (should be 84 for double-input).\n", .{});
        return;
    }

    const guest_path = args[1];
    const input_value = try std.fmt.parseInt(u64, args[2], 10);

    std.debug.print("Backend: {s}\n", .{@tagName(backend)});
    std.debug.print("Guest binary: {s}\n", .{guest_path});
    std.debug.print("Input value: {d}\n", .{input_value});

    // Initialize the runtime
    var rt = try runtime.Runtime.init(allocator, .{
        .backend = backend,
        .guest_binary = guest_path,
        .enable_proving = false, // Just execute, no proof
    });
    defer rt.deinit();

    // Encode input based on backend
    var input_bytes: [32]u8 = undefined;
    var input_len: usize = undefined;

    if (backend == .zisk) {
        // ZisK format: [8 bytes reserved][8 bytes size][data]
        @memset(input_bytes[0..8], 0); // Reserved zeros
        std.mem.writeInt(u64, input_bytes[8..16], 8, .little); // Size = 8 bytes
        std.mem.writeInt(u64, input_bytes[16..24], input_value, .little); // Data
        input_len = 24;
    } else {
        // Ligero format: [public_len:u64][public_data][private_len:u64][private_data]
        // For this example, all input is private
        std.mem.writeInt(u64, input_bytes[0..8], 0, .little); // No public data
        std.mem.writeInt(u64, input_bytes[8..16], 8, .little); // Private len = 8
        std.mem.writeInt(u64, input_bytes[16..24], input_value, .little); // Private data
        input_len = 24;
    }

    std.debug.print("\nExecuting guest program...\n", .{});

    // Execute the guest program
    var result = rt.execute(input_bytes[0..input_len]) catch |err| {
        std.debug.print("Execution failed: {}\n", .{err});
        return err;
    };
    defer result.deinit();

    // Print results
    std.debug.print("\nExecution completed!\n", .{});
    if (result.cycles) |cycles| {
        std.debug.print("Cycles: {d}\n", .{cycles});
    }

    if (result.outputs.count > 0) {
        std.debug.print("Output values:\n", .{});
        for (0..result.outputs.count) |i| {
            std.debug.print("  [{d}] = {d}\n", .{ i, result.outputs.read(i) });
        }

        // For double-input example, read as u64
        if (result.outputs.count >= 2) {
            const output_u64 = result.outputs.readU64(0);
            std.debug.print("\nAs u64: {d}\n", .{output_u64});
        }
    } else {
        std.debug.print("No output values\n", .{});
    }

    // Print stdout/stderr if any
    if (result.stdout) |stdout| {
        if (stdout.len > 0) {
            std.debug.print("\nziskemu stdout:\n{s}\n", .{stdout});
        }
    }
    if (result.stderr) |stderr| {
        if (stderr.len > 0) {
            std.debug.print("\nziskemu stderr:\n{s}\n", .{stderr});
        }
    }
}
