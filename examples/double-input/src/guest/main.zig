const zigkvm = @import("zigkvm");

comptime {
    zigkvm.exportEntryPoint(main);
}

pub const panic = zigkvm.panic;

pub fn main() void {
    const input = zigkvm.readInput(u64);
    const result = input * 2;

    zigkvm.setOutputU64(0, result);
}
