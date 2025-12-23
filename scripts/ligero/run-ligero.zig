const std = @import("std");

/// Run a Ligero binary with a JSON config file as a single argument.
///
/// Usage:
///   zig run scripts/ligero/run-ligero.zig -- <command> <config_json>
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 3) {
        std.debug.print("Usage: {s} <command> <config_json>\n", .{args[0]});
        std.process.exit(1);
    }

    const command = args[1];
    const config_path = args[2];

    const config_file = try std.fs.cwd().openFile(config_path, .{});
    defer config_file.close();
    const config_json = try config_file.readToEndAlloc(allocator, 10 * 1024 * 1024);
    defer allocator.free(config_json);

    var child = std.process.Child.init(&[_][]const u8{ command, config_json }, allocator);
    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    const term = try child.spawnAndWait();
    switch (term) {
        .Exited => |code| {
            if (code != 0) std.process.exit(code);
        },
        else => std.process.exit(1),
    }
}
