// Jolt Backend for zigkvm-sdk
// Provides a Zig interface to the Jolt zkVM (via Zolt)
//
// Memory map (matching Jolt/Zolt's default MemoryLayout):
//   I/O region below RAM_START_ADDRESS (0x80000000):
//     INPUT_ADDR:   0x7FFFA000 - input data (read-only, 4KB)
//     OUTPUT_ADDR:  0x7FFFB000 - output data (4KB)
//     PANIC_ADDR:   0x7FFFC000 - panic bit
//     TERM_ADDR:    0x7FFFC008 - termination bit
//   RAM at 0x80000000+:
//     Program code, data, stack, heap

const std = @import("std");

// =============================================================================
// Memory Constants (matching Jolt/Zolt default MemoryConfig)
// =============================================================================

/// RAM start address (Jolt standard)
pub const RAM_START_ADDRESS: u64 = 0x80000000;

/// I/O region addresses computed from default MemoryConfig:
///   max_input=4096, max_output=4096, max_trusted_advice=4096, max_untrusted_advice=4096
///   io_region_bytes = 4*4096 + 16 = 16400
///   io_region_words = ceilPow2(16400/8) = 4096
///   io_bytes = 4096 * 8 = 32768

/// Base address where input data is mapped
pub const INPUT_ADDR: u64 = 0x7FFF_A000;

/// Base address for output data
pub const OUTPUT_ADDR: u64 = 0x7FFF_B000;

/// Panic address
pub const PANIC_ADDR: u64 = 0x7FFF_C000;

/// Termination address
pub const TERMINATION_ADDR: u64 = 0x7FFF_C008;

/// Maximum input size (4KB, matching default MemoryConfig)
pub const MAX_INPUT: usize = 4096;

/// Maximum output size (4KB, matching default MemoryConfig)
pub const MAX_OUTPUT: usize = 4096;

/// Maximum number of output values (matches ZisK convention: 64 u32 values)
pub const MAX_OUTPUT_COUNT: usize = 64;

/// Input data header size: 8 bytes for data size (u64 LE)
pub const INPUT_HEADER_SIZE: u64 = 8;

// =============================================================================
// Input Functions
// =============================================================================

/// Read the input data size from the Jolt input region
/// The host encoder prepends an 8-byte size field
pub fn readInputSize() u64 {
    const size_ptr: *const u64 = @ptrFromInt(INPUT_ADDR);
    return size_ptr.*;
}

/// Read input data as a byte slice from the Jolt input region
/// Returns a slice pointing directly to the memory-mapped input data
pub fn readInputSlice() []const u8 {
    const size = readInputSize();
    const data_ptr: [*]const u8 = @ptrFromInt(INPUT_ADDR + INPUT_HEADER_SIZE);
    return data_ptr[0..size];
}

/// Read input data as a typed structure.
/// The structure must be packed and match the input data layout.
pub fn readInput(comptime T: type) T {
    const data_ptr: *const T = @ptrFromInt(INPUT_ADDR + INPUT_HEADER_SIZE);
    return data_ptr.*;
}

/// Read input from a specific offset within the input data region.
/// Useful for more complex input formats with multiple sections.
pub fn readInputAt(comptime T: type, offset: usize) T {
    const data_ptr: *const T = @ptrFromInt(INPUT_ADDR + INPUT_HEADER_SIZE + offset);
    return data_ptr.*;
}

// =============================================================================
// Architecture Detection
// =============================================================================

/// Check if running inside a zkVM.
/// For the Jolt backend, always returns true when compiled for RISC-V.
pub fn isZkVM() bool {
    return true;
}

/// Get the architecture ID.
/// Returns a Jolt-specific identifier.
pub fn getArchId() u64 {
    return 0x4A4F4C54; // "JOLT" in ASCII
}

// =============================================================================
// Output Functions
// =============================================================================

/// Set a u32 output value at the given index.
/// Jolt outputs are written to the output region as raw bytes.
/// Format: [count:u32][value0:u32][value1:u32]...
pub fn setOutput(id: usize, value: u32) void {
    if (id >= MAX_OUTPUT_COUNT) return;

    // Update the output count if needed
    const count_ptr: *volatile u32 = @ptrFromInt(OUTPUT_ADDR);
    const current_count = count_ptr.*;
    if (id + 1 > current_count) {
        count_ptr.* = @intCast(id + 1);
    }

    // Write the value
    const value_ptr: *volatile u32 = @ptrFromInt(OUTPUT_ADDR + 4 + 4 * id);
    value_ptr.* = value;
}

/// Set a u64 output value using two consecutive output slots.
/// The low 32 bits go to id, high 32 bits to id+1.
pub fn setOutputU64(id: usize, value: u64) void {
    setOutput(id, @truncate(value));
    setOutput(id + 1, @truncate(value >> 32));
}

/// Get the current output count
pub fn getOutputCount() u32 {
    const count_ptr: *volatile u32 = @ptrFromInt(OUTPUT_ADDR);
    return count_ptr.*;
}

/// Get a u32 output value at the given index.
/// Returns the value previously set with setOutput().
pub fn getOutput(id: usize) u32 {
    if (id >= MAX_OUTPUT_COUNT) return 0;

    const value_ptr: *volatile u32 = @ptrFromInt(OUTPUT_ADDR + 4 + 4 * id);
    return value_ptr.*;
}

/// Get a u64 output value from two consecutive output slots.
/// The low 32 bits from id, high 32 bits from id+1.
pub fn getOutputU64(id: usize) u64 {
    const low: u64 = getOutput(id);
    const high: u64 = getOutput(id + 1);
    return low | (high << 32);
}

/// Get all outputs as a slice of u32 values.
/// Returns a slice containing all output values from 0 to count-1.
pub fn getOutputSlice() []const u32 {
    const count = getOutputCount();
    if (count == 0) return &[_]u32{};

    const values_ptr: [*]const u32 = @ptrFromInt(OUTPUT_ADDR + 4);
    return values_ptr[0..count];
}

/// Commit a value to the public outputs.
/// This is an alias for setOutput, matching the Rust SDK's commit() function.
pub fn commit(id: usize, value: u32) void {
    setOutput(id, value);
}

/// Commit a u64 value to the public outputs using two slots.
pub fn commitU64(id: usize, value: u64) void {
    setOutputU64(id, value);
}

// =============================================================================
// Exit Functions
// =============================================================================

/// Exit the zkVM program.
/// Jolt detects termination via infinite loop (PC stops advancing).
pub fn exit(code: u64) noreturn {
    _ = code;
    // Jolt/Zolt detects termination when PC doesn't change
    while (true) {
        asm volatile (
            \\nop
        );
    }
}

/// Exit with success (code 0)
pub fn exitSuccess() noreturn {
    exit(0);
}

/// Exit with error (code 1) and write an error marker to output
pub fn exitError() noreturn {
    setOutput(0, 0xDEAD);
    exit(1);
}

// =============================================================================
// Debug Output
// =============================================================================

/// Write a single byte (no-op for Jolt, no UART equivalent)
pub fn uartWrite(byte: u8) void {
    _ = byte;
}

/// Write a string (no-op for Jolt)
pub fn uartPrint(str: []const u8) void {
    _ = str;
}

// =============================================================================
// Bump Allocator
// =============================================================================

/// A simple bump allocator suitable for zkVM programs.
/// Allocations are made from a contiguous memory region and never freed.
pub const BumpAllocator = struct {
    pos: usize,
    end: usize,

    const Self = @This();

    /// Create a bump allocator from explicit start and end addresses
    pub fn init(start: usize, end_addr: usize) Self {
        return .{
            .pos = start,
            .end = end_addr,
        };
    }

    /// Create a bump allocator using the linker-defined heap region
    pub fn initFromLinker() Self {
        return .{
            .pos = @intFromPtr(&_heap_start),
            .end = @intFromPtr(&_heap_end),
        };
    }

    /// Get a std.mem.Allocator interface to this bump allocator
    pub fn allocator(self: *Self) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    fn alloc(ctx: *anyopaque, len: usize, ptr_align: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        _ = ret_addr;
        const self: *Self = @ptrCast(@alignCast(ctx));

        const log2_align = @intFromEnum(ptr_align);
        const alignment: usize = @as(usize, 1) << @intCast(log2_align);
        const aligned_pos = std.mem.alignForward(usize, self.pos, alignment);
        const new_pos = aligned_pos + len;

        if (new_pos > self.end) return null;

        self.pos = new_pos;
        return @ptrFromInt(aligned_pos);
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        _ = ctx;
        _ = buf;
        _ = buf_align;
        _ = new_len;
        _ = ret_addr;
        return false;
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, ret_addr: usize) void {
        _ = ctx;
        _ = buf;
        _ = buf_align;
        _ = ret_addr;
    }

    fn remap(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        _ = ctx;
        _ = buf;
        _ = buf_align;
        _ = new_len;
        _ = ret_addr;
        return null;
    }

    const vtable = std.mem.Allocator.VTable{
        .alloc = alloc,
        .resize = resize,
        .free = free,
        .remap = remap,
    };
};

// Linker symbols for heap bounds
extern var _heap_start: u8;
extern var _heap_end: u8;

// Global bump allocator instance
var global_bump_allocator: ?BumpAllocator = null;

/// Get the global allocator for zkVM programs
pub fn allocator() std.mem.Allocator {
    if (global_bump_allocator == null) {
        global_bump_allocator = BumpAllocator.initFromLinker();
    }
    return global_bump_allocator.?.allocator();
}

// =============================================================================
// Entry Point Support
// =============================================================================

// BSS section symbols from linker
extern var _bss_start: u8;
extern var _bss_end: u8;

/// Type signature for the user's main function
pub const MainFn = *const fn () void;

/// Generate a _start entry point that calls the given main function.
///
/// Usage in your zkvm program:
///   comptime {
///       zkvm.exportEntryPoint(main);
///   }
///
///   fn main() void {
///       // your code here
///   }
pub fn exportEntryPoint(comptime mainFn: MainFn) void {
    const S = struct {
        fn callMain() void {
            mainFn();
        }

        export fn _start() linksection(".text.init") callconv(.naked) noreturn {
            asm volatile (
                // Set up stack pointer (use linker-defined symbol)
                \\la sp, _init_stack_top
                \\
                // Clear BSS
                \\la t0, _bss_start
                \\la t1, _bss_end
                \\1:
                \\bge t0, t1, 2f
                \\sd zero, 0(t0)
                \\addi t0, t0, 8
                \\j 1b
                \\2:
                \\
                // Call main
                \\call %[callMain]
                \\
                // Terminate via infinite loop (Jolt detects when PC stops advancing)
                \\3: j 3b
                :
                : [callMain] "s" (&callMain),
            );
            unreachable;
        }
    };
    _ = S._start;
}

// =============================================================================
// Panic Handler
// =============================================================================

/// Default panic handler for zkVM programs.
/// Writes an error marker to output and terminates.
pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    _ = msg;
    setOutput(0, 0xDEAD);
    exit(1);
}
