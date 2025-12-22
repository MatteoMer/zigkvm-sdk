const std = @import("std");
const zigkvm = @import("zigkvm");

comptime {
    zigkvm.exportEntryPoint(main);
}

pub const panic = zigkvm.panic;

pub fn main() void {
    const input = zigkvm.readInputSlice();
    const allocator = zigkvm.allocator();

    const copy = allocator.alloc(u8, input.len) catch @panic("allocation failed");
    defer allocator.free(copy);
    std.mem.copyForwards(u8, copy, input);

    var sum: u64 = 0;
    for (copy) |byte| {
        sum += byte;
    }

    zigkvm.setOutputU64(0, sum);
    zigkvm.setOutput(2, @intCast(copy.len));
}
