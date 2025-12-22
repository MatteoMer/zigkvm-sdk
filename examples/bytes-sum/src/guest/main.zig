const std = @import("std");
const zkvm = @import("zkvm");

comptime {
    zkvm.exportEntryPoint(main);
}

pub const panic = zkvm.panic;

pub fn main() void {
    const input = zkvm.readInputSlice();
    const allocator = zkvm.allocator();

    const copy = allocator.alloc(u8, input.len) catch @panic("allocation failed");
    defer allocator.free(copy);
    std.mem.copyForwards(u8, copy, input);

    var sum: u64 = 0;
    for (copy) |byte| {
        sum += byte;
    }

    zkvm.setOutputU64(0, sum);
    zkvm.setOutput(2, @intCast(copy.len));
}
