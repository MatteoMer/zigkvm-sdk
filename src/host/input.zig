const std = @import("std");
const encoder_mod = @import("encoder.zig");

/// Re-export Backend for convenience
pub const Backend = encoder_mod.Backend;

/// Host-side input preparation for zkVM programs.
/// Provides an ergonomic API for preparing inputs to send to guest programs.
///
/// Supports both compile-time and runtime backend selection:
///
/// ## Compile-time backend (backward compatible)
/// ```zig
/// var input = Input.init(allocator);
/// defer input.deinit();
/// try input.write(@as(u64, 42));
/// ```
///
/// ## Runtime backend selection
/// ```zig
/// var input = Input.initWithBackend(allocator, .ligero);
/// defer input.deinit();
/// try input.writePublic(@as(u64, expected_hash));
/// try input.writePrivate(@as(u64, secret_value));
/// ```
pub const Input = struct {
    allocator: std.mem.Allocator,
    encoder: encoder_mod.Encoder,

    const Self = @This();

    /// Initialize with compile-time backend selection (backward compatible).
    /// Uses the backend specified via `-Dbackend=` build option.
    pub fn init(allocator: std.mem.Allocator) Self {
        const build_options = @import("build_options");
        const backend: Backend = switch (build_options.backend) {
            .native => .native,
            .zisk => .zisk,
            .ligero => .ligero,
        };
        return initWithBackend(allocator, backend);
    }

    /// Initialize with runtime-selected backend.
    /// Use this when the backend is determined at runtime (e.g., from Runtime options).
    pub fn initWithBackend(allocator: std.mem.Allocator, backend: Backend) Self {
        return .{
            .allocator = allocator,
            .encoder = encoder_mod.Encoder.init(allocator, backend),
        };
    }

    /// Free resources
    pub fn deinit(self: *Self) void {
        self.encoder.deinit();
    }

    /// Write a typed value to the input.
    /// Supports integers, floats, packed structs, and byte arrays/slices.
    /// All numeric types are serialized as little-endian.
    ///
    /// For Ligero: defaults to private input (backward compatible)
    /// For other backends: writes to main buffer
    pub fn write(self: *Self, value: anytype) !void {
        return self.encoder.write(value);
    }

    /// Write raw bytes to the input
    pub fn writeBytes(self: *Self, bytes: []const u8) !void {
        return self.encoder.writeBytes(bytes);
    }

    /// Write a typed value to public inputs.
    /// For Ligero: writes to public buffer (verifier-visible)
    /// For other backends: writes to main buffer (public/private not distinguished)
    pub fn writePublic(self: *Self, value: anytype) !void {
        return self.encoder.writePublic(value);
    }

    /// Write raw bytes to public inputs.
    pub fn writePublicBytes(self: *Self, bytes: []const u8) !void {
        return self.encoder.writePublicBytes(bytes);
    }

    /// Write a typed value to private inputs.
    /// For Ligero: writes to private buffer (witness, kept secret)
    /// For other backends: writes to main buffer
    pub fn writePrivate(self: *Self, value: anytype) !void {
        return self.encoder.writePrivate(value);
    }

    /// Write raw bytes to private inputs.
    pub fn writePrivateBytes(self: *Self, bytes: []const u8) !void {
        return self.encoder.writePrivateBytes(bytes);
    }

    /// Get the fully encoded input as bytes.
    /// The encoding format depends on the backend:
    /// - Native: raw data bytes
    /// - ZisK: 16-byte header + data
    /// - Ligero: [pub_len:u64][pub_data][priv_len:u64][priv_data]
    ///
    /// Caller owns the returned slice and must free it.
    pub fn toBytes(self: *Self) ![]const u8 {
        return self.encoder.toBytes();
    }

    /// Get raw public bytes for Runtime.execute() separation.
    /// For Ligero: returns just the public data without length prefix
    /// For other backends: returns empty slice
    ///
    /// Caller owns the returned slice and must free it (if non-empty).
    pub fn getPublicBytes(self: *Self) ![]const u8 {
        return self.encoder.getPublicBytes();
    }

    /// Get raw private bytes for Runtime.execute() separation.
    /// For Ligero: returns just the private data without length prefix
    /// For other backends: returns all data
    ///
    /// Caller owns the returned slice and must free it (if non-empty).
    pub fn getPrivateBytes(self: *Self) ![]const u8 {
        return self.encoder.getPrivateBytes();
    }

    /// Write the encoded input to a file.
    /// Convenience method for creating input.bin files.
    pub fn toFile(self: *Self, path: []const u8) !void {
        const bytes = try self.toBytes();
        defer self.allocator.free(bytes);

        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();
        try file.writeAll(bytes);
    }

    /// Get the current size of the input data (excluding any header)
    pub fn size(self: *const Self) usize {
        return self.encoder.dataSize();
    }

    /// Check if there's any public data
    pub fn hasPublicData(self: *const Self) bool {
        return self.encoder.hasPublicData();
    }

    /// Check if there's any private data
    pub fn hasPrivateData(self: *const Self) bool {
        return self.encoder.hasPrivateData();
    }

    /// Get the backend this input is configured for
    pub fn getBackend(self: *const Self) Backend {
        return self.encoder.getBackend();
    }
};
