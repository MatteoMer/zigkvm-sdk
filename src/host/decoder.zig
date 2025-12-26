const std = @import("std");

// Backend-specific decoders
const native_decoder = @import("backends/native/decoder.zig");
const zisk_decoder = @import("backends/zisk/decoder.zig");
const ligero_decoder = @import("backends/ligero/decoder.zig");

/// Backend selection for runtime decoding
pub const Backend = enum {
    native,
    zisk,
    ligero,
};

/// Runtime-selectable decoder that wraps backend-specific decoders.
/// Allows choosing the backend at runtime instead of compile time.
pub const Decoder = union(Backend) {
    native: native_decoder.Decoder,
    zisk: zisk_decoder.Decoder,
    ligero: ligero_decoder.Decoder,

    const Self = @This();

    /// Load output from a file with specified backend
    pub fn fromFile(allocator: std.mem.Allocator, path: []const u8, backend: Backend) !Self {
        return switch (backend) {
            .native => .{ .native = try native_decoder.Decoder.fromFile(allocator, path) },
            .zisk => .{ .zisk = try zisk_decoder.Decoder.fromFile(allocator, path) },
            .ligero => .{ .ligero = try ligero_decoder.Decoder.fromFile(allocator, path) },
        };
    }

    /// Load output from raw bytes with specified backend
    pub fn fromBytes(allocator: std.mem.Allocator, bytes: []const u8, backend: Backend) !Self {
        return switch (backend) {
            .native => .{ .native = try native_decoder.Decoder.fromBytes(allocator, bytes) },
            .zisk => .{ .zisk = try zisk_decoder.Decoder.fromBytes(allocator, bytes) },
            .ligero => .{ .ligero = try ligero_decoder.Decoder.fromBytes(allocator, bytes) },
        };
    }

    /// Free resources
    pub fn deinit(self: *Self) void {
        switch (self.*) {
            inline else => |*dec| dec.deinit(),
        }
    }

    /// Get the number of output values
    pub fn count(self: *const Self) u32 {
        return switch (self.*) {
            inline else => |*dec| dec.count(),
        };
    }

    /// Read a u32 output value at the given index
    pub fn read(self: *const Self, index: usize) u32 {
        return switch (self.*) {
            inline else => |*dec| dec.read(index),
        };
    }

    /// Read a u64 output value from two consecutive slots
    /// Low 32 bits from index, high 32 bits from index+1
    pub fn readU64(self: *const Self, index: usize) u64 {
        return switch (self.*) {
            inline else => |*dec| dec.readU64(index),
        };
    }

    /// Get all outputs as a slice
    pub fn slice(self: *const Self) []const u32 {
        return switch (self.*) {
            inline else => |*dec| dec.slice(),
        };
    }

    /// Get the backend type
    pub fn getBackend(self: *const Self) Backend {
        return self.*;
    }
};

// =============================================================================
// Tests
// =============================================================================

test "decoder - native backend" {
    const allocator = std.testing.allocator;

    var bytes = [_]u8{0} ** 8;
    std.mem.writeInt(u32, bytes[0..4], 1, .little);
    std.mem.writeInt(u32, bytes[4..8], 42, .little);

    var dec = try Decoder.fromBytes(allocator, &bytes, .native);
    defer dec.deinit();

    try std.testing.expectEqual(@as(u32, 1), dec.count());
    try std.testing.expectEqual(@as(u32, 42), dec.read(0));
    try std.testing.expectEqual(Backend.native, dec.getBackend());
}

test "decoder - zisk backend" {
    const allocator = std.testing.allocator;

    var bytes = [_]u8{0} ** 12;
    std.mem.writeInt(u32, bytes[0..4], 2, .little);
    std.mem.writeInt(u32, bytes[4..8], 0xDEAD, .little);
    std.mem.writeInt(u32, bytes[8..12], 0xBEEF, .little);

    var dec = try Decoder.fromBytes(allocator, &bytes, .zisk);
    defer dec.deinit();

    try std.testing.expectEqual(@as(u32, 2), dec.count());
    try std.testing.expectEqual(@as(u32, 0xDEAD), dec.read(0));
    try std.testing.expectEqual(@as(u32, 0xBEEF), dec.read(1));
    try std.testing.expectEqual(Backend.zisk, dec.getBackend());
}

test "decoder - ligero backend" {
    const allocator = std.testing.allocator;

    var bytes = [_]u8{0} ** 12;
    std.mem.writeInt(u32, bytes[0..4], 2, .little);
    std.mem.writeInt(u32, bytes[4..8], 100, .little);
    std.mem.writeInt(u32, bytes[8..12], 200, .little);

    var dec = try Decoder.fromBytes(allocator, &bytes, .ligero);
    defer dec.deinit();

    try std.testing.expectEqual(@as(u32, 2), dec.count());
    try std.testing.expectEqual(@as(u64, (200 << 32) | 100), dec.readU64(0));
    try std.testing.expectEqual(Backend.ligero, dec.getBackend());
}

test "decoder - u64 reading" {
    const allocator = std.testing.allocator;

    var bytes = [_]u8{0} ** 12;
    std.mem.writeInt(u32, bytes[0..4], 2, .little);
    std.mem.writeInt(u32, bytes[4..8], 0xABCDEF12, .little);
    std.mem.writeInt(u32, bytes[8..12], 0x34567890, .little);

    var dec = try Decoder.fromBytes(allocator, &bytes, .native);
    defer dec.deinit();

    const expected: u64 = 0xABCDEF12 | (@as(u64, 0x34567890) << 32);
    try std.testing.expectEqual(expected, dec.readU64(0));
}

test "decoder - slice access" {
    const allocator = std.testing.allocator;

    var bytes = [_]u8{0} ** 16;
    std.mem.writeInt(u32, bytes[0..4], 3, .little);
    std.mem.writeInt(u32, bytes[4..8], 10, .little);
    std.mem.writeInt(u32, bytes[8..12], 20, .little);
    std.mem.writeInt(u32, bytes[12..16], 30, .little);

    var dec = try Decoder.fromBytes(allocator, &bytes, .zisk);
    defer dec.deinit();

    const s = dec.slice();
    try std.testing.expectEqual(@as(usize, 3), s.len);
    try std.testing.expectEqual(@as(u32, 10), s[0]);
    try std.testing.expectEqual(@as(u32, 20), s[1]);
    try std.testing.expectEqual(@as(u32, 30), s[2]);
}
