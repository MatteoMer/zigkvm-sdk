const std = @import("std");
const decoder_mod = @import("decoder.zig");

/// Re-export Backend for convenience
pub const Backend = decoder_mod.Backend;

/// Host-side output reading for zkVM programs.
/// Provides an ergonomic API for reading outputs from guest programs.
///
/// Supports both compile-time and runtime backend selection:
///
/// ## Compile-time backend (backward compatible)
/// ```zig
/// var output = try Output.fromFile(allocator, "output.bin");
/// defer output.deinit();
/// const result = output.readU64(0);
/// ```
///
/// ## Runtime backend selection
/// ```zig
/// var output = try Output.fromFileWithBackend(allocator, "output.bin", .zisk);
/// defer output.deinit();
/// const result = output.readU64(0);
/// ```
pub const Output = struct {
    allocator: std.mem.Allocator,
    decoder: decoder_mod.Decoder,

    const Self = @This();

    /// Load outputs from a file using compile-time backend (backward compatible).
    /// Uses the backend specified via `-Dbackend=` build option.
    pub fn fromFile(allocator: std.mem.Allocator, path: []const u8) !Self {
        const build_options = @import("build_options");
        const backend: Backend = switch (build_options.backend) {
            .native => .native,
            .zisk => .zisk,
            .ligero => .ligero,
        };
        return fromFileWithBackend(allocator, path, backend);
    }

    /// Load outputs from raw bytes using compile-time backend (backward compatible).
    pub fn fromBytes(allocator: std.mem.Allocator, bytes: []const u8) !Self {
        const build_options = @import("build_options");
        const backend: Backend = switch (build_options.backend) {
            .native => .native,
            .zisk => .zisk,
            .ligero => .ligero,
        };
        return fromBytesWithBackend(allocator, bytes, backend);
    }

    /// Load outputs from a file with runtime-selected backend.
    /// Use this when the backend is determined at runtime (e.g., from Runtime options).
    pub fn fromFileWithBackend(allocator: std.mem.Allocator, path: []const u8, backend: Backend) !Self {
        return .{
            .allocator = allocator,
            .decoder = try decoder_mod.Decoder.fromFile(allocator, path, backend),
        };
    }

    /// Load outputs from raw bytes with runtime-selected backend.
    pub fn fromBytesWithBackend(allocator: std.mem.Allocator, bytes: []const u8, backend: Backend) !Self {
        return .{
            .allocator = allocator,
            .decoder = try decoder_mod.Decoder.fromBytes(allocator, bytes, backend),
        };
    }

    /// Free resources
    pub fn deinit(self: *Self) void {
        self.decoder.deinit();
    }

    /// Get the number of output values
    pub fn count(self: *const Self) u32 {
        return self.decoder.count();
    }

    /// Read a u32 output value at the given index
    pub fn read(self: *const Self, index: usize) u32 {
        return self.decoder.read(index);
    }

    /// Read a u64 output value from two consecutive slots
    /// Low 32 bits from index, high 32 bits from index+1
    pub fn readU64(self: *const Self, index: usize) u64 {
        return self.decoder.readU64(index);
    }

    /// Get all outputs as a slice of u32 values
    pub fn slice(self: *const Self) []const u32 {
        return self.decoder.slice();
    }

    /// Get the backend that produced this output
    pub fn getBackend(self: *const Self) Backend {
        return self.decoder.getBackend();
    }
};
