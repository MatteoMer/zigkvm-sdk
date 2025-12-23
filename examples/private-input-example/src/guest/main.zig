const zigkvm = @import("zigkvm");

comptime {
    zigkvm.exportEntryPoint(main);
}

pub const panic = zigkvm.panic;

pub fn main() void {
    comptime {
        if (!@hasDecl(zigkvm, "readPrivateInput")) {
            @compileError("This example requires the Ligero backend (-Dbackend=ligero).");
        }
    }

    const expected = zigkvm.readPublicInput(u64);
    const secret = zigkvm.readPrivateInput(u64);

    const computed = secret * 3 + 7;
    if (computed != expected) {
        zigkvm.exitError();
    }

    zigkvm.setOutputU64(0, computed);
}
