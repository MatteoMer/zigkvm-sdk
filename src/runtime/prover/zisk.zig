const std = @import("std");
const runtime = @import("../runtime.zig");

/// ZisK prover that wraps the cargo-zisk subprocess.
/// Thread-safe: uses atomic temp directory naming for concurrent proofs.
pub const ZisKProver = struct {
    allocator: std.mem.Allocator,
    cargo_zisk_path: []const u8,
    temp_counter: std.atomic.Value(u64),

    const Self = @This();

    pub const Options = struct {
        cargo_zisk_path: ?[]const u8 = null,
    };

    /// Initialize the ZisK prover
    pub fn init(allocator: std.mem.Allocator, options: Options) !Self {
        const cargo_zisk_path = if (options.cargo_zisk_path) |p|
            try allocator.dupe(u8, p)
        else
            try allocator.dupe(u8, "cargo-zisk");

        return Self{
            .allocator = allocator,
            .cargo_zisk_path = cargo_zisk_path,
            .temp_counter = std.atomic.Value(u64).init(0),
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.cargo_zisk_path);
    }

    /// Generate a proof for the guest program
    pub fn prove(self: *Self, elf_path: []const u8, input: []const u8) !runtime.ProverResult {
        const start_time = std.time.milliTimestamp();

        // Generate unique temp directory for thread safety
        const counter = self.temp_counter.fetchAdd(1, .monotonic);
        const timestamp = @as(u64, @intCast(std.time.timestamp()));

        const temp_dir = try std.fmt.allocPrint(
            self.allocator,
            "/tmp/zigkvm-proof-{d}-{d}",
            .{ timestamp, counter },
        );
        defer self.allocator.free(temp_dir);
        defer deleteDir(temp_dir);

        const input_file = try std.fmt.allocPrint(
            self.allocator,
            "{s}/input.bin",
            .{temp_dir},
        );
        defer self.allocator.free(input_file);

        const output_dir = try std.fmt.allocPrint(
            self.allocator,
            "{s}/proofs",
            .{temp_dir},
        );
        defer self.allocator.free(output_dir);

        // Create directories
        try std.fs.cwd().makePath(temp_dir);
        try std.fs.cwd().makePath(output_dir);

        // cargo-zisk expects a nested proofs/proofs dir (quirk of the tool)
        const nested_proofs = try std.fmt.allocPrint(
            self.allocator,
            "{s}/proofs",
            .{output_dir},
        );
        defer self.allocator.free(nested_proofs);
        try std.fs.cwd().makePath(nested_proofs);

        // Write input to temp file
        {
            const file = try std.fs.cwd().createFile(input_file, .{});
            defer file.close();
            try file.writeAll(input);
        }

        // Build command arguments
        var argv: std.ArrayListUnmanaged([]const u8) = .empty;
        defer argv.deinit(self.allocator);

        try argv.appendSlice(self.allocator, &[_][]const u8{
            self.cargo_zisk_path,
            "prove",
            "--elf",
            elf_path,
            "--emulator",
            "--input",
            input_file,
            "--output-dir",
            output_dir,
            "-vvvv",
            "-a", // Aggregation
            "-y", // Skip confirmations
        });

        // Execute cargo-zisk prove
        var child = std.process.Child.init(argv.items, self.allocator);
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;

        try child.spawn();

        // Read stdout/stderr
        var stdout_list: std.ArrayListUnmanaged(u8) = .empty;
        var stderr_list: std.ArrayListUnmanaged(u8) = .empty;
        errdefer stdout_list.deinit(self.allocator);
        errdefer stderr_list.deinit(self.allocator);

        child.collectOutput(self.allocator, &stdout_list, &stderr_list, 100 * 1024 * 1024) catch {
            return error.ProvingFailed;
        };

        const term = try child.wait();

        const stdout = try stdout_list.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(stdout);

        const stderr = try stderr_list.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(stderr);

        // Check exit status
        const exit_code = switch (term) {
            .Exited => |code| code,
            else => return error.ProvingFailed,
        };

        if (exit_code != 0) {
            self.allocator.free(stdout);
            self.allocator.free(stderr);
            return error.ProvingFailed;
        }

        // Read proof file
        const proof_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/vadcop_final_proof.bin",
            .{output_dir},
        );
        defer self.allocator.free(proof_path);

        const proof_data = std.fs.cwd().readFileAlloc(
            self.allocator,
            proof_path,
            100 * 1024 * 1024, // 100MB max
        ) catch |err| {
            self.allocator.free(stdout);
            self.allocator.free(stderr);
            return err;
        };
        errdefer self.allocator.free(proof_data);

        // Read output file
        const output_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/output.bin",
            .{output_dir},
        );
        defer self.allocator.free(output_path);

        const outputs = runtime.OutputData.fromFile(self.allocator, output_path) catch {
            // Output might not exist
            runtime.OutputData{
                .allocator = self.allocator,
                .values = try self.allocator.alloc(u32, 0),
                .count = 0,
            };
        };

        const proof_time = @as(u64, @intCast(std.time.milliTimestamp() - start_time));

        return runtime.ProverResult{
            .allocator = self.allocator,
            .outputs = outputs,
            .proof = runtime.Proof{
                .allocator = self.allocator,
                .data = proof_data,
                .backend = .zisk,
            },
            .proof_time_ms = proof_time,
            .stdout = stdout,
            .stderr = stderr,
        };
    }

    /// Verify a proof
    pub fn verify(self: *Self, proof: *const runtime.Proof, public_inputs: ?[]const u8) !bool {
        _ = public_inputs; // ZisK doesn't use separate public inputs

        // Generate unique temp file for proof
        const counter = self.temp_counter.fetchAdd(1, .monotonic);
        const timestamp = @as(u64, @intCast(std.time.timestamp()));

        const proof_file = try std.fmt.allocPrint(
            self.allocator,
            "/tmp/zigkvm-verify-{d}-{d}.bin",
            .{ timestamp, counter },
        );
        defer self.allocator.free(proof_file);

        // Write proof to temp file
        {
            const file = try std.fs.cwd().createFile(proof_file, .{});
            defer file.close();
            try file.writeAll(proof.data);
        }
        defer std.fs.cwd().deleteFile(proof_file) catch {};

        // Build command
        var child = std.process.Child.init(&[_][]const u8{
            self.cargo_zisk_path,
            "verify",
            "--proof",
            proof_file,
        }, self.allocator);

        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;

        try child.spawn();

        // We don't care about output for verification, just exit code
        _ = child.stdout.?.reader().readAllAlloc(self.allocator, 1024 * 1024) catch "";
        _ = child.stderr.?.reader().readAllAlloc(self.allocator, 1024 * 1024) catch "";

        const term = try child.wait();

        return switch (term) {
            .Exited => |code| code == 0,
            else => false,
        };
    }
};

/// Recursively delete a directory
fn deleteDir(path: []const u8) void {
    std.fs.cwd().deleteTree(path) catch {};
}
