const std = @import("std");

/// Ligero backend encoder for host-side input preparation.
/// Supports separate public and private inputs for proper ZK applications.
///
/// Usage:
/// ```zig
/// var encoder = Encoder.init(allocator);
/// defer encoder.deinit();
///
/// // Public inputs (verifier knows these)
/// try encoder.writePublic(@as(u64, expected_hash));
///
/// // Private witnesses (kept secret)
/// try encoder.writePrivate(@as(u64, secret_value));
///
/// // Get encoded bytes for input.bin
/// const bytes = try encoder.toBytes();
/// ```
///
/// JSON output format:
/// {
///   "program": "app.wasm",
///   "shader-path": "./shader",
///   "packing": 8192,
///   "private-indices": [2],  // arg[2] is private (indices start at 1)
///   "args": [
///     {"hex": "0x...public..."},   // arg[0] - public
///     {"hex": "0x...private..."}   // arg[1] - private
///   ]
/// }
pub const Encoder = struct {
    allocator: std.mem.Allocator,
    public_data: std.ArrayListUnmanaged(u8),
    private_data: std.ArrayListUnmanaged(u8),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .public_data = .{},
            .private_data = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.public_data.deinit(self.allocator);
        self.private_data.deinit(self.allocator);
    }

    // =========================================================================
    // Public Input Functions
    // =========================================================================

    /// Write a typed value to public inputs (verifier knows these)
    pub fn writePublic(self: *Self, value: anytype) !void {
        try self.writeValueTo(&self.public_data, value);
    }

    /// Write raw bytes to public inputs
    pub fn writePublicBytes(self: *Self, bytes: []const u8) !void {
        try self.public_data.appendSlice(self.allocator, bytes);
    }

    // =========================================================================
    // Private Input Functions
    // =========================================================================

    /// Write a typed value to private inputs (witnesses, kept secret)
    pub fn writePrivate(self: *Self, value: anytype) !void {
        try self.writeValueTo(&self.private_data, value);
    }

    /// Write raw bytes to private inputs
    pub fn writePrivateBytes(self: *Self, bytes: []const u8) !void {
        try self.private_data.appendSlice(self.allocator, bytes);
    }

    // =========================================================================
    // Backward Compatibility (defaults to private)
    // =========================================================================

    /// Write a typed value (defaults to private for backward compatibility)
    pub fn write(self: *Self, value: anytype) !void {
        return self.writePrivate(value);
    }

    /// Write raw bytes (defaults to private for backward compatibility)
    pub fn writeBytes(self: *Self, bytes: []const u8) !void {
        return self.writePrivateBytes(bytes);
    }

    // =========================================================================
    // Internal Helpers
    // =========================================================================

    /// Write a typed value with automatic little-endian serialization
    fn writeValueTo(self: *Self, target: *std.ArrayListUnmanaged(u8), value: anytype) !void {
        const T = @TypeOf(value);
        const type_info = @typeInfo(T);

        switch (type_info) {
            .int, .comptime_int => {
                const IntType = if (type_info == .comptime_int) i64 else T;
                var bytes: [@sizeOf(IntType)]u8 = undefined;
                std.mem.writeInt(IntType, &bytes, @intCast(value), .little);
                try target.appendSlice(self.allocator, &bytes);
            },
            .float, .comptime_float => {
                const FloatType = if (type_info == .comptime_float) f64 else T;
                const IntType = std.meta.Int(.unsigned, @bitSizeOf(FloatType));
                var bytes: [@sizeOf(FloatType)]u8 = undefined;
                std.mem.writeInt(IntType, &bytes, @bitCast(value), .little);
                try target.appendSlice(self.allocator, &bytes);
            },
            .@"struct" => {
                const bytes = std.mem.asBytes(&value);
                try target.appendSlice(self.allocator, bytes);
            },
            .array => |arr| {
                if (arr.child == u8) {
                    try target.appendSlice(self.allocator, &value);
                } else {
                    @compileError("Only u8 arrays are supported. Use writeBytes for other arrays.");
                }
            },
            .pointer => |ptr| {
                if (ptr.size == .Slice and ptr.child == u8) {
                    try target.appendSlice(self.allocator, value);
                } else {
                    @compileError("Only []const u8 slices are supported. Use writeBytes.");
                }
            },
            else => @compileError("Unsupported type for write(). Use writeBytes() for raw data."),
        }
    }

    // =========================================================================
    // Output Functions
    // =========================================================================

    /// Get the encoded bytes for input.bin
    /// Format: [public_len:u64][public_data][private_len:u64][private_data]
    /// This allows the create-ligero-config tool to split into JSON args
    pub fn toBytes(self: *Self) ![]const u8 {
        const public_size = self.public_data.items.len;
        const private_size = self.private_data.items.len;

        // Format: 8 bytes public_len + public_data + 8 bytes private_len + private_data
        const total_size = 8 + public_size + 8 + private_size;
        const result = try self.allocator.alloc(u8, total_size);
        errdefer self.allocator.free(result);

        var offset: usize = 0;

        // Write public length
        std.mem.writeInt(u64, result[offset..][0..8], public_size, .little);
        offset += 8;

        // Write public data
        @memcpy(result[offset..][0..public_size], self.public_data.items);
        offset += public_size;

        // Write private length
        std.mem.writeInt(u64, result[offset..][0..8], private_size, .little);
        offset += 8;

        // Write private data
        @memcpy(result[offset..][0..private_size], self.private_data.items);

        return result;
    }

    /// Check if there's any public input data
    pub fn hasPublicData(self: *const Self) bool {
        return self.public_data.items.len > 0;
    }

    /// Check if there's any private input data
    pub fn hasPrivateData(self: *const Self) bool {
        return self.private_data.items.len > 0;
    }

    /// Get size of public data
    pub fn publicSize(self: *const Self) usize {
        return self.public_data.items.len;
    }

    /// Get size of private data
    pub fn privateSize(self: *const Self) usize {
        return self.private_data.items.len;
    }

    /// Get current data size (for Input.size() compatibility)
    /// Returns private data size for backward compatibility
    pub fn dataSize(self: *const Self) usize {
        return self.private_data.items.len;
    }
};

// =============================================================================
// Tests
// =============================================================================

test "ligero encoder - private only (backward compat)" {
    const allocator = std.testing.allocator;

    var encoder = Encoder.init(allocator);
    defer encoder.deinit();

    try encoder.write(@as(u64, 0x123456789ABCDEF0));
    const result = try encoder.toBytes();
    defer allocator.free(result);

    // Format: 8 bytes public_len (0) + 0 bytes public + 8 bytes private_len + 8 bytes private
    try std.testing.expectEqual(@as(usize, 24), result.len);

    // Public length should be 0
    const public_len = std.mem.readInt(u64, result[0..8], .little);
    try std.testing.expectEqual(@as(u64, 0), public_len);

    // Private length should be 8
    const private_len = std.mem.readInt(u64, result[8..16], .little);
    try std.testing.expectEqual(@as(u64, 8), private_len);

    // Check private data
    const value = std.mem.readInt(u64, result[16..24], .little);
    try std.testing.expectEqual(@as(u64, 0x123456789ABCDEF0), value);
}

test "ligero encoder - public and private" {
    const allocator = std.testing.allocator;

    var encoder = Encoder.init(allocator);
    defer encoder.deinit();

    try encoder.writePublic(@as(u64, 0xAAAABBBBCCCCDDDD));
    try encoder.writePrivate(@as(u64, 0x1111222233334444));

    const result = try encoder.toBytes();
    defer allocator.free(result);

    // Format: 8 + 8 (public) + 8 + 8 (private) = 32 bytes
    try std.testing.expectEqual(@as(usize, 32), result.len);

    // Public length should be 8
    const public_len = std.mem.readInt(u64, result[0..8], .little);
    try std.testing.expectEqual(@as(u64, 8), public_len);

    // Check public data
    const public_value = std.mem.readInt(u64, result[8..16], .little);
    try std.testing.expectEqual(@as(u64, 0xAAAABBBBCCCCDDDD), public_value);

    // Private length should be 8
    const private_len = std.mem.readInt(u64, result[16..24], .little);
    try std.testing.expectEqual(@as(u64, 8), private_len);

    // Check private data
    const private_value = std.mem.readInt(u64, result[24..32], .little);
    try std.testing.expectEqual(@as(u64, 0x1111222233334444), private_value);
}

test "ligero encoder - public only" {
    const allocator = std.testing.allocator;

    var encoder = Encoder.init(allocator);
    defer encoder.deinit();

    try encoder.writePublic(@as(u32, 42));

    const result = try encoder.toBytes();
    defer allocator.free(result);

    // Format: 8 + 4 (public) + 8 + 0 (private) = 20 bytes
    try std.testing.expectEqual(@as(usize, 20), result.len);

    // Public length should be 4
    const public_len = std.mem.readInt(u64, result[0..8], .little);
    try std.testing.expectEqual(@as(u64, 4), public_len);

    // Check public data
    const public_value = std.mem.readInt(u32, result[8..12], .little);
    try std.testing.expectEqual(@as(u32, 42), public_value);

    // Private length should be 0
    const private_len = std.mem.readInt(u64, result[12..20], .little);
    try std.testing.expectEqual(@as(u64, 0), private_len);
}

test "ligero encoder - multiple values" {
    const allocator = std.testing.allocator;

    var encoder = Encoder.init(allocator);
    defer encoder.deinit();

    try encoder.writePublic(@as(u32, 100));
    try encoder.writePublic(@as(u32, 200));
    try encoder.writePrivate(@as(u64, 999));
    try encoder.writePrivateBytes(&[_]u8{ 1, 2, 3 });

    const result = try encoder.toBytes();
    defer allocator.free(result);

    // Public: 8 bytes (two u32) + Private: 11 bytes (u64 + 3 bytes)
    // Format: 8 + 8 + 8 + 11 = 35 bytes
    try std.testing.expectEqual(@as(usize, 35), result.len);

    // Public length
    const public_len = std.mem.readInt(u64, result[0..8], .little);
    try std.testing.expectEqual(@as(u64, 8), public_len);

    // Private length
    const private_len = std.mem.readInt(u64, result[16..24], .little);
    try std.testing.expectEqual(@as(u64, 11), private_len);
}

test "ligero encoder - empty" {
    const allocator = std.testing.allocator;

    var encoder = Encoder.init(allocator);
    defer encoder.deinit();

    const result = try encoder.toBytes();
    defer allocator.free(result);

    // Just the two length fields
    try std.testing.expectEqual(@as(usize, 16), result.len);

    // Both lengths should be 0
    const public_len = std.mem.readInt(u64, result[0..8], .little);
    try std.testing.expectEqual(@as(u64, 0), public_len);

    const private_len = std.mem.readInt(u64, result[8..16], .little);
    try std.testing.expectEqual(@as(u64, 0), private_len);
}

test "ligero encoder - struct" {
    const allocator = std.testing.allocator;

    const TestStruct = packed struct {
        a: u32,
        b: u32,
    };

    var encoder = Encoder.init(allocator);
    defer encoder.deinit();

    try encoder.writePrivate(TestStruct{ .a = 10, .b = 20 });
    const result = try encoder.toBytes();
    defer allocator.free(result);

    // Format: 8 + 0 (public) + 8 + 8 (struct) = 24 bytes
    try std.testing.expectEqual(@as(usize, 24), result.len);

    // Private length should be 8
    const private_len = std.mem.readInt(u64, result[8..16], .little);
    try std.testing.expectEqual(@as(u64, 8), private_len);

    // Check struct data
    const a = std.mem.readInt(u32, result[16..20], .little);
    const b = std.mem.readInt(u32, result[20..24], .little);
    try std.testing.expectEqual(@as(u32, 10), a);
    try std.testing.expectEqual(@as(u32, 20), b);
}
