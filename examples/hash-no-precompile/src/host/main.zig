//! Hash Example (No Precompiles) - Host Program
//!
//! This program prepares input for the hash example guest.
//! It writes input data to input.bin which the guest will hash using
//! Zig's standard library crypto implementations.

const std = @import("std");
const host = @import("zigkvm_host");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var input = host.Input.init(allocator);
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

    try input.toFile("input.bin");

    std.debug.print("Generated input.bin with {d} bytes\n", .{input.size()});
    std.debug.print("\nThis input will be processed by:\n", .{});
    std.debug.print("  - Keccak-256 (std.crypto) x100 iterations (outputs slots 0-7)\n", .{});
    std.debug.print("  - SHA-256 (std.crypto) x100 iterations (outputs slots 8-15)\n", .{});
    std.debug.print("  - Input length (output slot 16)\n", .{});
    std.debug.print("  - Iteration count (output slot 17)\n", .{});
}

test "hash-no-precompile host prepares correct input" {
    const allocator = std.testing.allocator;

    var input = host.Input.init(allocator);
    defer input.deinit();

    try input.writeBytes("test message");

    const bytes = try input.toBytes();
    defer allocator.free(bytes);

    // Verify some bytes were encoded
    try std.testing.expect(bytes.len >= 12);
}

test "hash-no-precompile host can read outputs" {
    const allocator = std.testing.allocator;

    // Create mock output data with 18 output slots
    // Format: count(18) + keccak[0-7] + sha256[8-15] + length + iterations
    var output_bytes = [_]u8{0} ** 76; // 4 + 18*4 = 76 bytes

    std.mem.writeInt(u32, output_bytes[0..4], 18, .little); // count = 18

    // Mock keccak output (slots 0-7)
    std.mem.writeInt(u32, output_bytes[4..8], 0xDEADBEEF, .little);
    std.mem.writeInt(u32, output_bytes[8..12], 0x12345678, .little);

    // Mock sha256 output (slots 8-15)
    std.mem.writeInt(u32, output_bytes[36..40], 0xCAFEBABE, .little);

    // Mock input length (slot 16)
    std.mem.writeInt(u32, output_bytes[68..72], 44, .little);

    // Mock iteration count (slot 17)
    std.mem.writeInt(u32, output_bytes[72..76], 100, .little);

    var output = try host.Output.fromBytes(allocator, &output_bytes);
    defer output.deinit();

    try std.testing.expectEqual(@as(u32, 18), output.count());
    try std.testing.expectEqual(@as(u32, 44), output.read(16));
    try std.testing.expectEqual(@as(u32, 100), output.read(17));
}
