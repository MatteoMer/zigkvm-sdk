// Ligero Backend for zigkvm-sdk
// Provides a Zig interface to Ligero's WASM-based zkVM
//
// Memory model:
//   - WASM linear memory (grows dynamically via WASI)
//   - Input data passed via WASI args (public in arg[0], private in arg[1])
//   - Output data committed via assert functions (env module)
//
// Args convention (argv[0] is program name/"Ligero"):
//   - argv[1]: public input data (hex-decoded bytes)
//   - argv[2]: private input data (hex-decoded bytes)
//   - If only one arg provided, treat argv[1] as private input

const std = @import("std");

// =============================================================================
// Constants
// =============================================================================

/// Maximum number of output values (matching native/zisk backends)
pub const MAX_OUTPUT_COUNT: usize = 64;

/// Unique architecture ID for Ligero
pub const ARCH_ID_LIGERO: u64 = 0x4C494745524F; // "LIGERO" in hex

// =============================================================================
// WASM Imports from Ligero Host Modules
// =============================================================================

// env module - constraint assertions and debug output
extern "env" fn assert_zero(value: i32) void;
extern "env" fn assert_one(value: i32) void;
extern "env" fn assert_equal(a: i32, b: i32) void;
extern "env" fn print_str(ptr: [*]const u8, len: i32) void;

// wasi_snapshot_preview1 - standard I/O for args
extern "wasi_snapshot_preview1" fn args_sizes_get(argc: *usize, argv_buf_size: *usize) i32;
extern "wasi_snapshot_preview1" fn args_get(argv: [*][*:0]u8, argv_buf: [*]u8) i32;

// =============================================================================
// Input Storage (Global State)
// =============================================================================

/// Cached public input data parsed from WASI args
var public_input_data: []const u8 = &[_]u8{};
var public_input_initialized: bool = false;

/// Cached private input data parsed from WASI args
var private_input_data: []const u8 = &[_]u8{};
var private_input_initialized: bool = false;

/// Indicates if args have been parsed
var args_parsed: bool = false;

// =============================================================================
// Args Parsing
// =============================================================================

/// Parse WASI args to extract public and private input data
/// Convention: argv[1] = public, argv[2] = private (if both present)
/// If only one arg beyond argv[0], treat argv[1] as private input
fn parseArgs() void {
    if (args_parsed) return;
    args_parsed = true;

    var argc: usize = 0;
    var argv_buf_size: usize = 0;

    // Get sizes
    const ret1 = args_sizes_get(&argc, &argv_buf_size);
    if (ret1 != 0 or argc == 0) {
        public_input_data = &[_]u8{};
        private_input_data = &[_]u8{};
        public_input_initialized = true;
        private_input_initialized = true;
        return;
    }

    // Allocate buffers using WASM allocator
    const alloc = std.heap.wasm_allocator;
    const argv = alloc.alloc([*:0]u8, argc) catch {
        public_input_data = &[_]u8{};
        private_input_data = &[_]u8{};
        public_input_initialized = true;
        private_input_initialized = true;
        return;
    };
    const argv_buf = alloc.alloc(u8, argv_buf_size) catch {
        public_input_data = &[_]u8{};
        private_input_data = &[_]u8{};
        public_input_initialized = true;
        private_input_initialized = true;
        return;
    };

    // Get args
    const ret2 = args_get(argv.ptr, argv_buf.ptr);
    if (ret2 != 0) {
        public_input_data = &[_]u8{};
        private_input_data = &[_]u8{};
        public_input_initialized = true;
        private_input_initialized = true;
        return;
    }

    const argv_slice = argv[0..argc];
    const argv_buf_end = @intFromPtr(argv_buf.ptr) + argv_buf_size;

    const get_arg_slice = struct {
        fn at(args: []const [*:0]u8, index: usize, buf_end: usize) []const u8 {
            if (index >= args.len) return &[_]u8{};
            const start = @intFromPtr(args[index]);
            const end = if (index + 1 < args.len) @intFromPtr(args[index + 1]) else buf_end;
            if (end <= start) return &[_]u8{};
            const len = end - start;
            return @as([*]const u8, @ptrFromInt(start))[0..len];
        }
    };

    const arg_count = if (argc > 0) argc - 1 else 0;
    if (arg_count >= 2) {
        // argv[1] = public, argv[2] = private
        public_input_data = get_arg_slice.at(argv_slice, 1, argv_buf_end);
        private_input_data = get_arg_slice.at(argv_slice, 2, argv_buf_end);
    } else if (arg_count == 1) {
        // Single arg beyond argv[0]: treat as private input
        public_input_data = &[_]u8{};
        private_input_data = get_arg_slice.at(argv_slice, 1, argv_buf_end);
    } else {
        public_input_data = &[_]u8{};
        private_input_data = &[_]u8{};
    }

    public_input_initialized = true;
    private_input_initialized = true;
}

// =============================================================================
// Public Input Functions
// =============================================================================

/// Read the public input data size
pub fn readPublicInputSize() u64 {
    parseArgs();
    return public_input_data.len;
}

/// Read public input data as a byte slice
pub fn readPublicInputSlice() []const u8 {
    parseArgs();
    return public_input_data;
}

/// Read public input data as a typed structure
pub fn readPublicInput(comptime T: type) T {
    parseArgs();
    if (public_input_data.len < @sizeOf(T)) {
        @panic("Public input data too small for requested type");
    }
    return std.mem.bytesToValue(T, public_input_data[0..@sizeOf(T)]);
}

/// Read public input from a specific offset
pub fn readPublicInputAt(comptime T: type, offset: usize) T {
    parseArgs();
    if (offset + @sizeOf(T) > public_input_data.len) {
        @panic("Public input offset out of bounds");
    }
    return std.mem.bytesToValue(T, public_input_data[offset..][0..@sizeOf(T)]);
}

// =============================================================================
// Private Input Functions
// =============================================================================

/// Read the private input data size
pub fn readPrivateInputSize() u64 {
    parseArgs();
    return private_input_data.len;
}

/// Read private input data as a byte slice
pub fn readPrivateInputSlice() []const u8 {
    parseArgs();
    return private_input_data;
}

/// Read private input data as a typed structure
pub fn readPrivateInput(comptime T: type) T {
    parseArgs();
    if (private_input_data.len < @sizeOf(T)) {
        @panic("Private input data too small for requested type");
    }
    return std.mem.bytesToValue(T, private_input_data[0..@sizeOf(T)]);
}

/// Read private input from a specific offset
pub fn readPrivateInputAt(comptime T: type, offset: usize) T {
    parseArgs();
    if (offset + @sizeOf(T) > private_input_data.len) {
        @panic("Private input offset out of bounds");
    }
    return std.mem.bytesToValue(T, private_input_data[offset..][0..@sizeOf(T)]);
}

// =============================================================================
// Backward Compatible Input Functions (defaults to private)
// =============================================================================

/// Read the input data size (private input for backward compatibility)
pub fn readInputSize() u64 {
    return readPrivateInputSize();
}

/// Read input data as a byte slice (private input for backward compatibility)
pub fn readInputSlice() []const u8 {
    return readPrivateInputSlice();
}

/// Read input data as a typed structure (private input for backward compatibility)
pub fn readInput(comptime T: type) T {
    return readPrivateInput(T);
}

/// Read input from a specific offset (private input for backward compatibility)
pub fn readInputAt(comptime T: type, offset: usize) T {
    return readPrivateInputAt(T, offset);
}

// =============================================================================
// Architecture Detection
// =============================================================================

/// Always returns true for Ligero backend (running in zkVM)
pub fn isZkVM() bool {
    return true;
}

/// Returns unique ID for Ligero architecture
pub fn getArchId() u64 {
    return ARCH_ID_LIGERO;
}

// =============================================================================
// Output Storage (Global State)
// =============================================================================

/// Output values buffer
var output_values: [MAX_OUTPUT_COUNT]u32 = [_]u32{0} ** MAX_OUTPUT_COUNT;
var output_count: u32 = 0;

// =============================================================================
// Output Functions
// =============================================================================

/// Set a u32 output value at the given index.
/// The value is committed to the proof via assert_equal.
pub fn setOutput(id: usize, value: u32) void {
    if (id >= MAX_OUTPUT_COUNT) return;

    if (id + 1 > output_count) {
        output_count = @intCast(id + 1);
    }

    output_values[id] = value;

    // Commit to proof by asserting value equals itself
    // This makes the value public in the constraint system
    assert_equal(@bitCast(value), @bitCast(value));
}

/// Set a u64 output value using two consecutive output slots.
/// Low 32 bits go to id, high 32 bits to id+1.
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
    if (id >= MAX_OUTPUT_COUNT) return 0;
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

/// Commit a value to the public outputs (alias for setOutput)
pub fn commit(id: usize, value: u32) void {
    setOutput(id, value);
}

/// Commit a u64 value to the public outputs
pub fn commitU64(id: usize, value: u64) void {
    setOutputU64(id, value);
}

// =============================================================================
// Exit Functions
// =============================================================================

/// Exit the zkVM program with the given exit code.
/// WASM doesn't have a native exit syscall, so we use unreachable.
pub fn exit(code: u64) noreturn {
    _ = code;
    // For non-zero exit, mark error in output
    unreachable;
}

/// Exit with success
pub fn exitSuccess() noreturn {
    exit(0);
}

/// Exit with error and write an error marker to output
pub fn exitError() noreturn {
    setOutput(0, 0xDEAD);
    exit(1);
}

// =============================================================================
// Debug Output
// =============================================================================

/// Write a single byte to debug output
pub fn uartWrite(byte: u8) void {
    print_str(@ptrCast(&byte), 1);
}

/// Write a string to debug output
pub fn uartPrint(str: []const u8) void {
    print_str(str.ptr, @intCast(str.len));
}

// =============================================================================
// Allocator
// =============================================================================

/// BumpAllocator stub for API compatibility with other backends.
/// Uses WASM allocator internally.
pub const BumpAllocator = struct {
    const Self = @This();

    pub fn init(_: usize, _: usize) Self {
        return .{};
    }

    pub fn initFromLinker() Self {
        return .{};
    }

    pub fn allocator(_: *Self) std.mem.Allocator {
        return std.heap.wasm_allocator;
    }
};

/// Get the allocator (uses WASM allocator)
pub fn allocator() std.mem.Allocator {
    return std.heap.wasm_allocator;
}

// =============================================================================
// Entry Point Support
// =============================================================================

/// Type signature for the user's main function
pub const MainFn = *const fn () void;

/// For WASI, entry point export is a no-op.
/// The WASI runtime handles _start automatically, and Zig's runtime
/// will call the user's main() function.
///
/// Usage in your zkvm program:
///   comptime {
///       zkvm.exportEntryPoint(main);
///   }
///
///   pub fn main() void {
///       // your code here
///   }
///
/// Note: For WASI, the main function should be `pub fn main() void`
/// so that Zig's runtime can call it.
pub fn exportEntryPoint(comptime mainFn: MainFn) void {
    _ = mainFn;
    // No-op for WASI - Zig's runtime handles entry point
}

// =============================================================================
// Panic Handler
// =============================================================================

/// Default panic handler for zkVM programs.
/// Writes an error marker to output and traps.
pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    uartPrint("PANIC: ");
    uartPrint(msg);
    uartPrint("\n");
    setOutput(0, 0xDEAD);
    unreachable;
}
