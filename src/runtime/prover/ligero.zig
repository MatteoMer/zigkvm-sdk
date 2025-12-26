const std = @import("std");
const runtime = @import("../runtime.zig");

/// Ligero prover that wraps the webgpu_prover subprocess.
/// Thread-safe: uses atomic temp file naming for concurrent proofs.
pub const LigeroProver = struct {
    allocator: std.mem.Allocator,
    webgpu_prover_path: []const u8,
    webgpu_verifier_path: []const u8,
    shader_path: ?[]const u8,
    temp_counter: std.atomic.Value(u64),

    const Self = @This();

    pub const Options = struct {
        webgpu_prover_path: ?[]const u8 = null,
        webgpu_verifier_path: ?[]const u8 = null,
        shader_path: ?[]const u8 = null,
    };

    /// Initialize the Ligero prover
    pub fn init(allocator: std.mem.Allocator, options: Options) !Self {
        // Default paths are in ~/.ligero/bin/
        const home = std.posix.getenv("HOME") orelse "/tmp";

        const default_prover = try std.fmt.allocPrint(
            allocator,
            "{s}/.ligero/bin/webgpu_prover",
            .{home},
        );
        errdefer allocator.free(default_prover);

        const default_verifier = try std.fmt.allocPrint(
            allocator,
            "{s}/.ligero/bin/webgpu_verifier",
            .{home},
        );
        errdefer allocator.free(default_verifier);

        const default_shader = try std.fmt.allocPrint(
            allocator,
            "{s}/.ligero/src/ligero-prover/shader",
            .{home},
        );
        errdefer allocator.free(default_shader);

        const prover_path = if (options.webgpu_prover_path) |p| blk: {
            allocator.free(default_prover);
            break :blk try allocator.dupe(u8, p);
        } else default_prover;

        const verifier_path = if (options.webgpu_verifier_path) |p| blk: {
            allocator.free(default_verifier);
            break :blk try allocator.dupe(u8, p);
        } else default_verifier;

        const shader_path = if (options.shader_path) |p| blk: {
            allocator.free(default_shader);
            break :blk try allocator.dupe(u8, p);
        } else default_shader;

        return Self{
            .allocator = allocator,
            .webgpu_prover_path = prover_path,
            .webgpu_verifier_path = verifier_path,
            .shader_path = shader_path,
            .temp_counter = std.atomic.Value(u64).init(0),
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.webgpu_prover_path);
        self.allocator.free(self.webgpu_verifier_path);
        if (self.shader_path) |p| self.allocator.free(p);
    }

    /// Generate a ZK proof for the WASM program
    pub fn prove(self: *Self, wasm_path: []const u8, input: []const u8) !runtime.ProverResult {
        const start_time = std.time.milliTimestamp();

        // Generate unique temp directory for thread safety
        const counter = self.temp_counter.fetchAdd(1, .monotonic);
        const timestamp = @as(u64, @intCast(std.time.timestamp()));

        const temp_dir = try std.fmt.allocPrint(
            self.allocator,
            "/tmp/zigkvm-ligero-{d}-{d}",
            .{ timestamp, counter },
        );
        defer self.allocator.free(temp_dir);
        defer deleteDir(temp_dir);

        try std.fs.cwd().makePath(temp_dir);

        const config_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/ligero-config.json",
            .{temp_dir},
        );
        defer self.allocator.free(config_path);

        // Create Ligero config JSON
        try self.createConfig(config_path, wasm_path, input);

        // Execute webgpu_prover
        var child = std.process.Child.init(&[_][]const u8{
            self.webgpu_prover_path,
            config_path,
        }, self.allocator);

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

        // Read proof file (webgpu_prover outputs to temp dir)
        const proof_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/proof.bin",
            .{temp_dir},
        );
        defer self.allocator.free(proof_path);

        const proof_data = std.fs.cwd().readFileAlloc(
            self.allocator,
            proof_path,
            100 * 1024 * 1024,
        ) catch {
            // If no proof file, use stdout as proof data (some versions output there)
            const data = try self.allocator.dupe(u8, stdout);
            return runtime.ProverResult{
                .allocator = self.allocator,
                .outputs = runtime.OutputData{
                    .allocator = self.allocator,
                    .values = try self.allocator.alloc(u32, 0),
                    .count = 0,
                },
                .proof = runtime.Proof{
                    .allocator = self.allocator,
                    .data = data,
                    .backend = .ligero,
                },
                .proof_time_ms = @as(u64, @intCast(std.time.milliTimestamp() - start_time)),
                .stdout = stdout,
                .stderr = stderr,
            };
        };

        const proof_time = @as(u64, @intCast(std.time.milliTimestamp() - start_time));

        return runtime.ProverResult{
            .allocator = self.allocator,
            .outputs = runtime.OutputData{
                .allocator = self.allocator,
                .values = try self.allocator.alloc(u32, 0),
                .count = 0,
            },
            .proof = runtime.Proof{
                .allocator = self.allocator,
                .data = proof_data,
                .backend = .ligero,
            },
            .proof_time_ms = proof_time,
            .stdout = stdout,
            .stderr = stderr,
        };
    }

    /// Verify a Ligero proof
    pub fn verify(self: *Self, proof: *const runtime.Proof, public_inputs: ?[]const u8) !bool {
        // Generate unique temp directory
        const counter = self.temp_counter.fetchAdd(1, .monotonic);
        const timestamp = @as(u64, @intCast(std.time.timestamp()));

        const temp_dir = try std.fmt.allocPrint(
            self.allocator,
            "/tmp/zigkvm-ligero-verify-{d}-{d}",
            .{ timestamp, counter },
        );
        defer self.allocator.free(temp_dir);
        defer deleteDir(temp_dir);

        try std.fs.cwd().makePath(temp_dir);

        // Write proof to temp file
        const proof_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/proof.bin",
            .{temp_dir},
        );
        defer self.allocator.free(proof_path);

        {
            const file = try std.fs.cwd().createFile(proof_path, .{});
            defer file.close();
            try file.writeAll(proof.data);
        }

        // Create minimal config for verification
        const config_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/verify-config.json",
            .{temp_dir},
        );
        defer self.allocator.free(config_path);

        // Create verification config
        if (public_inputs) |pub_input| {
            try self.createVerifyConfig(config_path, proof_path, pub_input);
        } else {
            try self.createVerifyConfig(config_path, proof_path, &[_]u8{});
        }

        // Execute webgpu_verifier
        var child = std.process.Child.init(&[_][]const u8{
            self.webgpu_verifier_path,
            config_path,
        }, self.allocator);

        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;

        try child.spawn();

        _ = child.stdout.?.reader().readAllAlloc(self.allocator, 1024 * 1024) catch "";
        _ = child.stderr.?.reader().readAllAlloc(self.allocator, 1024 * 1024) catch "";

        const term = try child.wait();

        return switch (term) {
            .Exited => |code| code == 0,
            else => false,
        };
    }

    /// Create Ligero config JSON from input bytes
    fn createConfig(self: *Self, config_path: []const u8, wasm_path: []const u8, input: []const u8) !void {
        // Parse input format: [public_len:u64][public_data][private_len:u64][private_data]
        if (input.len < 16) {
            return error.InvalidInputFormat;
        }

        const public_len = std.mem.readInt(u64, input[0..8], .little);
        if (8 + public_len + 8 > input.len) {
            return error.InvalidInputFormat;
        }

        const public_data = input[8..][0..public_len];
        const private_len_offset = 8 + public_len;
        const private_len = std.mem.readInt(u64, input[private_len_offset..][0..8], .little);

        if (private_len_offset + 8 + private_len > input.len) {
            return error.InvalidInputFormat;
        }

        const private_data = input[private_len_offset + 8 ..][0..private_len];

        const has_public = public_len > 0;
        const has_private = private_len > 0;

        // Build JSON manually (avoid std.json complexity)
        const file = try std.fs.cwd().createFile(config_path, .{});
        defer file.close();

        var writer = file.writer();

        try writer.writeAll("{\n");
        try writer.print("  \"program\": \"{s}\",\n", .{wasm_path});
        if (self.shader_path) |sp| {
            try writer.print("  \"shader-path\": \"{s}\",\n", .{sp});
        }
        try writer.writeAll("  \"packing\": 8192,\n");
        try writer.writeAll("  \"private-indices\": [");
        if (has_public and has_private) {
            try writer.writeAll("2");
        } else if (has_private) {
            try writer.writeAll("1");
        }
        try writer.writeAll("],\n");
        try writer.writeAll("  \"args\": [");

        var first = true;
        if (has_public) {
            if (!first) try writer.writeAll(",");
            try writer.writeAll("\n    {\"hex\": \"");
            try writeHex(writer, public_data);
            try writer.writeAll("\"}");
            first = false;
        }
        if (has_private) {
            if (!first) try writer.writeAll(",");
            try writer.writeAll("\n    {\"hex\": \"");
            try writeHex(writer, private_data);
            try writer.writeAll("\"}");
        }

        try writer.writeAll("\n  ]\n}\n");
    }

    /// Create verification config JSON
    fn createVerifyConfig(self: *Self, config_path: []const u8, proof_path: []const u8, public_inputs: []const u8) !void {
        const file = try std.fs.cwd().createFile(config_path, .{});
        defer file.close();

        var writer = file.writer();

        try writer.writeAll("{\n");
        try writer.print("  \"proof\": \"{s}\",\n", .{proof_path});
        if (self.shader_path) |sp| {
            try writer.print("  \"shader-path\": \"{s}\",\n", .{sp});
        }
        if (public_inputs.len > 0) {
            try writer.writeAll("  \"public-inputs\": \"");
            try writeHex(writer, public_inputs);
            try writer.writeAll("\"\n");
        }
        try writer.writeAll("}\n");
    }
};

/// Write bytes as hex string with 0x prefix
fn writeHex(writer: anytype, data: []const u8) !void {
    const hex_chars = "0123456789abcdef";
    try writer.writeAll("0x");
    for (data) |byte| {
        try writer.writeByte(hex_chars[byte >> 4]);
        try writer.writeByte(hex_chars[byte & 0x0f]);
    }
}

/// Recursively delete a directory
fn deleteDir(path: []const u8) void {
    std.fs.cwd().deleteTree(path) catch {};
}
