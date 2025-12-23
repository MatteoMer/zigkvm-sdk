const std = @import("std");
const host = @import("zigkvm_host");

/// Host program for the Ligero private-input example.
/// Prepares public and private inputs for the guest program.
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

    var input = host.Input.init(allocator);
    defer input.deinit();

    try input.writePublic(expected);
    try input.writePrivate(secret);

    try input.toFile("input.bin");

    std.debug.print("Generated input.bin\n", .{});
    std.debug.print("  Public expected: {d}\n", .{expected});
    std.debug.print("  Private secret:  {d}\n", .{secret});
    std.debug.print("Guest output (u64): {d}\n", .{expected});
}

test "ligero private input encodes public and private payloads" {
    const allocator = std.testing.allocator;

    var input = host.Input.init(allocator);
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
