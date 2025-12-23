const std = @import("std");
const build_options = @import("build_options");
const Backend = build_options.Backend;

// Backend-specific encoders
const native_encoder = @import("native.zig");
const zisk_encoder = @import("zisk.zig");
const ligero_encoder = @import("ligero.zig");

/// Select encoder based on configured backend
const Encoder = switch (build_options.backend) {
    .native => native_encoder.Encoder,
    .zisk => zisk_encoder.Encoder,
    .ligero => ligero_encoder.Encoder,
};

/// Host-side input preparation for zkVM programs.
/// Provides an ergonomic API for preparing inputs to send to guest programs.
///
/// Usage:
/// ```zig
/// var input = Input.init(allocator);
/// defer input.deinit();
///
/// try input.write(@as(u64, 42));
/// try input.write(@as(u32, 100));
///
/// // Write to file for zkVM CLI tools
/// try input.toFile("input.bin");
///
/// // Or get bytes directly for testing
/// const bytes = try input.toBytes();
/// ```
pub const Input = struct {
    allocator: std.mem.Allocator,
    encoder: Encoder,

    const Self = @This();

    /// Initialize a new input builder
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .encoder = Encoder.init(allocator),
        };
    }

    /// Free resources
    pub fn deinit(self: *Self) void {
        self.encoder.deinit();
    }

    /// Write a typed value to the input.
    /// Supports integers, floats, packed structs, and byte arrays/slices.
    /// All numeric types are serialized as little-endian.
    pub fn write(self: *Self, value: anytype) !void {
        return self.encoder.write(value);
    }

    /// Write raw bytes to the input
    pub fn writeBytes(self: *Self, bytes: []const u8) !void {
        return self.encoder.writeBytes(bytes);
    }

    /// Write a typed value to public inputs (Ligero only)
    pub fn writePublic(self: *Self, value: anytype) !void {
        if (build_options.backend != .ligero) {
            @compileError("writePublic is only supported by the Ligero backend");
        }
        return self.encoder.writePublic(value);
    }

    /// Write raw bytes to public inputs (Ligero only)
    pub fn writePublicBytes(self: *Self, bytes: []const u8) !void {
        if (build_options.backend != .ligero) {
            @compileError("writePublicBytes is only supported by the Ligero backend");
        }
        return self.encoder.writePublicBytes(bytes);
    }

    /// Write a typed value to private inputs (Ligero only)
    pub fn writePrivate(self: *Self, value: anytype) !void {
        if (build_options.backend != .ligero) {
            @compileError("writePrivate is only supported by the Ligero backend");
        }
        return self.encoder.writePrivate(value);
    }

    /// Write raw bytes to private inputs (Ligero only)
    pub fn writePrivateBytes(self: *Self, bytes: []const u8) !void {
        if (build_options.backend != .ligero) {
            @compileError("writePrivateBytes is only supported by the Ligero backend");
        }
        return self.encoder.writePrivateBytes(bytes);
    }

    /// Get the encoded input as bytes.
    /// The encoding format depends on the configured backend.
    /// Caller owns the returned slice and must free it.
    pub fn toBytes(self: *Self) ![]const u8 {
        return self.encoder.toBytes();
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
};
