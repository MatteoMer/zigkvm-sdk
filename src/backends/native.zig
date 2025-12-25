// Native Backend for zigkvm-sdk
// Provides a testing interface that runs outside of any zkVM
// Useful for unit testing and development

const std = @import("std");

// =============================================================================
// State for Testing
// =============================================================================

/// Input data buffer (set via setInputData for testing)
var input_data: []const u8 = &[_]u8{};
var input_offset: usize = 0;

/// Output buffer
var output_values: [64]u32 = [_]u32{0} ** 64;
var output_count: u32 = 0;

/// General purpose allocator for native execution
var gpa = std.heap.GeneralPurposeAllocator(.{}){};

// =============================================================================
// Test Setup Functions
// =============================================================================

/// Set the input data for testing (call before your main function)
pub fn setInputData(data: []const u8) void {
    input_data = data;
    input_offset = 0;
}

/// Reset state between tests
pub fn reset() void {
    input_data = &[_]u8{};
    input_offset = 0;
    output_values = [_]u32{0} ** 64;
    output_count = 0;
}

// =============================================================================
// Input Functions
// =============================================================================

/// Read the input data size
pub fn readInputSize() u64 {
    return input_data.len;
}

/// Read input data as a byte slice
pub fn readInputSlice() []const u8 {
    return input_data;
}

/// Read input data as a typed structure
pub fn readInput(comptime T: type) T {
    if (input_data.len < @sizeOf(T)) {
        @panic("Input data too small for requested type");
    }
    return std.mem.bytesToValue(T, input_data[0..@sizeOf(T)]);
}

/// Read input from a specific offset
pub fn readInputAt(comptime T: type, offset: usize) T {
    if (offset + @sizeOf(T) > input_data.len) {
        @panic("Input offset out of bounds");
    }
    return std.mem.bytesToValue(T, input_data[offset..][0..@sizeOf(T)]);
}

// =============================================================================
// Architecture Detection
// =============================================================================

/// Always returns false for native backend
pub fn isZkVM() bool {
    return false;
}

/// Returns 0 for native (no architecture ID)
pub fn getArchId() u64 {
    return 0;
}

// =============================================================================
// Output Functions
// =============================================================================

/// Set a u32 output value at the given index
pub fn setOutput(id: usize, value: u32) void {
    if (id >= 64) return;

    if (id + 1 > output_count) {
        output_count = @intCast(id + 1);
    }

    output_values[id] = value;
}

/// Set a u64 output value using two consecutive output slots
pub fn setOutputU64(id: usize, value: u64) void {
    setOutput(id, @truncate(value));
    setOutput(id + 1, @truncate(value >> 32));
}

/// Get the current output count
pub fn getOutputCount() u32 {
    return output_count;
}

/// Get a u32 output value at the given index
pub fn getOutput(id: usize) u32 {
    if (id >= 64) return 0;
    return output_values[id];
}

/// Get a u64 output value from two consecutive output slots
pub fn getOutputU64(id: usize) u64 {
    const low: u64 = getOutput(id);
    const high: u64 = getOutput(id + 1);
    return low | (high << 32);
}

/// Get all outputs as a slice
pub fn getOutputSlice() []const u32 {
    return output_values[0..output_count];
}

/// Commit a value (alias for setOutput)
pub fn commit(id: usize, value: u32) void {
    setOutput(id, value);
}

/// Commit a u64 value
pub fn commitU64(id: usize, value: u64) void {
    setOutputU64(id, value);
}

// =============================================================================
// Exit Functions
// =============================================================================

/// Exit with the given code (calls std.process.exit for native)
pub fn exit(code: u64) noreturn {
    std.process.exit(@truncate(code));
}

/// Exit with success
pub fn exitSuccess() noreturn {
    exit(0);
}

/// Exit with error
pub fn exitError() noreturn {
    setOutput(0, 0xDEAD);
    exit(1);
}

// =============================================================================
// Debug Output
// =============================================================================

/// Write a byte to stderr for debug output
pub fn uartWrite(byte: u8) void {
    const stderr = std.io.getStdErr();
    stderr.writer().writeByte(byte) catch {};
}

/// Write a string to stderr for debug output
pub fn uartPrint(str: []const u8) void {
    const stderr = std.io.getStdErr();
    stderr.writer().writeAll(str) catch {};
}

// =============================================================================
// Allocator
// =============================================================================

/// BumpAllocator stub for API compatibility
pub const BumpAllocator = struct {
    const Self = @This();

    pub fn init(_: usize, _: usize) Self {
        return .{};
    }

    pub fn initFromLinker() Self {
        return .{};
    }

    pub fn allocator(_: *Self) std.mem.Allocator {
        return gpa.allocator();
    }
};

/// Get the allocator (uses GPA for native)
pub fn allocator() std.mem.Allocator {
    return gpa.allocator();
}

// =============================================================================
// Entry Point Support
// =============================================================================

/// Type signature for the user's main function
pub const MainFn = *const fn () void;

/// For native, entry point export is a no-op
/// The program uses the standard entry point
pub fn exportEntryPoint(comptime mainFn: MainFn) void {
    _ = mainFn;
    // No-op for native - users call main() directly in tests
}

// =============================================================================
// Panic Handler
// =============================================================================

/// Default panic handler - uses standard panic for native
pub fn panic(msg: []const u8, stack_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    _ = stack_trace;
    std.debug.defaultPanic(msg, ret_addr);
}

// =============================================================================
// Tests
// =============================================================================

test "basic API availability" {
    _ = readInputSize;
    _ = readInputSlice;
    _ = readInput;
    _ = setOutput;
    _ = setOutputU64;
    _ = getOutput;
    _ = getOutputU64;
    _ = commit;
    _ = isZkVM;
    _ = allocator;
    _ = exportEntryPoint;
    _ = panic;
}

test "native backend I/O" {
    // Reset state
    reset();

    // Set up test input
    const input_bytes = [_]u8{ 0x01, 0x02, 0x03, 0x04 };
    setInputData(&input_bytes);

    // Test reading input
    const slice = readInputSlice();
    try std.testing.expectEqualSlices(u8, &input_bytes, slice);

    // Test output
    setOutput(0, 42);
    setOutput(1, 100);
    try std.testing.expectEqual(@as(u32, 42), getOutput(0));
    try std.testing.expectEqual(@as(u32, 100), getOutput(1));
    try std.testing.expectEqual(@as(u32, 2), getOutputCount());

    // Test u64 output
    setOutputU64(2, 0x123456789ABCDEF0);
    try std.testing.expectEqual(@as(u64, 0x123456789ABCDEF0), getOutputU64(2));

    // Test isZkVM (should be false for native)
    try std.testing.expectEqual(false, isZkVM());
}

