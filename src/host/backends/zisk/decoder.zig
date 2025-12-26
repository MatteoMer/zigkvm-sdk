const std = @import("std");

/// ZisK backend output decoder.
/// Reads outputs from raw bytes (count + values format).
/// Same format as native, so we can reuse the logic.
pub const Decoder = struct {
    allocator: std.mem.Allocator,
    values: []u32,
    output_count: u32,

    const Self = @This();

    /// Maximum output count (matches zkvm guest limit)
    pub const MAX_OUTPUT_COUNT: usize = 64;

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

        if (output_count > MAX_OUTPUT_COUNT) {
            return error.TooManyOutputs;
        }

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
test "zisk output decoder - single u32" {
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

test "zisk output decoder - multiple values" {
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

test "zisk output decoder - u64" {
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

test "zisk output decoder - max count validation" {
    const allocator = std.testing.allocator;

    // Try to create output with too many values
    var bytes = [_]u8{0} ** 4;
    std.mem.writeInt(u32, bytes[0..4], 65, .little); // count = 65 (exceeds MAX_OUTPUT_COUNT)

    const result = Decoder.fromBytes(allocator, &bytes);
    try std.testing.expectError(error.TooManyOutputs, result);
}
