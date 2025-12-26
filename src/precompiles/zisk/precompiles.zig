//! ZisK Precompiles
//!
//! Hardware-accelerated cryptographic precompiles for the ZisK zkVM.
//! These precompiles are invoked via RISC-V CSR instructions.
//!
//! ## Supported Precompiles
//!
//! | ID    | Name                    | Description                              |
//! |-------|-------------------------|------------------------------------------|
//! | 0x800 | keccak_f                | Keccak-f[1600] permutation               |
//! | 0x801 | arith256                | 256-bit multiply-add (a*b+c)             |
//! | 0x802 | arith256_mod            | 256-bit modular multiply-add             |
//! | 0x803 | secp256k1_add           | secp256k1 EC point addition              |
//! | 0x804 | secp256k1_dbl           | secp256k1 EC point doubling              |
//! | 0x805 | sha256_f                | SHA-256 extend and compress              |
//! | 0x806 | bn254_curve_add         | BN254 EC point addition                  |
//! | 0x807 | bn254_curve_dbl         | BN254 EC point doubling                  |
//! | 0x808 | bn254_complex_add       | BN254 Fp2 addition                       |
//! | 0x809 | bn254_complex_sub       | BN254 Fp2 subtraction                    |
//! | 0x80A | bn254_complex_mul       | BN254 Fp2 multiplication                 |
//! | 0x80B | arith384_mod            | 384-bit modular multiply-add             |
//! | 0x80C | bls12_381_curve_add     | BLS12-381 EC point addition              |
//! | 0x80D | bls12_381_curve_dbl     | BLS12-381 EC point doubling              |
//! | 0x80E | bls12_381_complex_add   | BLS12-381 Fp2 addition                   |
//! | 0x80F | bls12_381_complex_sub   | BLS12-381 Fp2 subtraction                |
//! | 0x810 | bls12_381_complex_mul   | BLS12-381 Fp2 multiplication             |
//! | 0x811 | add256                  | 256-bit addition with carry              |

const std = @import("std");
const types = @import("../types.zig");

// Re-export types for convenience
pub const U256 = types.U256;
pub const U384 = types.U384;
pub const Point256 = types.Point256;
pub const Point384 = types.Point384;
pub const Complex256 = types.Complex256;
pub const Complex384 = types.Complex384;
pub const KeccakState = types.KeccakState;
pub const Sha256State = types.Sha256State;
pub const Sha256Block = types.Sha256Block;
pub const Arith256Params = types.Arith256Params;
pub const Arith256ModParams = types.Arith256ModParams;
pub const Arith384ModParams = types.Arith384ModParams;
pub const Add256Params = types.Add256Params;
pub const Sha256Params = types.Sha256Params;
pub const Point256AddParams = types.Point256AddParams;
pub const Point384AddParams = types.Point384AddParams;
pub const Complex256OpParams = types.Complex256OpParams;
pub const Complex384OpParams = types.Complex384OpParams;

// =============================================================================
// Syscall IDs (CSR addresses)
// =============================================================================

/// ZisK precompile syscall IDs (CSR addresses 0x800-0x811)
pub const SyscallId = enum(u12) {
    keccak_f = 0x800,
    arith256 = 0x801,
    arith256_mod = 0x802,
    secp256k1_add = 0x803,
    secp256k1_dbl = 0x804,
    sha256_f = 0x805,
    bn254_curve_add = 0x806,
    bn254_curve_dbl = 0x807,
    bn254_complex_add = 0x808,
    bn254_complex_sub = 0x809,
    bn254_complex_mul = 0x80A,
    arith384_mod = 0x80B,
    bls12_381_curve_add = 0x80C,
    bls12_381_curve_dbl = 0x80D,
    bls12_381_complex_add = 0x80E,
    bls12_381_complex_sub = 0x80F,
    bls12_381_complex_mul = 0x810,
    add256 = 0x811,
};

// =============================================================================
// CSR Invocation
// =============================================================================

/// Invoke a ZisK precompile via CSR instruction.
/// The pointer is passed in a register, and csrs writes it to the CSR.
inline fn invokePrecompile(comptime syscall_id: SyscallId, params_ptr: usize) void {
    const csr_addr = @intFromEnum(syscall_id);
    asm volatile (std.fmt.comptimePrint("csrs {d}, %[rs]", .{csr_addr})
        :
        : [rs] "r" (params_ptr),
    );
}

/// Invoke a ZisK precompile that returns a u64 value via CSR instruction.
inline fn invokePrecompileRet(comptime syscall_id: SyscallId, params_ptr: usize) u64 {
    const csr_addr = @intFromEnum(syscall_id);
    return asm volatile (std.fmt.comptimePrint("csrrs %[ret], {d}, %[rs]", .{csr_addr})
        : [ret] "=r" (-> u64)
        : [rs] "r" (params_ptr),
    );
}

// =============================================================================
// Hash Precompiles
// =============================================================================

/// Apply Keccak-f[1600] permutation to state (in-place).
/// This is the core permutation used in SHA-3 and Keccak hashes.
pub fn keccakF(state: *KeccakState) void {
    invokePrecompile(.keccak_f, @intFromPtr(state));
}

/// Apply SHA-256 extend and compress to state with input block (in-place).
/// The state should contain the current hash state (H0-H7 packed as 4 x u64).
/// The input should contain a 512-bit message block (16 x u32 packed as 8 x u64).
pub fn sha256F(state: *Sha256State, input: *const Sha256Block) void {
    var params = Sha256Params{
        .state = state,
        .input = input,
    };
    invokePrecompile(.sha256_f, @intFromPtr(&params));
}

// =============================================================================
// 256-bit Arithmetic Precompiles
// =============================================================================

/// 256-bit multiply-add: a*b+c = dh|dl (512-bit result)
pub fn arith256(a: *const U256, b: *const U256, c: *const U256, dl: *U256, dh: *U256) void {
    var params = Arith256Params{
        .a = a,
        .b = b,
        .c = c,
        .dl = dl,
        .dh = dh,
    };
    invokePrecompile(.arith256, @intFromPtr(&params));
}

/// 256-bit modular multiply-add: d = (a*b+c) mod m
pub fn arith256Mod(a: *const U256, b: *const U256, c: *const U256, m: *const U256, d: *U256) void {
    var params = Arith256ModParams{
        .a = a,
        .b = b,
        .c = c,
        .m = m,
        .d = d,
    };
    invokePrecompile(.arith256_mod, @intFromPtr(&params));
}

/// 256-bit addition with carry: a+b+cin = cout|c
/// Returns the carry-out bit.
pub fn add256(a: *const U256, b: *const U256, cin: u64, c: *U256) u64 {
    var params = Add256Params{
        .a = a,
        .b = b,
        .cin = cin,
        .c = c,
    };
    return invokePrecompileRet(.add256, @intFromPtr(&params));
}

// =============================================================================
// 384-bit Arithmetic Precompiles
// =============================================================================

/// 384-bit modular multiply-add: d = (a*b+c) mod m
pub fn arith384Mod(a: *const U384, b: *const U384, c: *const U384, m: *const U384, d: *U384) void {
    var params = Arith384ModParams{
        .a = a,
        .b = b,
        .c = c,
        .m = m,
        .d = d,
    };
    invokePrecompile(.arith384_mod, @intFromPtr(&params));
}

// =============================================================================
// secp256k1 Curve Precompiles
// =============================================================================

/// secp256k1 elliptic curve point addition: p1 = p1 + p2
pub fn secp256k1Add(p1: *Point256, p2: *const Point256) void {
    var params = Point256AddParams{
        .p1 = p1,
        .p2 = p2,
    };
    invokePrecompile(.secp256k1_add, @intFromPtr(&params));
}

/// secp256k1 elliptic curve point doubling: p1 = 2*p1
pub fn secp256k1Dbl(p1: *Point256) void {
    invokePrecompile(.secp256k1_dbl, @intFromPtr(p1));
}

// =============================================================================
// BN254 Curve Precompiles
// =============================================================================

/// BN254 elliptic curve point addition: p1 = p1 + p2
pub fn bn254CurveAdd(p1: *Point256, p2: *const Point256) void {
    var params = Point256AddParams{
        .p1 = p1,
        .p2 = p2,
    };
    invokePrecompile(.bn254_curve_add, @intFromPtr(&params));
}

/// BN254 elliptic curve point doubling: p1 = 2*p1
pub fn bn254CurveDbl(p1: *Point256) void {
    invokePrecompile(.bn254_curve_dbl, @intFromPtr(p1));
}

/// BN254 Fp2 addition: f1 = f1 + f2
pub fn bn254ComplexAdd(f1: *Complex256, f2: *const Complex256) void {
    var params = Complex256OpParams{
        .f1 = f1,
        .f2 = f2,
    };
    invokePrecompile(.bn254_complex_add, @intFromPtr(&params));
}

/// BN254 Fp2 subtraction: f1 = f1 - f2
pub fn bn254ComplexSub(f1: *Complex256, f2: *const Complex256) void {
    var params = Complex256OpParams{
        .f1 = f1,
        .f2 = f2,
    };
    invokePrecompile(.bn254_complex_sub, @intFromPtr(&params));
}

/// BN254 Fp2 multiplication: f1 = f1 * f2
pub fn bn254ComplexMul(f1: *Complex256, f2: *const Complex256) void {
    var params = Complex256OpParams{
        .f1 = f1,
        .f2 = f2,
    };
    invokePrecompile(.bn254_complex_mul, @intFromPtr(&params));
}

// =============================================================================
// BLS12-381 Curve Precompiles
// =============================================================================

/// BLS12-381 elliptic curve point addition: p1 = p1 + p2
pub fn bls12381CurveAdd(p1: *Point384, p2: *const Point384) void {
    var params = Point384AddParams{
        .p1 = p1,
        .p2 = p2,
    };
    invokePrecompile(.bls12_381_curve_add, @intFromPtr(&params));
}

/// BLS12-381 elliptic curve point doubling: p1 = 2*p1
pub fn bls12381CurveDbl(p1: *Point384) void {
    invokePrecompile(.bls12_381_curve_dbl, @intFromPtr(p1));
}

/// BLS12-381 Fp2 addition: f1 = f1 + f2
pub fn bls12381ComplexAdd(f1: *Complex384, f2: *const Complex384) void {
    var params = Complex384OpParams{
        .f1 = f1,
        .f2 = f2,
    };
    invokePrecompile(.bls12_381_complex_add, @intFromPtr(&params));
}

/// BLS12-381 Fp2 subtraction: f1 = f1 - f2
pub fn bls12381ComplexSub(f1: *Complex384, f2: *const Complex384) void {
    var params = Complex384OpParams{
        .f1 = f1,
        .f2 = f2,
    };
    invokePrecompile(.bls12_381_complex_sub, @intFromPtr(&params));
}

/// BLS12-381 Fp2 multiplication: f1 = f1 * f2
pub fn bls12381ComplexMul(f1: *Complex384, f2: *const Complex384) void {
    var params = Complex384OpParams{
        .f1 = f1,
        .f2 = f2,
    };
    invokePrecompile(.bls12_381_complex_mul, @intFromPtr(&params));
}
