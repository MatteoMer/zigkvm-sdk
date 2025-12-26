//! Hash Precompiles Example - Host Program
//!
//! This program executes the hash precompiles example guest using the runtime API.
//! It hashes data using the keccakF and sha256F precompiles.

const std = @import("std");
const runtime = @import("zigkvm_runtime");
const build_options = @import("build_options");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Map build backend to runtime backend
    const backend: runtime.Backend = switch (build_options.backend) {
        .zisk => .zisk,
        .ligero => .ligero,
    };

    // Initialize runtime with guest binary from build options
    var rt = try runtime.Runtime.init(allocator, .{
        .backend = backend,
        .guest_binary = build_options.guest_binary,
    });
    defer rt.deinit();

    // Prepare input using runtime API
    var input = rt.createInput();
    defer input.deinit();

    if (args.len > 1) {
        // Use provided string as input
        const data = args[1];
        try input.writeBytes(data);
        std.debug.print("Using input: \"{s}\"\n", .{data});
    } else {
        // Default test input
        const default_input = "The quick brown fox jumps over the lazy dog";
        try input.writeBytes(default_input);
        std.debug.print("Using default input: \"{s}\"\n", .{default_input});
    }

    std.debug.print("Input size: {d} bytes\n", .{input.size()});

    // Also write input.bin for CLI tools compatibility (prove step)
    try input.toFile("input.bin");

    // Execute guest program
    const private_bytes = try input.getPrivateBytes();
    defer allocator.free(private_bytes);

    var result = try rt.execute(null, private_bytes);
    defer result.deinit();

    // Display results
    std.debug.print("\nExecution completed!\n", .{});
    if (result.cycles) |cycles| {
        std.debug.print("Cycles: {d}\n", .{cycles});
    }

    std.debug.print("Output count: {d}\n", .{result.output.count()});

    if (result.output.count() >= 17) {
        std.debug.print("\nKeccak output (slots 0-7):\n", .{});
        for (0..8) |i| {
            std.debug.print("  slot[{d}] = 0x{x:0>8}\n", .{ i, result.output.read(i) });
        }

        std.debug.print("\nSHA-256 output (slots 8-15):\n", .{});
        for (8..16) |i| {
            std.debug.print("  slot[{d}] = 0x{x:0>8}\n", .{ i, result.output.read(i) });
        }

        std.debug.print("\nInput length: {d}\n", .{result.output.read(16)});
    }
}

const host = @import("zigkvm_host");

test "hash-precompiles host prepares correct input" {
    const allocator = std.testing.allocator;

    var input = host.Input.initWithBackend(allocator, .zisk);
    defer input.deinit();

    try input.writeBytes("test message");

    const bytes = try input.toBytes();
    defer allocator.free(bytes);

    // Verify some bytes were encoded
    try std.testing.expect(bytes.len >= 12);
}

test "hash-precompiles host can read outputs" {
    const allocator = std.testing.allocator;

    // Create mock output data with 17 output slots
    // Format: count(17) + keccak[0-7] + sha256[8-15] + length
    var output_bytes = [_]u8{0} ** 72; // 4 + 17*4 = 72 bytes

    std.mem.writeInt(u32, output_bytes[0..4], 17, .little); // count = 17

    // Mock keccak output (slots 0-7)
    std.mem.writeInt(u32, output_bytes[4..8], 0xDEADBEEF, .little);
    std.mem.writeInt(u32, output_bytes[8..12], 0x12345678, .little);

    // Mock sha256 output (slots 8-15)
    std.mem.writeInt(u32, output_bytes[36..40], 0xCAFEBABE, .little);

    // Mock input length (slot 16)
    std.mem.writeInt(u32, output_bytes[68..72], 44, .little);

    var output = try host.Output.fromBytes(allocator, &output_bytes);
    defer output.deinit();

    try std.testing.expectEqual(@as(u32, 17), output.count());
    try std.testing.expectEqual(@as(u32, 44), output.read(16));
}
