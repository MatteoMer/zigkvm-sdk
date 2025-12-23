const std = @import("std");

/// Native backend encoder for host-side input preparation.
/// Simply collects bytes without any header - used for testing.
pub const Encoder = struct {
    allocator: std.mem.Allocator,
    data: std.ArrayListUnmanaged(u8),

    const Self = @This();

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

    /// Get the encoded bytes (native: no header, just raw data)
    pub fn toBytes(self: *Self) ![]const u8 {
        const result = try self.allocator.alloc(u8, self.data.items.len);
        @memcpy(result, self.data.items);
        return result;
    }
};

// Tests
test "native encoder - single u64" {
    const allocator = std.testing.allocator;

    var encoder = Encoder.init(allocator);
    defer encoder.deinit();

    try encoder.write(@as(u64, 0x123456789ABCDEF0));
    const result = try encoder.toBytes();
    defer allocator.free(result);

    try std.testing.expectEqual(@as(usize, 8), result.len);

    const value = std.mem.readInt(u64, result[0..8], .little);
    try std.testing.expectEqual(@as(u64, 0x123456789ABCDEF0), value);
}

test "native encoder - multiple values" {
    const allocator = std.testing.allocator;

    var encoder = Encoder.init(allocator);
    defer encoder.deinit();

    try encoder.write(@as(u32, 100));
    try encoder.write(@as(u32, 200));
    try encoder.writeBytes(&[_]u8{ 1, 2, 3 });

    const result = try encoder.toBytes();
    defer allocator.free(result);

    try std.testing.expectEqual(@as(usize, 11), result.len);

    const val1 = std.mem.readInt(u32, result[0..4], .little);
    const val2 = std.mem.readInt(u32, result[4..8], .little);
    try std.testing.expectEqual(@as(u32, 100), val1);
    try std.testing.expectEqual(@as(u32, 200), val2);
}

test "native encoder - struct" {
    const allocator = std.testing.allocator;

    const TestStruct = packed struct {
        a: u32,
        b: u32,
    };

    var encoder = Encoder.init(allocator);
    defer encoder.deinit();

    try encoder.write(TestStruct{ .a = 10, .b = 20 });
    const result = try encoder.toBytes();
    defer allocator.free(result);

    try std.testing.expectEqual(@as(usize, 8), result.len);

    const a = std.mem.readInt(u32, result[0..4], .little);
    const b = std.mem.readInt(u32, result[4..8], .little);
    try std.testing.expectEqual(@as(u32, 10), a);
    try std.testing.expectEqual(@as(u32, 20), b);
}
