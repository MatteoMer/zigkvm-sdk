const zkvm = @import("zkvm");

comptime {
    zkvm.exportEntryPoint(main);
}

pub const panic = zkvm.panic;

pub fn main() void {
    const input = zkvm.readInput(u64);
    const result = input * 2;

    zkvm.setOutputU64(0, result);
}
