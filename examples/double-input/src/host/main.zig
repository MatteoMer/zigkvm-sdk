const std = @import("std");
const runtime = @import("zigkvm_runtime");
const build_options = @import("build_options");

/// Host program for the double-input example.
/// Executes the guest program using the runtime API.
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

    try input.write(input_value);

    std.debug.print("Input: {d}, expected output: {d}\n", .{ input_value, input_value * 2 });

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

    if (result.output.count() >= 2) {
        const output_value = result.output.readU64(0);
        std.debug.print("Output: {d}\n", .{output_value});
    } else {
        std.debug.print("Output count: {d}\n", .{result.output.count()});
    }
}

const host = @import("zigkvm_host");

test "double-input host prepares correct input" {
    const allocator = std.testing.allocator;

    var input = host.Input.initWithBackend(allocator, .zisk);
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
