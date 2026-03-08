const std = @import("std");
const runtime = @import("../runtime.zig");
const zolt = @import("zolt");

const BN254Scalar = zolt.field.BN254Scalar;

/// Jolt prover that uses zolt's JoltProver as a library.
/// No subprocess needed - proving happens in-process.
pub const JoltProver = struct {
    allocator: std.mem.Allocator,
    srs_path: ?[]const u8,
    heap_size: u64,

    const Self = @This();

    pub const Options = struct {
        /// Path to Dory SRS file (optional, will generate if not provided)
        srs_path: ?[]const u8 = null,
        /// Heap size for the emulated program (default: 32KB)
        heap_size: u64 = 32768,
    };

    pub fn init(allocator: std.mem.Allocator, options: Options) !Self {
        return Self{
            .allocator = allocator,
            .srs_path = if (options.srs_path) |p| try allocator.dupe(u8, p) else null,
            .heap_size = options.heap_size,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.srs_path) |p| self.allocator.free(p);
    }

    /// Generate a proof for the guest program
    pub fn prove(self: *Self, elf_path: []const u8, input: []const u8) !runtime.ProverResult {
        const start_time = std.time.milliTimestamp();

        // Load the ELF file
        var loader = zolt.host.ELFLoader.init(self.allocator);
        var program = try loader.loadFile(elf_path);
        defer program.deinit();

        // First execute to get outputs
        var config = zolt.common.MemoryConfig{
            .program_size = program.bytecode.len,
            .heap_size = self.heap_size,
        };

        var emulator = zolt.tracer.Emulator.init(self.allocator, &config);
        defer emulator.deinit();

        try emulator.loadProgramAt(program.bytecode, program.base_address);
        if (input.len > 0) {
            try emulator.setInputs(input);
        }
        emulator.state.pc = program.entry_point;
        emulator.run() catch {};

        // Extract outputs
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

        // Generate proof using zolt's JoltProver (from zkvm/mod.zig, has high-level prove API)
        var prover_inst = zolt.zkvm.JoltProver(BN254Scalar).init(self.allocator);

        var jolt_bundle = try prover_inst.proveJoltCompatibleWithDoryAndSrsAtAddress(
            program.bytecode,
            input,
            self.srs_path,
            program.base_address,
            program.entry_point,
        );
        defer jolt_bundle.deinit();

        // Serialize the proof
        const proof_data = try prover_inst.serializeJoltProofWithDory(&jolt_bundle);

        const proof_time = @as(u64, @intCast(std.time.milliTimestamp() - start_time));

        return runtime.ProverResult{
            .allocator = self.allocator,
            .outputs = outputs,
            .proof = runtime.Proof{
                .allocator = self.allocator,
                .data = proof_data,
                .backend = .jolt,
            },
            .proof_time_ms = proof_time,
            .stdout = null,
            .stderr = null,
        };
    }

    /// Verify a proof (not yet implemented - requires verifier integration)
    pub fn verify(self: *Self, proof: *const runtime.Proof, public_inputs: ?[]const u8) !bool {
        _ = self;
        _ = proof;
        _ = public_inputs;
        return error.VerificationNotImplemented;
    }
};
