//! Host-side utilities for zkVM programs.
//!
//! This module provides ergonomic APIs for preparing inputs and reading outputs
//! from zkVM guest programs. It handles backend-specific encoding automatically.
//!
//! ## Compile-time backend selection (backward compatible)
//!
//! ```zig
//! const host = @import("zkvm_host");
//!
//! pub fn main() !void {
//!     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//!     defer _ = gpa.deinit();
//!     const allocator = gpa.allocator();
//!
//!     // Prepare input for guest (uses compile-time backend)
//!     var input = host.Input.init(allocator);
//!     defer input.deinit();
//!
//!     try input.write(@as(u64, 42));
//!     try input.toFile("input.bin");
//!
//!     // Read output from guest
//!     var output = try host.Output.fromFile(allocator, "output.bin");
//!     defer output.deinit();
//!
//!     const result = output.readU64(0);
//! }
//! ```
//!
//! ## Runtime backend selection
//!
//! ```zig
//! const host = @import("zkvm_host");
//!
//! pub fn main() !void {
//!     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//!     defer _ = gpa.deinit();
//!     const allocator = gpa.allocator();
//!
//!     // Create input for specific backend at runtime
//!     var input = host.createInput(allocator, .ligero);
//!     defer input.deinit();
//!
//!     try input.writePublic(@as(u64, expected_hash));
//!     try input.writePrivate(@as(u64, secret_value));
//!
//!     // Read output with specific backend
//!     var output = try host.Output.fromFileWithBackend(allocator, "output.bin", .ligero);
//!     defer output.deinit();
//! }
//! ```

const std = @import("std");

/// Input preparation for zkVM guest programs
pub const Input = @import("host/input.zig").Input;

/// Output reading from zkVM guest programs
pub const Output = @import("host/output.zig").Output;

/// Backend type for runtime selection
pub const Backend = @import("host/encoder.zig").Backend;

// Re-export common types for convenience
pub const Allocator = std.mem.Allocator;

/// Create an Input for a runtime-selected backend.
/// This is a convenience function equivalent to Input.initWithBackend().
pub fn createInput(allocator: Allocator, backend: Backend) Input {
    return Input.initWithBackend(allocator, backend);
}

/// Parse output from raw bytes with a runtime-selected backend.
/// This is a convenience function equivalent to Output.fromBytesWithBackend().
pub fn parseOutput(allocator: Allocator, bytes: []const u8, backend: Backend) !Output {
    return Output.fromBytesWithBackend(allocator, bytes, backend);
}

// Re-export backend-specific encoders/decoders for advanced use cases
pub const encoders = struct {
    pub const native = @import("host/backends/native/encoder.zig");
    pub const zisk = @import("host/backends/zisk/encoder.zig");
    pub const ligero = @import("host/backends/ligero/encoder.zig");
    pub const Encoder = @import("host/encoder.zig").Encoder;
};

pub const decoders = struct {
    pub const native = @import("host/backends/native/decoder.zig");
    pub const zisk = @import("host/backends/zisk/decoder.zig");
    pub const ligero = @import("host/backends/ligero/decoder.zig");
    pub const Decoder = @import("host/decoder.zig").Decoder;
};
