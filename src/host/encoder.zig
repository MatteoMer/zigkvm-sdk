const std = @import("std");

// Backend-specific encoders
const native_encoder = @import("backends/native/encoder.zig");
const zisk_encoder = @import("backends/zisk/encoder.zig");
const ligero_encoder = @import("backends/ligero/encoder.zig");

/// Backend selection for runtime encoding
pub const Backend = enum {
    native,
    zisk,
    ligero,
};

/// Runtime-selectable encoder that wraps backend-specific encoders.
/// Allows choosing the backend at runtime instead of compile time.
pub const Encoder = union(Backend) {
    native: native_encoder.Encoder,
    zisk: zisk_encoder.Encoder,
    ligero: ligero_encoder.Encoder,

    const Self = @This();

    /// Initialize encoder for the specified backend
    pub fn init(allocator: std.mem.Allocator, backend: Backend) Self {
        return switch (backend) {
            .native => .{ .native = native_encoder.Encoder.init(allocator) },
            .zisk => .{ .zisk = zisk_encoder.Encoder.init(allocator) },
            .ligero => .{ .ligero = ligero_encoder.Encoder.init(allocator) },
        };
    }

    /// Free resources
    pub fn deinit(self: *Self) void {
        switch (self.*) {
            inline else => |*enc| enc.deinit(),
        }
    }

    /// Write a typed value.
    /// For native/zisk: writes to combined data
    /// For ligero: writes to private data (backward compatible)
    pub fn write(self: *Self, value: anytype) !void {
        switch (self.*) {
            inline else => |*enc| try enc.write(value),
        }
    }

    /// Write raw bytes.
    /// For native/zisk: writes to combined data
    /// For ligero: writes to private data (backward compatible)
    pub fn writeBytes(self: *Self, bytes: []const u8) !void {
        switch (self.*) {
            inline else => |*enc| try enc.writeBytes(bytes),
        }
    }

    /// Write a typed value to public inputs.
    /// Only meaningful for Ligero - other backends ignore public/private distinction.
    pub fn writePublic(self: *Self, value: anytype) !void {
        switch (self.*) {
            .ligero => |*enc| try enc.writePublic(value),
            // For non-Ligero backends, public data is just added to the main buffer
            .native => |*enc| try enc.write(value),
            .zisk => |*enc| try enc.write(value),
        }
    }

    /// Write raw bytes to public inputs.
    /// Only meaningful for Ligero - other backends ignore public/private distinction.
    pub fn writePublicBytes(self: *Self, bytes: []const u8) !void {
        switch (self.*) {
            .ligero => |*enc| try enc.writePublicBytes(bytes),
            .native => |*enc| try enc.writeBytes(bytes),
            .zisk => |*enc| try enc.writeBytes(bytes),
        }
    }

    /// Write a typed value to private inputs.
    /// For Ligero: writes to private buffer
    /// For other backends: writes to main buffer
    pub fn writePrivate(self: *Self, value: anytype) !void {
        switch (self.*) {
            .ligero => |*enc| try enc.writePrivate(value),
            .native => |*enc| try enc.write(value),
            .zisk => |*enc| try enc.write(value),
        }
    }

    /// Write raw bytes to private inputs.
    /// For Ligero: writes to private buffer
    /// For other backends: writes to main buffer
    pub fn writePrivateBytes(self: *Self, bytes: []const u8) !void {
        switch (self.*) {
            .ligero => |*enc| try enc.writePrivateBytes(bytes),
            .native => |*enc| try enc.writeBytes(bytes),
            .zisk => |*enc| try enc.writeBytes(bytes),
        }
    }

    /// Get current data size
    pub fn dataSize(self: *const Self) usize {
        return switch (self.*) {
            inline else => |*enc| enc.dataSize(),
        };
    }

    /// Get the fully encoded bytes (backend-specific format).
    /// Caller owns the returned slice and must free it.
    pub fn toBytes(self: *Self) ![]const u8 {
        return switch (self.*) {
            inline else => |*enc| try enc.toBytes(),
        };
    }

    /// Get raw public bytes (for Runtime.execute separation).
    /// For Ligero: returns just the public data without length prefix
    /// For other backends: returns empty slice
    pub fn getPublicBytes(self: *Self) ![]const u8 {
        return switch (self.*) {
            .ligero => |*enc| {
                const size = enc.publicSize();
                if (size == 0) return &[_]u8{};
                const result = try self.getAllocator().alloc(u8, size);
                @memcpy(result, enc.public_data.items);
                return result;
            },
            .native, .zisk => &[_]u8{},
        };
    }

    /// Get raw private bytes (for Runtime.execute separation).
    /// For Ligero: returns just the private data without length prefix
    /// For other backends: returns all data
    pub fn getPrivateBytes(self: *Self) ![]const u8 {
        return switch (self.*) {
            .ligero => |*enc| {
                const size = enc.privateSize();
                if (size == 0) return &[_]u8{};
                const result = try self.getAllocator().alloc(u8, size);
                @memcpy(result, enc.private_data.items);
                return result;
            },
            .native => |*enc| {
                const size = enc.data.items.len;
                if (size == 0) return &[_]u8{};
                const result = try self.getAllocator().alloc(u8, size);
                @memcpy(result, enc.data.items);
                return result;
            },
            .zisk => |*enc| {
                const size = enc.data.items.len;
                if (size == 0) return &[_]u8{};
                const result = try self.getAllocator().alloc(u8, size);
                @memcpy(result, enc.data.items);
                return result;
            },
        };
    }

    /// Check if there's any public data
    pub fn hasPublicData(self: *const Self) bool {
        return switch (self.*) {
            .ligero => |*enc| enc.hasPublicData(),
            .native, .zisk => false,
        };
    }

    /// Check if there's any private data
    pub fn hasPrivateData(self: *const Self) bool {
        return switch (self.*) {
            .ligero => |*enc| enc.hasPrivateData(),
            .native => |*enc| enc.data.items.len > 0,
            .zisk => |*enc| enc.data.items.len > 0,
        };
    }

    /// Get the allocator used by this encoder
    fn getAllocator(self: *Self) std.mem.Allocator {
        return switch (self.*) {
            inline else => |*enc| enc.allocator,
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

test "encoder - native backend" {
    const allocator = std.testing.allocator;

    var enc = Encoder.init(allocator, .native);
    defer enc.deinit();

    try enc.write(@as(u64, 42));
    const bytes = try enc.toBytes();
    defer allocator.free(bytes);

    try std.testing.expectEqual(@as(usize, 8), bytes.len);
}

test "encoder - zisk backend" {
    const allocator = std.testing.allocator;

    var enc = Encoder.init(allocator, .zisk);
    defer enc.deinit();

    try enc.write(@as(u64, 42));
    const bytes = try enc.toBytes();
    defer allocator.free(bytes);

    // ZisK adds 16-byte header
    try std.testing.expectEqual(@as(usize, 24), bytes.len);
}

test "encoder - ligero backend with public/private" {
    const allocator = std.testing.allocator;

    var enc = Encoder.init(allocator, .ligero);
    defer enc.deinit();

    try enc.writePublic(@as(u32, 100));
    try enc.writePrivate(@as(u32, 200));

    try std.testing.expect(enc.hasPublicData());
    try std.testing.expect(enc.hasPrivateData());

    const pub_bytes = try enc.getPublicBytes();
    defer if (pub_bytes.len > 0) allocator.free(pub_bytes);
    try std.testing.expectEqual(@as(usize, 4), pub_bytes.len);

    const priv_bytes = try enc.getPrivateBytes();
    defer if (priv_bytes.len > 0) allocator.free(priv_bytes);
    try std.testing.expectEqual(@as(usize, 4), priv_bytes.len);
}

test "encoder - native backend public/private fallback" {
    const allocator = std.testing.allocator;

    var enc = Encoder.init(allocator, .native);
    defer enc.deinit();

    // For native, public/private both go to main buffer
    try enc.writePublic(@as(u32, 100));
    try enc.writePrivate(@as(u32, 200));

    const bytes = try enc.toBytes();
    defer allocator.free(bytes);

    // Both values in sequence
    try std.testing.expectEqual(@as(usize, 8), bytes.len);
}
