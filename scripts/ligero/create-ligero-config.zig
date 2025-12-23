const std = @import("std");

/// Create Ligero JSON config from input.bin
///
/// Usage:
///   zig run scripts/ligero/create-ligero-config.zig -- <wasm_path> <shader_path> <input_bin> <output_json>
///
/// Input.bin format (from ligero encoder):
///   [public_len:u64][public_data][private_len:u64][private_data]
///
/// Output JSON format:
///   {
///     "program": "app.wasm",
///     "shader-path": "./shader",
///     "packing": 8192,
///     "private-indices": [2],   // arg[2] is private (indices start at 1)
///     "args": [
///       {"hex": "0x...public..."},
///       {"hex": "0x...private..."}
///     ]
///   }
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 5) {
        std.debug.print("Usage: {s} <wasm_path> <shader_path> <input_bin> <output_json>\n", .{args[0]});
        std.debug.print("\nCreates Ligero JSON config from input.bin\n", .{});
        std.debug.print("\nArguments:\n", .{});
        std.debug.print("  wasm_path    - Path to the WASM program\n", .{});
        std.debug.print("  shader_path  - Path to Ligero shader directory\n", .{});
        std.debug.print("  input_bin    - Path to input.bin file\n", .{});
        std.debug.print("  output_json  - Path to output JSON config file\n", .{});
        std.process.exit(1);
    }

    const wasm_path = args[1];
    const shader_path = args[2];
    const input_bin_path = args[3];
    const output_json_path = args[4];

    // Read input.bin
    const input_file = try std.fs.cwd().openFile(input_bin_path, .{});
    defer input_file.close();
    const input_data = try input_file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(input_data);

    // Parse input.bin format: [public_len:u64][public_data][private_len:u64][private_data]
    if (input_data.len < 16) {
        std.debug.print("Error: input.bin too small (need at least 16 bytes for headers)\n", .{});
        std.process.exit(1);
    }

    const public_len = std.mem.readInt(u64, input_data[0..8], .little);
    if (8 + public_len + 8 > input_data.len) {
        std.debug.print("Error: input.bin corrupted (public_len={d} exceeds file size)\n", .{public_len});
        std.process.exit(1);
    }

    const public_data = input_data[8..][0..public_len];
    const private_len_offset = 8 + public_len;
    const private_len = std.mem.readInt(u64, input_data[private_len_offset..][0..8], .little);

    if (private_len_offset + 8 + private_len > input_data.len) {
        std.debug.print("Error: input.bin corrupted (private_len={d} exceeds file size)\n", .{private_len});
        std.process.exit(1);
    }

    const private_data = input_data[private_len_offset + 8 ..][0..private_len];

    // Create JSON - build in memory then write
    var json_buf: std.ArrayListUnmanaged(u8) = .{};
    defer json_buf.deinit(allocator);
    const writer = json_buf.writer(allocator);
    var json_stream: std.json.Stringify = .{
        .writer = &writer,
        .options = .{ .whitespace = .indent_2 },
    };

    // Determine args and private-indices based on what data we have
    const has_public = public_len > 0;
    const has_private = private_len > 0;

    try json_stream.beginObject();
    try json_stream.objectField("program");
    try json_stream.write(wasm_path);
    try json_stream.objectField("shader-path");
    try json_stream.write(shader_path);
    try json_stream.objectField("packing");
    try json_stream.write(@as(u32, 8192));
    try json_stream.objectField("private-indices");
    try json_stream.beginArray();
    if (has_public and has_private) {
        // Both public and private: argv[1] = public, argv[2] = private
        try json_stream.write(@as(u32, 2));
    } else if (has_private) {
        // Only private: argv[1] = private
        try json_stream.write(@as(u32, 1));
    }
    try json_stream.endArray();
    try json_stream.objectField("args");
    try json_stream.beginArray();
    if (has_public) {
        const hex = try hexString(allocator, public_data);
        defer allocator.free(hex);
        try json_stream.beginObject();
        try json_stream.objectField("hex");
        try json_stream.write(hex);
        try json_stream.endObject();
    }
    if (has_private) {
        const hex = try hexString(allocator, private_data);
        defer allocator.free(hex);
        try json_stream.beginObject();
        try json_stream.objectField("hex");
        try json_stream.write(hex);
        try json_stream.endObject();
    }
    try json_stream.endArray();
    try json_stream.endObject();

    // Write to file
    const output_file = try std.fs.cwd().createFile(output_json_path, .{});
    defer output_file.close();
    try output_file.writeAll(json_buf.items);

    std.debug.print("Created Ligero config: {s}\n", .{output_json_path});
    if (has_public) {
        std.debug.print("  Public input: {d} bytes\n", .{public_len});
    }
    if (has_private) {
        std.debug.print("  Private input: {d} bytes\n", .{private_len});
    }
}

fn hexString(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    const hex = "0123456789abcdef";
    const out_len = 2 + data.len * 2;
    const out = try allocator.alloc(u8, out_len);
    out[0] = '0';
    out[1] = 'x';
    for (data, 0..) |byte, i| {
        out[2 + i * 2] = hex[byte >> 4];
        out[2 + i * 2 + 1] = hex[byte & 0x0f];
    }
    return out;
}
