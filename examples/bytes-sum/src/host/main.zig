const std = @import("std");
const host = @import("zigkvm_host");

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

test "reading outputs from zkVM proof (example)" {
    const allocator = std.testing.allocator;

    // This test demonstrates how to read outputs from a zkVM execution.
    // After running `zig build prove`, the output.bin file contains the results.

    // Try to read outputs if the file exists (from a previous proof)
    const output_file = std.fs.cwd().openFile("proofs/output.bin", .{}) catch {
        std.debug.print("\n--- Output Reading Example ---\n", .{});
        std.debug.print("No proofs/output.bin found (run `zig build prove` first)\n", .{});
        std.debug.print("\nExample code to read outputs:\n\n", .{});
        std.debug.print("  var output = try host.Output.fromFile(allocator, \"proofs/output.bin\");\n", .{});
        std.debug.print("  defer output.deinit();\n\n", .{});
        std.debug.print("  const sum = output.readU64(0);\n", .{});
        std.debug.print("  const length = output.read(2);\n", .{});
        std.debug.print("  std.debug.print(\"Sum: {{d}}, Length: {{d}}\\n\", .{{sum, length}});\n", .{});
        return;
    };
    defer output_file.close();

    std.debug.print("\n--- Reading zkVM Outputs ---\n", .{});

    var output = try host.Output.fromFile(allocator, "proofs/output.bin");
    defer output.deinit();

    std.debug.print("Output count: {d}\n", .{output.count()});

    // For bytes-sum, we expect:
    // - sum (u64) at slot 0-1
    // - length (u32) at slot 2
    if (output.count() >= 2) {
        const sum = output.readU64(0);
        std.debug.print("Sum (u64 at slot 0): {d}\n", .{sum});
    }

    if (output.count() >= 3) {
        const length = output.read(2);
        std.debug.print("Length (u32 at slot 2): {d}\n", .{length});
    }

    std.debug.print("\nAll output slots:\n", .{});
    for (output.slice(), 0..) |value, i| {
        std.debug.print("  slot[{d}] = {d} (0x{x:0>8})\n", .{ i, value, value });
    }
}
