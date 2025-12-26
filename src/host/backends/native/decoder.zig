const std = @import("std");

/// Native backend output decoder.
/// Reads outputs from raw bytes (count + values format).
pub const Decoder = struct {
    allocator: std.mem.Allocator,
    values: []u32,
    output_count: u32,

    const Self = @This();

    /// Load from a file
    pub fn fromFile(allocator: std.mem.Allocator, path: []const u8) !Self {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const bytes = try file.readToEndAlloc(allocator, 1024 * 1024); // 1MB max
        defer allocator.free(bytes);

        return try fromBytes(allocator, bytes);
    }

    /// Load from raw bytes
    /// Format: count (u32) + values (array of u32)
    pub fn fromBytes(allocator: std.mem.Allocator, bytes: []const u8) !Self {
        if (bytes.len < 4) {
            return error.InvalidOutputFormat;
        }

        const output_count = std.mem.readInt(u32, bytes[0..4], .little);
        const expected_size = 4 + (output_count * 4);

        if (bytes.len < expected_size) {
            return error.InvalidOutputFormat;
        }

        // Copy values
        const values = try allocator.alloc(u32, output_count);
        errdefer allocator.free(values);

        for (0..output_count) |i| {
            const offset = 4 + (i * 4);
            values[i] = std.mem.readInt(u32, bytes[offset..][0..4], .little);
        }

        return .{
            .allocator = allocator,
            .values = values,
            .output_count = output_count,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.values);
    }

    pub fn count(self: *const Self) u32 {
        return self.output_count;
    }

    pub fn read(self: *const Self, index: usize) u32 {
        if (index >= self.output_count) return 0;
        return self.values[index];
    }

    pub fn readU64(self: *const Self, index: usize) u64 {
        const low: u64 = self.read(index);
        const high: u64 = self.read(index + 1);
        return low | (high << 32);
    }

    pub fn slice(self: *const Self) []const u32 {
        return self.values;
    }
};

// Tests
test "native output decoder - single u32" {
    const allocator = std.testing.allocator;

    // Format: count (1) + value (42)
    var bytes = [_]u8{0} ** 8;
    std.mem.writeInt(u32, bytes[0..4], 1, .little); // count = 1
    std.mem.writeInt(u32, bytes[4..8], 42, .little); // value = 42

    var decoder = try Decoder.fromBytes(allocator, &bytes);
    defer decoder.deinit();

    try std.testing.expectEqual(@as(u32, 1), decoder.count());
    try std.testing.expectEqual(@as(u32, 42), decoder.read(0));
}

test "native output decoder - multiple values" {
    const allocator = std.testing.allocator;

    // Format: count (3) + values (10, 20, 30)
    var bytes = [_]u8{0} ** 16;
    std.mem.writeInt(u32, bytes[0..4], 3, .little); // count = 3
    std.mem.writeInt(u32, bytes[4..8], 10, .little);
    std.mem.writeInt(u32, bytes[8..12], 20, .little);
    std.mem.writeInt(u32, bytes[12..16], 30, .little);

    var decoder = try Decoder.fromBytes(allocator, &bytes);
    defer decoder.deinit();

    try std.testing.expectEqual(@as(u32, 3), decoder.count());
    try std.testing.expectEqual(@as(u32, 10), decoder.read(0));
    try std.testing.expectEqual(@as(u32, 20), decoder.read(1));
    try std.testing.expectEqual(@as(u32, 30), decoder.read(2));
}

test "native output decoder - u64" {
    const allocator = std.testing.allocator;

    // Format: count (2) + low (0xABCDEF12) + high (0x34567890)
    var bytes = [_]u8{0} ** 12;
    std.mem.writeInt(u32, bytes[0..4], 2, .little); // count = 2
    std.mem.writeInt(u32, bytes[4..8], 0xABCDEF12, .little); // low
    std.mem.writeInt(u32, bytes[8..12], 0x34567890, .little); // high

    var decoder = try Decoder.fromBytes(allocator, &bytes);
    defer decoder.deinit();

    const value = decoder.readU64(0);
    const expected: u64 = 0xABCDEF12 | (@as(u64, 0x34567890) << 32);
    try std.testing.expectEqual(expected, value);
}
