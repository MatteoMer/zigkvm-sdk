// ZisK Backend for zigkvm-sdk
// Provides a Zig interface to the ZisK zkVM
//
// Memory map:
//   ROM_ADDR:           0x80000000 - program code
//   INPUT_ADDR:         0x90000000 - input data (read-only)
//   RAM_ADDR:           0xa0000000 - system/registers
//   OUTPUT_ADDR:        0xa0010000 - output data
//   AVAILABLE_MEM_ADDR: 0xa0030000 - program memory (heap/stack)
//   END OF RAM:         0xc0000000

const std = @import("std");

// =============================================================================
// Memory Constants
// =============================================================================

/// Base address where input data is mapped
pub const INPUT_ADDR: u64 = 0x9000_0000;

/// Base address for output data
pub const OUTPUT_ADDR: u64 = 0xa001_0000;

/// UART address for debug output
pub const UART_ADDR: u64 = 0xa000_0200;

/// Architecture ID for ZisK (used to detect if running in zkVM)
pub const ARCH_ID_ZISK: u64 = 0xFFFEEEE;

/// QEMU exit address
pub const QEMU_EXIT_ADDR: u64 = 0x100000;

/// QEMU exit code for success
pub const QEMU_EXIT_CODE: u64 = 0x5555;

/// QEMU output address (fallback when not running on ZisK)
pub const QEMU_OUTPUT_ADDR: u64 = 0x1000_0000;

/// Maximum input size (8KB)
pub const MAX_INPUT: usize = 0x2000;

/// Maximum output size (64KB)
pub const MAX_OUTPUT: usize = 0x1_0000;

/// Maximum number of output values (64 u32 values)
pub const MAX_OUTPUT_COUNT: usize = 64;

/// Start of available memory for heap/stack
pub const AVAILABLE_MEM_ADDR: u64 = 0xa003_0000;

/// End of RAM
pub const RAM_END: u64 = 0xc000_0000;

/// Default stack top (1MB above available memory start)
pub const DEFAULT_STACK_TOP: u64 = 0xa013_0000;

// =============================================================================
// Input Functions
// =============================================================================

/// Offset where ziskemu loads the input file into the INPUT region.
/// The file content starts at INPUT_ADDR + this offset.
pub const INPUT_FILE_OFFSET: u64 = 16;

/// Within the input file format:
/// - Offset 0: reserved (8 bytes)
/// - Offset 8: data size (8 bytes, little-endian u64)
/// - Offset 16: actual data
pub const INPUT_HEADER_SIZE: u64 = 16;

/// Read the input data size from the ZisK input region
pub fn readInputSize() u64 {
    const size_ptr: *const u64 = @ptrFromInt(INPUT_ADDR + INPUT_FILE_OFFSET + 8);
    return size_ptr.*;
}

/// Read input data as a byte slice from the ZisK input region
/// Returns a slice pointing directly to the memory-mapped input data
pub fn readInputSlice() []const u8 {
    const size = readInputSize();
    const data_ptr: [*]const u8 = @ptrFromInt(INPUT_ADDR + INPUT_FILE_OFFSET + INPUT_HEADER_SIZE);
    return data_ptr[0..size];
}

/// Read input data as a typed structure.
/// The structure must be packed and match the input data layout.
pub fn readInput(comptime T: type) T {
    const data_ptr: *const T = @ptrFromInt(INPUT_ADDR + INPUT_FILE_OFFSET + INPUT_HEADER_SIZE);
    return data_ptr.*;
}

/// Read input from a specific offset within the input data region.
/// Useful for more complex input formats with multiple sections.
pub fn readInputAt(comptime T: type, offset: usize) T {
    const data_ptr: *const T = @ptrFromInt(INPUT_ADDR + INPUT_FILE_OFFSET + INPUT_HEADER_SIZE + offset);
    return data_ptr.*;
}

// =============================================================================
// Architecture Detection
// =============================================================================

/// Check if running inside ZisK zkVM by reading the marchid CSR.
/// Returns true if running on ZisK, false if running on QEMU or other emulator.
pub fn isZkVM() bool {
    const arch_id = asm volatile ("csrr %[ret], marchid"
        : [ret] "=r" (-> u64),
    );
    return arch_id == ARCH_ID_ZISK;
}

/// Get the architecture ID from the marchid CSR.
pub fn getArchId() u64 {
    return asm volatile ("csrr %[ret], marchid"
        : [ret] "=r" (-> u64),
    );
}

// =============================================================================
// Output Functions
// =============================================================================

/// Get the base address for outputs based on architecture detection.
/// Returns OUTPUT_ADDR for ZisK, QEMU_OUTPUT_ADDR for QEMU.
fn getOutputBaseAddr() u64 {
    if (isZkVM()) {
        return OUTPUT_ADDR;
    } else {
        return QEMU_OUTPUT_ADDR;
    }
}

/// Set a u32 output value at the given index.
/// ZisK supports up to 64 output values (id 0-63).
/// This is the primary way to return results from a zkVM program.
pub fn setOutput(id: usize, value: u32) void {
    if (id >= MAX_OUTPUT_COUNT) return;

    const base_addr = getOutputBaseAddr();

    // Update the output count if needed
    const count_ptr: *volatile u32 = @ptrFromInt(base_addr);
    const current_count = count_ptr.*;
    if (id + 1 > current_count) {
        count_ptr.* = @intCast(id + 1);
    }

    // Write the value
    const value_ptr: *volatile u32 = @ptrFromInt(base_addr + 4 + 4 * id);
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
    const base_addr = getOutputBaseAddr();
    const count_ptr: *volatile u32 = @ptrFromInt(base_addr);
    return count_ptr.*;
}

/// Get a u32 output value at the given index.
/// Returns the value previously set with setOutput().
pub fn getOutput(id: usize) u32 {
    if (id >= MAX_OUTPUT_COUNT) return 0;

    const base_addr = getOutputBaseAddr();
    const value_ptr: *volatile u32 = @ptrFromInt(base_addr + 4 + 4 * id);
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
    const base_addr = getOutputBaseAddr();
    const count = getOutputCount();
    if (count == 0) return &[_]u32{};

    const values_ptr: [*]const u32 = @ptrFromInt(base_addr + 4);
    return values_ptr[0..count];
}

/// Commit a value to the public outputs.
/// This is an alias for setOutput, matching the Rust SDK's commit() function.
/// The committed values become public inputs to the proof verification.
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

/// Exit the zkVM program with the given exit code.
/// Code 0 indicates success, non-zero indicates error.
pub fn exit(code: u64) noreturn {
    asm volatile (
        \\ecall
        :
        : [a7] "{a7}" (@as(u64, 93)),
          [a0] "{a0}" (code),
    );
    unreachable;
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
// Debug Output (UART)
// =============================================================================

/// Write a single byte to the UART for debug output.
/// Note: This may not be captured in all ZisK execution modes.
pub fn uartWrite(byte: u8) void {
    const uart_ptr: *volatile u8 = @ptrFromInt(UART_ADDR);
    uart_ptr.* = byte;
}

/// Write a string to the UART for debug output.
pub fn uartPrint(str: []const u8) void {
    for (str) |byte| {
        uartWrite(byte);
    }
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
        return false; // No resize support
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, ret_addr: usize) void {
        _ = ctx;
        _ = buf;
        _ = buf_align;
        _ = ret_addr;
        // No-op: bump allocator doesn't free
    }

    fn remap(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        _ = ctx;
        _ = buf;
        _ = buf_align;
        _ = new_len;
        _ = ret_addr;
        return null; // No remap support
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
/// This is a comptime function that generates inline assembly for the entry point.
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
                // Exit via ecall (syscall 93)
                \\li a7, 93
                \\li a0, 0
                \\ecall
                \\
                // Infinite loop as fallback
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
/// Writes an error marker to output and exits with code 1.
pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    _ = msg;
    setOutput(0, 0xDEAD);
    exit(1);
}
