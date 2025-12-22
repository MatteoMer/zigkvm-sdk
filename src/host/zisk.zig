const std = @import("std");

/// ZisK backend encoder for host-side input preparation.
/// Adds a 16-byte header: 8 bytes reserved + 8 bytes size (little-endian u64).
pub const Encoder = struct {
    allocator: std.mem.Allocator,
    data: std.ArrayListUnmanaged(u8),

    const Self = @This();

    /// Header size for ZisK input files
    pub const HEADER_SIZE: usize = 16;
    const RESERVED_SIZE: usize = 8;
    const SIZE_FIELD_SIZE: usize = 8;

    /// Maximum input size (matches zkvm guest limit)
    pub const MAX_INPUT: usize = 0x2000; // 8KB

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

    /// Get the encoded bytes with ZisK header
    /// Format: 8 bytes reserved (zeros) + 8 bytes size (little-endian u64) + data
    pub fn toBytes(self: *Self) ![]const u8 {
        const data_size = self.data.items.len;

        if (data_size > MAX_INPUT) {
            return error.InputTooLarge;
        }

        const total_size = HEADER_SIZE + data_size;
        const result = try self.allocator.alloc(u8, total_size);
        errdefer self.allocator.free(result);

        // Reserved bytes (0-7): all zeros
        @memset(result[0..RESERVED_SIZE], 0);

        // Data size (8-15): little-endian u64
        std.mem.writeInt(u64, result[RESERVED_SIZE..][0..SIZE_FIELD_SIZE], data_size, .little);

        // Copy data (16+)
        @memcpy(result[HEADER_SIZE..], self.data.items);

        return result;
    }
};

// Tests
test "zisk encoder - single u64 with header" {
    const allocator = std.testing.allocator;

    var encoder = Encoder.init(allocator);
    defer encoder.deinit();

    try encoder.write(@as(u64, 0x123456789ABCDEF0));
    const result = try encoder.toBytes();
    defer allocator.free(result);

    // Header (16) + data (8) = 24 bytes
    try std.testing.expectEqual(@as(usize, 24), result.len);

    // Check reserved bytes are zero
    for (result[0..8]) |byte| {
        try std.testing.expectEqual(@as(u8, 0), byte);
    }

    // Check size field
    const size = std.mem.readInt(u64, result[8..16], .little);
    try std.testing.expectEqual(@as(u64, 8), size);

    // Check data
    const value = std.mem.readInt(u64, result[16..24], .little);
    try std.testing.expectEqual(@as(u64, 0x123456789ABCDEF0), value);
}

test "zisk encoder - multiple values" {
    const allocator = std.testing.allocator;

    var encoder = Encoder.init(allocator);
    defer encoder.deinit();

    try encoder.write(@as(u32, 100));
    try encoder.write(@as(u32, 200));
    try encoder.writeBytes(&[_]u8{ 1, 2, 3 });

    const result = try encoder.toBytes();
    defer allocator.free(result);

    // Size field should be 11 (4 + 4 + 3)
    const size = std.mem.readInt(u64, result[8..16], .little);
    try std.testing.expectEqual(@as(u64, 11), size);

    // Total length: header (16) + data (11) = 27
    try std.testing.expectEqual(@as(usize, 27), result.len);
}

test "zisk encoder - empty input" {
    const allocator = std.testing.allocator;

    var encoder = Encoder.init(allocator);
    defer encoder.deinit();

    const result = try encoder.toBytes();
    defer allocator.free(result);

    // Just the header
    try std.testing.expectEqual(@as(usize, 16), result.len);

    // Size should be 0
    const size = std.mem.readInt(u64, result[8..16], .little);
    try std.testing.expectEqual(@as(u64, 0), size);
}

test "zisk encoder - struct" {
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

    // Header (16) + struct (8) = 24
    try std.testing.expectEqual(@as(usize, 24), result.len);

    // Size should be 8
    const size = std.mem.readInt(u64, result[8..16], .little);
    try std.testing.expectEqual(@as(u64, 8), size);

    // Check struct data
    const a = std.mem.readInt(u32, result[16..20], .little);
    const b = std.mem.readInt(u32, result[20..24], .little);
    try std.testing.expectEqual(@as(u32, 10), a);
    try std.testing.expectEqual(@as(u32, 20), b);
}
