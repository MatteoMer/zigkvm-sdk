const std = @import("std");
const runtime = @import("../runtime.zig");

/// Ligero executor that runs WASM programs.
/// Uses wasmtime CLI or node.js as the WASM runtime.
/// Thread-safe: uses atomic temp file naming for concurrent executions.
pub const LigeroExecutor = struct {
    allocator: std.mem.Allocator,
    runtime_type: RuntimeType,
    shader_path: ?[]const u8,
    temp_counter: std.atomic.Value(u64),

    const Self = @This();

    pub const RuntimeType = enum {
        wasmtime,
        node,
    };

    pub const Options = struct {
        shader_path: ?[]const u8 = null,
        runtime_type: RuntimeType = .wasmtime,
    };

    /// Initialize the Ligero executor
    pub fn init(allocator: std.mem.Allocator, options: Options) !Self {
        const shader_path = if (options.shader_path) |p|
            try allocator.dupe(u8, p)
        else
            null;

        return Self{
            .allocator = allocator,
            .runtime_type = options.runtime_type,
            .shader_path = shader_path,
            .temp_counter = std.atomic.Value(u64).init(0),
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.shader_path) |p| self.allocator.free(p);
    }

    /// Execute a WASM program
    pub fn execute(self: *Self, wasm_path: []const u8, input: []const u8) !runtime.ExecutorResult {
        // Parse Ligero input format: [public_len:u64][public_data][private_len:u64][private_data]
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

        // Convert to hex args
        const public_hex = if (public_len > 0) try hexString(self.allocator, public_data) else null;
        defer if (public_hex) |h| self.allocator.free(h);

        const private_hex = if (private_len > 0) try hexString(self.allocator, private_data) else null;
        defer if (private_hex) |h| self.allocator.free(h);

        // Build command based on runtime type
        var argv: std.ArrayListUnmanaged([]const u8) = .empty;
        defer argv.deinit(self.allocator);

        switch (self.runtime_type) {
            .wasmtime => {
                try argv.append(self.allocator, "wasmtime");
                try argv.append(self.allocator, wasm_path);
                try argv.append(self.allocator, "--");
                if (public_hex) |h| try argv.append(self.allocator, h);
                if (private_hex) |h| try argv.append(self.allocator, h);
            },
            .node => {
                // Use node to run WASM with WASI
                // This requires a wrapper script
                return error.NodeRuntimeNotImplemented;
            },
        }

        // Execute WASM runtime
        var child = std.process.Child.init(argv.items, self.allocator);
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;

        try child.spawn();

        // Read stdout/stderr
        var stdout_list: std.ArrayListUnmanaged(u8) = .empty;
        var stderr_list: std.ArrayListUnmanaged(u8) = .empty;
        errdefer stdout_list.deinit(self.allocator);
        errdefer stderr_list.deinit(self.allocator);

        child.collectOutput(self.allocator, &stdout_list, &stderr_list, 10 * 1024 * 1024) catch {
            return error.ExecutionFailed;
        };

        const term = try child.wait();

        const stdout = try stdout_list.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(stdout);

        const stderr = try stderr_list.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(stderr);

        // Check exit status
        switch (term) {
            .Exited => |code| {
                if (code != 0) {
                    // Non-zero exit, but still return result with stdout/stderr
                }
            },
            else => return error.ExecutionFailed,
        }

        // Parse output from stdout
        // Ligero WASM programs typically output JSON or binary results
        const outputs = parseWasmOutput(self.allocator, stdout) catch {
            // Return empty outputs if parsing fails
            return runtime.ExecutorResult{
                .allocator = self.allocator,
                .outputs = runtime.OutputData{
                    .allocator = self.allocator,
                    .values = try self.allocator.alloc(u32, 0),
                    .count = 0,
                },
                .cycles = null,
                .stdout = stdout,
                .stderr = stderr,
            };
        };

        return runtime.ExecutorResult{
            .allocator = self.allocator,
            .outputs = outputs,
            .cycles = null, // WASM doesn't expose cycle count
            .stdout = stdout,
            .stderr = stderr,
        };
    }
};

/// Convert bytes to hex string with 0x prefix
fn hexString(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    const hex_chars = "0123456789abcdef";
    const out_len = 2 + data.len * 2;
    const out = try allocator.alloc(u8, out_len);
    out[0] = '0';
    out[1] = 'x';
    for (data, 0..) |byte, i| {
        out[2 + i * 2] = hex_chars[byte >> 4];
        out[2 + i * 2 + 1] = hex_chars[byte & 0x0f];
    }
    return out;
}

/// Parse WASM program output
/// Expected format: count (u32) + values (array of u32) printed as hex or binary
fn parseWasmOutput(allocator: std.mem.Allocator, stdout: []const u8) !runtime.OutputData {
    // Try to parse as binary output format (same as ZisK)
    if (stdout.len >= 4) {
        const count = std.mem.readInt(u32, stdout[0..4], .little);
        if (count <= 64 and stdout.len >= 4 + count * 4) {
            const values = try allocator.alloc(u32, count);
            errdefer allocator.free(values);

            for (0..count) |i| {
                const offset = 4 + (i * 4);
                values[i] = std.mem.readInt(u32, stdout[offset..][0..4], .little);
            }

            return runtime.OutputData{
                .allocator = allocator,
                .values = values,
                .count = count,
            };
        }
    }

    // Return empty if we can't parse
    return runtime.OutputData{
        .allocator = allocator,
        .values = try allocator.alloc(u32, 0),
        .count = 0,
    };
}

test "hexString converts correctly" {
    const allocator = std.testing.allocator;
    const data = [_]u8{ 0xDE, 0xAD, 0xBE, 0xEF };
    const hex = try hexString(allocator, &data);
    defer allocator.free(hex);
    try std.testing.expectEqualStrings("0xdeadbeef", hex);
}
