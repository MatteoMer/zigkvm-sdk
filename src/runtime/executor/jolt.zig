const std = @import("std");
const runtime = @import("../runtime.zig");
const zolt = @import("zolt");

/// Jolt executor that uses zolt's emulator as a library.
/// No subprocess needed - execution happens in-process.
pub const JoltExecutor = struct {
    allocator: std.mem.Allocator,
    heap_size: u64,

    const Self = @This();

    pub const Options = struct {
        /// Heap size for the emulated program (default: 32KB)
        heap_size: u64 = 32768,
    };

    pub fn init(allocator: std.mem.Allocator, options: Options) !Self {
        return Self{
            .allocator = allocator,
            .heap_size = options.heap_size,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    /// Execute a guest program using zolt's emulator
    pub fn execute(self: *Self, elf_path: []const u8, input: []const u8) !runtime.ExecutorResult {
        // Load the ELF file
        var loader = zolt.host.ELFLoader.init(self.allocator);
        var program = try loader.loadFile(elf_path);
        defer program.deinit();

        // Create memory config matching the program
        var config = zolt.common.MemoryConfig{
            .program_size = program.bytecode.len,
            .heap_size = self.heap_size,
        };

        // Initialize emulator
        var emulator = zolt.tracer.Emulator.init(self.allocator, &config);
        defer emulator.deinit();

        // Load program into emulator memory
        try emulator.loadProgramAt(program.bytecode, program.base_address);

        // Set input data
        if (input.len > 0) {
            try emulator.setInputs(input);
        }

        // Set entry point
        emulator.state.pc = program.entry_point;

        // Run to completion
        emulator.run() catch {};

        // Extract outputs from the JoltDevice
        const output_bytes = emulator.device.outputs.items;
        const outputs = if (output_bytes.len >= 4) blk: {
            break :blk try runtime.OutputData.fromBytes(self.allocator, output_bytes);
        } else blk: {
            break :blk runtime.OutputData{
                .allocator = self.allocator,
                .values = try self.allocator.alloc(u32, 0),
                .count = 0,
            };
        };

        return runtime.ExecutorResult{
            .allocator = self.allocator,
            .outputs = outputs,
            .cycles = emulator.state.cycle,
            .stdout = null,
            .stderr = null,
        };
    }
};
