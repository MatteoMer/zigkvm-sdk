const std = @import("std");
const build_options = @import("build_options");
const Backend = build_options.Backend;

// Backend-specific decoders
const native_decoder = @import("output_native.zig");
const zisk_decoder = @import("output_zisk.zig");
const ligero_decoder = @import("output_ligero.zig");

/// Select decoder based on configured backend
const Decoder = switch (build_options.backend) {
    .native => native_decoder.Decoder,
    .zisk => zisk_decoder.Decoder,
    .ligero => ligero_decoder.Decoder,
};

/// Host-side output reading for zkVM programs.
/// Provides an ergonomic API for reading outputs from guest programs.
///
/// Usage:
/// ```zig
/// // Load from file (zisk backend)
/// var output = try Output.fromFile(allocator, "output.bin");
/// defer output.deinit();
///
/// const result = output.readU64(0);
/// ```
pub const Output = struct {
    allocator: std.mem.Allocator,
    decoder: Decoder,

    const Self = @This();

    /// Load outputs from a file
    pub fn fromFile(allocator: std.mem.Allocator, path: []const u8) !Self {
        const decoder = try Decoder.fromFile(allocator, path);
        return .{
            .allocator = allocator,
            .decoder = decoder,
        };
    }

    /// Load outputs from raw bytes
    pub fn fromBytes(allocator: std.mem.Allocator, bytes: []const u8) !Self {
        const decoder = try Decoder.fromBytes(allocator, bytes);
        return .{
            .allocator = allocator,
            .decoder = decoder,
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
};
