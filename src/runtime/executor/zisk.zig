const std = @import("std");
const runtime = @import("../runtime.zig");

/// ZisK executor that wraps the ziskemu subprocess.
/// Thread-safe: uses atomic temp file naming for concurrent executions.
pub const ZisKExecutor = struct {
    allocator: std.mem.Allocator,
    ziskemu_path: []const u8,
    max_cycles: ?u64,
    temp_counter: std.atomic.Value(u64),

    const Self = @This();

    pub const Options = struct {
        ziskemu_path: ?[]const u8 = null,
        max_cycles: ?u64 = null,
    };

    /// Initialize the ZisK executor
    pub fn init(allocator: std.mem.Allocator, options: Options) !Self {
        const ziskemu_path = if (options.ziskemu_path) |p|
            try allocator.dupe(u8, p)
        else
            try allocator.dupe(u8, "ziskemu");

        return Self{
            .allocator = allocator,
            .ziskemu_path = ziskemu_path,
            .max_cycles = options.max_cycles,
            .temp_counter = std.atomic.Value(u64).init(0),
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.ziskemu_path);
    }

    /// Execute a guest program using ziskemu
    pub fn execute(self: *Self, elf_path: []const u8, input: []const u8) !runtime.ExecutorResult {
        // Generate unique temp file names for thread safety
        const counter = self.temp_counter.fetchAdd(1, .monotonic);
        const timestamp = @as(u64, @intCast(std.time.timestamp()));

        const input_file = try std.fmt.allocPrint(
            self.allocator,
            "/tmp/zigkvm-{d}-{d}-input.bin",
            .{ timestamp, counter },
        );
        defer self.allocator.free(input_file);

        const output_file = try std.fmt.allocPrint(
            self.allocator,
            "/tmp/zigkvm-{d}-{d}-output.bin",
            .{ timestamp, counter },
        );
        defer self.allocator.free(output_file);

        // Write input to temp file
        {
            const file = try std.fs.cwd().createFile(input_file, .{});
            defer file.close();
            try file.writeAll(input);
        }
        defer std.fs.cwd().deleteFile(input_file) catch {};

        // Build command arguments
        var argv: std.ArrayListUnmanaged([]const u8) = .empty;
        defer argv.deinit(self.allocator);

        try argv.appendSlice(self.allocator, &[_][]const u8{
            self.ziskemu_path,
            "-e",
            elf_path,
            "-i",
            input_file,
            "-o",
            output_file,
            "-c", // Collect stats
            "-m", // Memory stats
        });

        // Add max cycles if specified
        if (self.max_cycles) |max| {
            const max_str = try std.fmt.allocPrint(self.allocator, "{d}", .{max});
            defer self.allocator.free(max_str);
            try argv.appendSlice(self.allocator, &[_][]const u8{ "--max-cycles", max_str });
        }

        // Execute ziskemu
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
        defer std.fs.cwd().deleteFile(output_file) catch {};

        const stdout = try stdout_list.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(stdout);

        const stderr = try stderr_list.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(stderr);

        // Check exit status
        const exit_code = switch (term) {
            .Exited => |code| code,
            else => return error.ExecutionFailed,
        };

        if (exit_code != 0) {
            // Return result with error info
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
        }

        // Parse output file
        const outputs = runtime.OutputData.fromFile(self.allocator, output_file) catch {
            // Output file might not exist if guest didn't produce output
            return runtime.ExecutorResult{
                .allocator = self.allocator,
                .outputs = runtime.OutputData{
                    .allocator = self.allocator,
                    .values = try self.allocator.alloc(u32, 0),
                    .count = 0,
                },
                .cycles = parseCycles(stdout),
                .stdout = stdout,
                .stderr = stderr,
            };
        };

        return runtime.ExecutorResult{
            .allocator = self.allocator,
            .outputs = outputs,
            .cycles = parseCycles(stdout),
            .stdout = stdout,
            .stderr = stderr,
        };
    }
};

/// Parse cycle count from ziskemu stdout
/// Looks for patterns like "Total cycles: 12345" or similar
fn parseCycles(stdout: []const u8) ?u64 {
    // Look for "cycles" in output and extract number
    var lines = std.mem.splitScalar(u8, stdout, '\n');
    while (lines.next()) |line| {
        if (std.mem.indexOf(u8, line, "cycles")) |_| {
            // Try to find a number in the line
            var i: usize = 0;
            while (i < line.len) : (i += 1) {
                if (std.ascii.isDigit(line[i])) {
                    var end = i;
                    while (end < line.len and std.ascii.isDigit(line[end])) : (end += 1) {}
                    return std.fmt.parseInt(u64, line[i..end], 10) catch null;
                }
            }
        }
    }
    return null;
}

test "parseCycles extracts cycle count" {
    const stdout = "Running...\nTotal cycles: 12345\nDone";
    try std.testing.expectEqual(@as(?u64, 12345), parseCycles(stdout));
}

test "parseCycles returns null for no match" {
    const stdout = "Running...\nDone";
    try std.testing.expectEqual(@as(?u64, null), parseCycles(stdout));
}
