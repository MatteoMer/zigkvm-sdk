const std = @import("std");

/// Jolt backend encoder for host-side input preparation.
/// Adds an 8-byte size header: data size as little-endian u64.
/// This matches how the jolt guest backend reads input from the JoltDevice input region.
pub const Encoder = struct {
    allocator: std.mem.Allocator,
    data: std.ArrayListUnmanaged(u8),

    const Self = @This();

    /// Header size for Jolt input (8 bytes for data size)
    pub const HEADER_SIZE: usize = 8;

    /// Maximum input size (4KB, matching default Jolt MemoryConfig)
    pub const MAX_INPUT: usize = 4096;

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .data = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.data.deinit(self.allocator);
    }

    /// Write a typed value with automatic little-endian serialization
    pub fn write(self: *Self, value: anytype) !void {
        const T = @TypeOf(value);
        const type_info = @typeInfo(T);

        switch (type_info) {
            .int, .comptime_int => {
                const IntType = if (type_info == .comptime_int) i64 else T;
                var bytes: [@sizeOf(IntType)]u8 = undefined;
                std.mem.writeInt(IntType, &bytes, @intCast(value), .little);
                try self.data.appendSlice(self.allocator, &bytes);
            },
            .float, .comptime_float => {
                const FloatType = if (type_info == .comptime_float) f64 else T;
                const IntType = std.meta.Int(.unsigned, @bitSizeOf(FloatType));
                var bytes: [@sizeOf(FloatType)]u8 = undefined;
                std.mem.writeInt(IntType, &bytes, @bitCast(value), .little);
                try self.data.appendSlice(self.allocator, &bytes);
            },
            .@"struct" => {
                const bytes = std.mem.asBytes(&value);
                try self.data.appendSlice(self.allocator, bytes);
            },
            .array => |arr| {
                if (arr.child == u8) {
                    try self.data.appendSlice(self.allocator, &value);
                } else {
                    @compileError("Only u8 arrays are supported. Use writeBytes for other arrays.");
                }
            },
            .pointer => |ptr| {
                if (ptr.size == .Slice and ptr.child == u8) {
                    try self.data.appendSlice(self.allocator, value);
                } else {
                    @compileError("Only []const u8 slices are supported. Use writeBytes.");
                }
            },
            else => @compileError("Unsupported type for write(). Use writeBytes() for raw data."),
        }
    }

    /// Write raw bytes
    pub fn writeBytes(self: *Self, bytes: []const u8) !void {
        try self.data.appendSlice(self.allocator, bytes);
    }

    /// Get current data size (for Input.size() compatibility)
    pub fn dataSize(self: *const Self) usize {
        return self.data.items.len;
    }

    /// Get the encoded bytes with Jolt header
    /// Format: 8 bytes size (little-endian u64) + data
    pub fn toBytes(self: *Self) ![]const u8 {
        const data_size = self.data.items.len;

        if (data_size > MAX_INPUT) {
            return error.InputTooLarge;
        }

        const total_size = HEADER_SIZE + data_size;
        const result = try self.allocator.alloc(u8, total_size);
        errdefer self.allocator.free(result);

        // Data size (0-7): little-endian u64
        std.mem.writeInt(u64, result[0..8], data_size, .little);

        // Copy data (8+)
        @memcpy(result[HEADER_SIZE..], self.data.items);

        return result;
    }
};

// Tests
test "jolt encoder - single u64 with header" {
    const allocator = std.testing.allocator;

    var encoder = Encoder.init(allocator);
    defer encoder.deinit();

    try encoder.write(@as(u64, 0x123456789ABCDEF0));
    const result = try encoder.toBytes();
    defer allocator.free(result);

    // Header (8) + data (8) = 16 bytes
    try std.testing.expectEqual(@as(usize, 16), result.len);

    // Check size field
    const size = std.mem.readInt(u64, result[0..8], .little);
    try std.testing.expectEqual(@as(u64, 8), size);

    // Check data
    const value = std.mem.readInt(u64, result[8..16], .little);
    try std.testing.expectEqual(@as(u64, 0x123456789ABCDEF0), value);
}

test "jolt encoder - multiple values" {
    const allocator = std.testing.allocator;

    var encoder = Encoder.init(allocator);
    defer encoder.deinit();

    try encoder.write(@as(u32, 100));
    try encoder.write(@as(u32, 200));
    try encoder.writeBytes(&[_]u8{ 1, 2, 3 });

    const result = try encoder.toBytes();
    defer allocator.free(result);

    // Size field should be 11 (4 + 4 + 3)
    const size = std.mem.readInt(u64, result[0..8], .little);
    try std.testing.expectEqual(@as(u64, 11), size);

    // Total length: header (8) + data (11) = 19
    try std.testing.expectEqual(@as(usize, 19), result.len);
}

test "jolt encoder - empty input" {
    const allocator = std.testing.allocator;

    var encoder = Encoder.init(allocator);
    defer encoder.deinit();

    const result = try encoder.toBytes();
    defer allocator.free(result);

    // Just the header
    try std.testing.expectEqual(@as(usize, 8), result.len);

    // Size should be 0
    const size = std.mem.readInt(u64, result[0..8], .little);
    try std.testing.expectEqual(@as(u64, 0), size);
}
