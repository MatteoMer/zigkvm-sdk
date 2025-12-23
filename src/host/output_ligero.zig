const std = @import("std");

/// Ligero backend output decoder.
/// Extracts committed values from output files.
///
/// Format: Same as native/zisk for compatibility:
/// - 4 bytes: output count (u32, little-endian)
/// - N*4 bytes: output values (u32 array, little-endian)
///
/// Future enhancement: Parse Ligero proof format to extract public outputs directly.
pub const Decoder = struct {
    allocator: std.mem.Allocator,
    values: []u32,
    output_count: u32,

    const Self = @This();

    pub const MAX_OUTPUT_COUNT: usize = 64;

    /// Load outputs from a file
    pub fn fromFile(allocator: std.mem.Allocator, path: []const u8) !Self {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const bytes = try file.readToEndAlloc(allocator, 1024 * 1024);
        defer allocator.free(bytes);

        return try fromBytes(allocator, bytes);
    }

    /// Load outputs from raw bytes
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

    /// Free resources
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.values);
    }

    /// Get the number of output values
    pub fn count(self: *const Self) u32 {
        return self.output_count;
    }

    /// Read a u32 output value at the given index
    pub fn read(self: *const Self, index: usize) u32 {
        if (index >= self.output_count) return 0;
        return self.values[index];
    }

    /// Read a u64 output value from two consecutive slots
    /// Low 32 bits from index, high 32 bits from index+1
    pub fn readU64(self: *const Self, index: usize) u64 {
        const low: u64 = self.read(index);
        const high: u64 = self.read(index + 1);
        return low | (high << 32);
    }

    /// Get all outputs as a slice
    pub fn slice(self: *const Self) []const u32 {
        return self.values;
    }
};

// =============================================================================
// Tests
// =============================================================================

test "ligero output decoder - single u32" {
    const allocator = std.testing.allocator;

    var bytes = [_]u8{0} ** 8;
    std.mem.writeInt(u32, bytes[0..4], 1, .little);
    std.mem.writeInt(u32, bytes[4..8], 42, .little);

    var decoder = try Decoder.fromBytes(allocator, &bytes);
    defer decoder.deinit();

    try std.testing.expectEqual(@as(u32, 1), decoder.count());
    try std.testing.expectEqual(@as(u32, 42), decoder.read(0));
}

test "ligero output decoder - multiple values" {
    const allocator = std.testing.allocator;

    var bytes = [_]u8{0} ** 16;
    std.mem.writeInt(u32, bytes[0..4], 3, .little);
    std.mem.writeInt(u32, bytes[4..8], 100, .little);
    std.mem.writeInt(u32, bytes[8..12], 200, .little);
    std.mem.writeInt(u32, bytes[12..16], 300, .little);

    var decoder = try Decoder.fromBytes(allocator, &bytes);
    defer decoder.deinit();

    try std.testing.expectEqual(@as(u32, 3), decoder.count());
    try std.testing.expectEqual(@as(u32, 100), decoder.read(0));
    try std.testing.expectEqual(@as(u32, 200), decoder.read(1));
    try std.testing.expectEqual(@as(u32, 300), decoder.read(2));
}

test "ligero output decoder - u64 value" {
    const allocator = std.testing.allocator;

    var bytes = [_]u8{0} ** 12;
    std.mem.writeInt(u32, bytes[0..4], 2, .little);
    // 0x123456789ABCDEF0 split into low and high u32
    std.mem.writeInt(u32, bytes[4..8], 0x9ABCDEF0, .little);
    std.mem.writeInt(u32, bytes[8..12], 0x12345678, .little);

    var decoder = try Decoder.fromBytes(allocator, &bytes);
    defer decoder.deinit();

    try std.testing.expectEqual(@as(u64, 0x123456789ABCDEF0), decoder.readU64(0));
}

test "ligero output decoder - empty" {
    const allocator = std.testing.allocator;

    var bytes = [_]u8{0} ** 4;
    std.mem.writeInt(u32, bytes[0..4], 0, .little);

    var decoder = try Decoder.fromBytes(allocator, &bytes);
    defer decoder.deinit();

    try std.testing.expectEqual(@as(u32, 0), decoder.count());
    try std.testing.expectEqual(@as(usize, 0), decoder.slice().len);
}

test "ligero output decoder - out of bounds read" {
    const allocator = std.testing.allocator;

    var bytes = [_]u8{0} ** 8;
    std.mem.writeInt(u32, bytes[0..4], 1, .little);
    std.mem.writeInt(u32, bytes[4..8], 42, .little);

    var decoder = try Decoder.fromBytes(allocator, &bytes);
    defer decoder.deinit();

    // Out of bounds should return 0
    try std.testing.expectEqual(@as(u32, 0), decoder.read(1));
    try std.testing.expectEqual(@as(u32, 0), decoder.read(100));
}

test "ligero output decoder - invalid format" {
    const allocator = std.testing.allocator;

    // Too short
    const short_bytes = [_]u8{ 1, 2 };
    try std.testing.expectError(error.InvalidOutputFormat, Decoder.fromBytes(allocator, &short_bytes));

    // Count says 10 but only 1 value provided
    var bad_bytes = [_]u8{0} ** 8;
    std.mem.writeInt(u32, bad_bytes[0..4], 10, .little);
    try std.testing.expectError(error.InvalidOutputFormat, Decoder.fromBytes(allocator, &bad_bytes));
}

test "ligero output decoder - too many outputs" {
    const allocator = std.testing.allocator;

    var bytes = [_]u8{0} ** 4;
    std.mem.writeInt(u32, bytes[0..4], 100, .little); // More than MAX_OUTPUT_COUNT

    try std.testing.expectError(error.TooManyOutputs, Decoder.fromBytes(allocator, &bytes));
}
