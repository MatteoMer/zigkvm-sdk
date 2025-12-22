const std = @import("std");
const host = @import("zigkvm_host");

/// Host program for the double-input example.
/// Prepares input for the guest program.
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const input_value: u64 = if (args.len > 1)
        std.fmt.parseInt(u64, args[1], 10) catch {
            std.debug.print("Usage: {s} [input_value]\n", .{args[0]});
            std.debug.print("  input_value: u64 to double (default: 21)\n", .{});
            return;
        }
    else
        21; // Default value

    // Prepare input using host API
    var input = host.Input.init(allocator);
    defer input.deinit();

    try input.write(input_value);

    // Write to file
    try input.toFile("input.bin");

    std.debug.print("Generated input.bin with value: {d}\n", .{input_value});
    std.debug.print("Expected output: {d}\n", .{input_value * 2});
}

test "double-input host prepares correct input" {
    const allocator = std.testing.allocator;

    var input = host.Input.init(allocator);
    defer input.deinit();

    try input.write(@as(u64, 42));

    const bytes = try input.toBytes();
    defer allocator.free(bytes);

    // Verify the input was encoded correctly
    try std.testing.expect(bytes.len >= 8);
}

test "double-input host can read outputs" {
    const allocator = std.testing.allocator;

    // Create mock output data
    var output_bytes = [_]u8{0} ** 12;
    std.mem.writeInt(u32, output_bytes[0..4], 2, .little); // count = 2
    std.mem.writeInt(u32, output_bytes[4..8], 84, .little); // low = 84
    std.mem.writeInt(u32, output_bytes[8..12], 0, .little); // high = 0

    var output = try host.Output.fromBytes(allocator, &output_bytes);
    defer output.deinit();

    try std.testing.expectEqual(@as(u32, 2), output.count());
    try std.testing.expectEqual(@as(u64, 84), output.readU64(0));
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
        std.debug.print("  const result = output.readU64(0);\n", .{});
        std.debug.print("  std.debug.print(\"Result: {{d}}\\n\", .{{result}});\n", .{});
        return;
    };
    defer output_file.close();

    std.debug.print("\n--- Reading zkVM Outputs ---\n", .{});

    var output = try host.Output.fromFile(allocator, "proofs/output.bin");
    defer output.deinit();

    std.debug.print("Output count: {d}\n", .{output.count()});

    if (output.count() >= 2) {
        const result = output.readU64(0);
        std.debug.print("Result (u64 at slot 0): {d}\n", .{result});
    }

    std.debug.print("\nAll output slots:\n", .{});
    for (output.slice(), 0..) |value, i| {
        std.debug.print("  slot[{d}] = {d} (0x{x:0>8})\n", .{ i, value, value });
    }
}
