const std = @import("std");
const runtime = @import("zigkvm_runtime");
const build_options = @import("build_options");

/// Host program for the Ligero private-input example.
/// Executes the guest program using the runtime API with public/private separation.
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const secret: u64 = if (args.len > 1)
        std.fmt.parseInt(u64, args[1], 10) catch {
            std.debug.print("Usage: {s} [secret] [expected]\n", .{args[0]});
            std.debug.print("  secret   : private u64 input (default: 11)\n", .{});
            std.debug.print("  expected : public u64 input (default: secret * 3 + 7)\n", .{});
            return;
        }
    else
        11;

    const expected: u64 = if (args.len > 2)
        std.fmt.parseInt(u64, args[2], 10) catch {
            std.debug.print("Usage: {s} [secret] [expected]\n", .{args[0]});
            std.debug.print("  secret   : private u64 input (default: 11)\n", .{});
            std.debug.print("  expected : public u64 input (default: secret * 3 + 7)\n", .{});
            return;
        }
    else
        secret * 3 + 7;

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

    // Prepare input with public/private separation
    var input = rt.createInput();
    defer input.deinit();

    try input.writePublic(expected);
    try input.writePrivate(secret);

    std.debug.print("Public expected: {d}\n", .{expected});
    std.debug.print("Private secret:  {d}\n", .{secret});

    // Also write input.bin for CLI tools compatibility (prove step)
    try input.toFile("input.bin");

    // Get public and private bytes separately
    const public_bytes = try input.getPublicBytes();
    defer if (public_bytes.len > 0) allocator.free(public_bytes);

    const private_bytes = try input.getPrivateBytes();
    defer allocator.free(private_bytes);

    // Execute guest program with public/private separation
    var result = try rt.execute(
        if (public_bytes.len > 0) public_bytes else null,
        private_bytes,
    );
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

test "ligero private input encodes public and private payloads" {
    const allocator = std.testing.allocator;

    var input = host.Input.initWithBackend(allocator, .ligero);
    defer input.deinit();

    try input.writePublic(@as(u64, 10));
    try input.writePrivate(@as(u64, 21));

    const bytes = try input.toBytes();
    defer allocator.free(bytes);

    try std.testing.expectEqual(@as(usize, 32), bytes.len);

    const public_len = std.mem.readInt(u64, bytes[0..8], .little);
    const public_value = std.mem.readInt(u64, bytes[8..16], .little);
    const private_len = std.mem.readInt(u64, bytes[16..24], .little);
    const private_value = std.mem.readInt(u64, bytes[24..32], .little);

    try std.testing.expectEqual(@as(u64, 8), public_len);
    try std.testing.expectEqual(@as(u64, 10), public_value);
    try std.testing.expectEqual(@as(u64, 8), private_len);
    try std.testing.expectEqual(@as(u64, 21), private_value);
}
