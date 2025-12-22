const std = @import("std");
const host = @import("zkvm_host");

/// Host program for the bytes-sum example.
/// Prepares input bytes for the guest program to sum.
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Prepare input using host API
    var input = host.Input.init(allocator);
    defer input.deinit();

    var expected_sum: u64 = 0;

    if (args.len > 1) {
        // Use provided bytes as input
        for (args[1..]) |arg| {
            const byte = std.fmt.parseInt(u8, arg, 10) catch {
                std.debug.print("Invalid byte value: {s}\n", .{arg});
                std.debug.print("Usage: {s} [byte1 byte2 ...]\n", .{args[0]});
                return;
            };
            try input.write(byte);
            expected_sum += byte;
        }
    } else {
        // Default: use "hello" as input
        const default_input = "hello";
        try input.writeBytes(default_input);
        for (default_input) |byte| {
            expected_sum += byte;
        }
    }

    // Write to file
    try input.toFile("input.bin");

    std.debug.print("Generated input.bin with {d} bytes\n", .{input.size()});
    std.debug.print("Expected sum: {d}\n", .{expected_sum});
}

test "bytes-sum host prepares correct input" {
    const allocator = std.testing.allocator;

    var input = host.Input.init(allocator);
    defer input.deinit();

    try input.writeBytes("test");

    const bytes = try input.toBytes();
    defer allocator.free(bytes);

    // Verify some bytes were encoded
    try std.testing.expect(bytes.len >= 4);
}

test "bytes-sum host can read outputs" {
    const allocator = std.testing.allocator;

    // Create mock output data
    // Format: count(3) + sum_low + sum_high + length
    var output_bytes = [_]u8{0} ** 16;
    std.mem.writeInt(u32, output_bytes[0..4], 3, .little); // count = 3
    std.mem.writeInt(u32, output_bytes[4..8], 532, .little); // sum low
    std.mem.writeInt(u32, output_bytes[8..12], 0, .little); // sum high
    std.mem.writeInt(u32, output_bytes[12..16], 5, .little); // length

    var output = try host.Output.fromBytes(allocator, &output_bytes);
    defer output.deinit();

    try std.testing.expectEqual(@as(u32, 3), output.count());
    try std.testing.expectEqual(@as(u64, 532), output.readU64(0));
    try std.testing.expectEqual(@as(u32, 5), output.read(2));
}
