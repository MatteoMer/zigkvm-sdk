//! Hash Precompiles Example - Host Program
//!
//! This program prepares input for the hash precompiles example guest.
//! It writes input data to input.bin which the guest will hash using
//! the keccakF and sha256F precompiles.

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
    std.debug.print("  - Keccak-f[1600] permutation (outputs slots 0-7)\n", .{});
    std.debug.print("  - SHA-256 extend/compress (outputs slots 8-15)\n", .{});
    std.debug.print("  - Input length (output slot 16)\n", .{});
}

test "hash-precompiles host prepares correct input" {
    const allocator = std.testing.allocator;

    var input = host.Input.init(allocator);
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
