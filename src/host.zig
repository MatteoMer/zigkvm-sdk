//! Host-side utilities for zkVM programs.
//!
//! This module provides ergonomic APIs for preparing inputs and reading outputs
//! from zkVM guest programs. It handles backend-specific encoding automatically.
//!
//! ## Example
//!
//! ```zig
//! const host = @import("zkvm_host");
//!
//! pub fn main() !void {
//!     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//!     defer _ = gpa.deinit();
//!     const allocator = gpa.allocator();
//!
//!     // Prepare input for guest
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

const std = @import("std");

/// Input preparation for zkVM guest programs
pub const Input = @import("host/input.zig").Input;

/// Output reading from zkVM guest programs
pub const Output = @import("host/output.zig").Output;

// Re-export common types for convenience
pub const Allocator = std.mem.Allocator;

// Re-export backend-specific encoders/decoders for advanced use cases
pub const encoders = struct {
    pub const native = @import("host/native.zig");
    pub const zisk = @import("host/zisk.zig");
};

pub const decoders = struct {
    pub const native = @import("host/output_native.zig");
    pub const zisk = @import("host/output_zisk.zig");
};
