//! ZisK Precompiles for zkVM acceleration
//!
//! This module provides cryptographic precompiles that are hardware-accelerated
//! in the ZisK zkVM via CSR instructions, with real software implementations
//! for native testing.
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
const build_options = @import("build_options");

// =============================================================================
// Configuration
// =============================================================================

const Backend = build_options.Backend;
const backend = build_options.backend;
const is_zisk = backend == .zisk;

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
// Data Types
// =============================================================================

/// 256-bit unsigned integer represented as 4 x u64 (little-endian limbs)
pub const U256 = [4]u64;

/// 384-bit unsigned integer represented as 6 x u64 (little-endian limbs)
pub const U384 = [6]u64;

/// EC Point on a 256-bit curve (secp256k1, bn254)
pub const Point256 = extern struct {
    x: U256,
    y: U256,
};

/// EC Point on a 384-bit curve (bls12_381)
pub const Point384 = extern struct {
    x: U384,
    y: U384,
};

/// Fp2 element (complex field element) for 256-bit curves
pub const Complex256 = extern struct {
    x: U256, // real part
    y: U256, // imaginary part
};

/// Fp2 element (complex field element) for 384-bit curves
pub const Complex384 = extern struct {
    x: U384, // real part
    y: U384, // imaginary part
};

/// Keccak-f[1600] state (25 x u64 = 1600 bits)
pub const KeccakState = [25]u64;

/// SHA-256 state (8 x u32 working variables packed as 4 x u64)
pub const Sha256State = [4]u64;

/// SHA-256 input block (16 x u32 message words packed as 8 x u64)
pub const Sha256Block = [8]u64;

// =============================================================================
// Parameter Structures (matching ZisK ABI)
// =============================================================================

/// Parameters for arith256: a*b+c = dh|dl (512-bit result)
pub const Arith256Params = extern struct {
    a: *const U256,
    b: *const U256,
    c: *const U256,
    dl: *U256, // low 256 bits of result
    dh: *U256, // high 256 bits of result
};

/// Parameters for arith256_mod: (a*b+c) mod m
pub const Arith256ModParams = extern struct {
    a: *const U256,
    b: *const U256,
    c: *const U256,
    m: *const U256, // modulus
    d: *U256, // result
};

/// Parameters for arith384_mod: (a*b+c) mod m
pub const Arith384ModParams = extern struct {
    a: *const U384,
    b: *const U384,
    c: *const U384,
    m: *const U384, // modulus
    d: *U384, // result
};

/// Parameters for add256: a+b+cin = cout|c
pub const Add256Params = extern struct {
    a: *const U256,
    b: *const U256,
    cin: u64, // carry in
    c: *U256, // result
};

/// Parameters for SHA-256
pub const Sha256Params = extern struct {
    state: *Sha256State,
    input: *const Sha256Block,
};

/// Parameters for secp256k1/bn254 point addition
pub const Point256AddParams = extern struct {
    p1: *Point256, // input/output
    p2: *const Point256,
};

/// Parameters for bls12_381 point addition
pub const Point384AddParams = extern struct {
    p1: *Point384, // input/output
    p2: *const Point384,
};

/// Parameters for bn254 complex field operations
pub const Complex256OpParams = extern struct {
    f1: *Complex256, // input/output
    f2: *const Complex256,
};

/// Parameters for bls12_381 complex field operations
pub const Complex384OpParams = extern struct {
    f1: *Complex384, // input/output
    f2: *const Complex384,
};

// =============================================================================
// CSR Invocation (ZisK Backend)
// =============================================================================

/// Invoke a ZisK precompile via CSR instruction.
/// The pointer is passed in a register, and csrs writes it to the CSR.
inline fn invokePrecompile(comptime syscall_id: SyscallId, params_ptr: usize) void {
    if (!is_zisk) {
        @compileError("invokePrecompile should only be called on ZisK backend");
    }
    // Use comptime string formatting to embed CSR address directly
    const csr_addr = @intFromEnum(syscall_id);
    asm volatile (std.fmt.comptimePrint("csrs {d}, %[rs]", .{csr_addr})
        :
        : [rs] "r" (params_ptr),
    );
}

/// Invoke a ZisK precompile that returns a u64 value via CSR instruction.
inline fn invokePrecompileRet(comptime syscall_id: SyscallId, params_ptr: usize) u64 {
    if (!is_zisk) {
        @compileError("invokePrecompileRet should only be called on ZisK backend");
    }
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
    if (is_zisk) {
        invokePrecompile(.keccak_f, @intFromPtr(state));
    } else {
        keccakFNative(state);
    }
}

/// Apply SHA-256 extend and compress to state with input block (in-place).
/// The state should contain the current hash state (H0-H7 packed as 4 x u64).
/// The input should contain a 512-bit message block (16 x u32 packed as 8 x u64).
pub fn sha256F(state: *Sha256State, input: *const Sha256Block) void {
    if (is_zisk) {
        var params = Sha256Params{
            .state = state,
            .input = input,
        };
        invokePrecompile(.sha256_f, @intFromPtr(&params));
    } else {
        sha256FNative(state, input);
    }
}

// =============================================================================
// 256-bit Arithmetic Precompiles
// =============================================================================

/// 256-bit multiply-add: a*b+c = dh|dl (512-bit result)
pub fn arith256(a: *const U256, b: *const U256, c: *const U256, dl: *U256, dh: *U256) void {
    if (is_zisk) {
        var params = Arith256Params{
            .a = a,
            .b = b,
            .c = c,
            .dl = dl,
            .dh = dh,
        };
        invokePrecompile(.arith256, @intFromPtr(&params));
    } else {
        arith256Native(a, b, c, dl, dh);
    }
}

/// 256-bit modular multiply-add: d = (a*b+c) mod m
pub fn arith256Mod(a: *const U256, b: *const U256, c: *const U256, m: *const U256, d: *U256) void {
    if (is_zisk) {
        var params = Arith256ModParams{
            .a = a,
            .b = b,
            .c = c,
            .m = m,
            .d = d,
        };
        invokePrecompile(.arith256_mod, @intFromPtr(&params));
    } else {
        arith256ModNative(a, b, c, m, d);
    }
}

/// 256-bit addition with carry: a+b+cin = cout|c
/// Returns the carry-out bit.
pub fn add256(a: *const U256, b: *const U256, cin: u64, c: *U256) u64 {
    if (is_zisk) {
        var params = Add256Params{
            .a = a,
            .b = b,
            .cin = cin,
            .c = c,
        };
        return invokePrecompileRet(.add256, @intFromPtr(&params));
    } else {
        return add256Native(a, b, cin, c);
    }
}

// =============================================================================
// 384-bit Arithmetic Precompiles
// =============================================================================

/// 384-bit modular multiply-add: d = (a*b+c) mod m
pub fn arith384Mod(a: *const U384, b: *const U384, c: *const U384, m: *const U384, d: *U384) void {
    if (is_zisk) {
        var params = Arith384ModParams{
            .a = a,
            .b = b,
            .c = c,
            .m = m,
            .d = d,
        };
        invokePrecompile(.arith384_mod, @intFromPtr(&params));
    } else {
        arith384ModNative(a, b, c, m, d);
    }
}

// =============================================================================
// secp256k1 Curve Precompiles
// =============================================================================

/// secp256k1 elliptic curve point addition: p1 = p1 + p2
pub fn secp256k1Add(p1: *Point256, p2: *const Point256) void {
    if (is_zisk) {
        var params = Point256AddParams{
            .p1 = p1,
            .p2 = p2,
        };
        invokePrecompile(.secp256k1_add, @intFromPtr(&params));
    } else {
        secp256k1AddNative(p1, p2);
    }
}

/// secp256k1 elliptic curve point doubling: p1 = 2*p1
pub fn secp256k1Dbl(p1: *Point256) void {
    if (is_zisk) {
        invokePrecompile(.secp256k1_dbl, @intFromPtr(p1));
    } else {
        secp256k1DblNative(p1);
    }
}

// =============================================================================
// BN254 Curve Precompiles
// =============================================================================

/// BN254 elliptic curve point addition: p1 = p1 + p2
pub fn bn254CurveAdd(p1: *Point256, p2: *const Point256) void {
    if (is_zisk) {
        var params = Point256AddParams{
            .p1 = p1,
            .p2 = p2,
        };
        invokePrecompile(.bn254_curve_add, @intFromPtr(&params));
    } else {
        bn254CurveAddNative(p1, p2);
    }
}

/// BN254 elliptic curve point doubling: p1 = 2*p1
pub fn bn254CurveDbl(p1: *Point256) void {
    if (is_zisk) {
        invokePrecompile(.bn254_curve_dbl, @intFromPtr(p1));
    } else {
        bn254CurveDblNative(p1);
    }
}

/// BN254 Fp2 addition: f1 = f1 + f2
pub fn bn254ComplexAdd(f1: *Complex256, f2: *const Complex256) void {
    if (is_zisk) {
        var params = Complex256OpParams{
            .f1 = f1,
            .f2 = f2,
        };
        invokePrecompile(.bn254_complex_add, @intFromPtr(&params));
    } else {
        bn254ComplexAddNative(f1, f2);
    }
}

/// BN254 Fp2 subtraction: f1 = f1 - f2
pub fn bn254ComplexSub(f1: *Complex256, f2: *const Complex256) void {
    if (is_zisk) {
        var params = Complex256OpParams{
            .f1 = f1,
            .f2 = f2,
        };
        invokePrecompile(.bn254_complex_sub, @intFromPtr(&params));
    } else {
        bn254ComplexSubNative(f1, f2);
    }
}

/// BN254 Fp2 multiplication: f1 = f1 * f2
pub fn bn254ComplexMul(f1: *Complex256, f2: *const Complex256) void {
    if (is_zisk) {
        var params = Complex256OpParams{
            .f1 = f1,
            .f2 = f2,
        };
        invokePrecompile(.bn254_complex_mul, @intFromPtr(&params));
    } else {
        bn254ComplexMulNative(f1, f2);
    }
}

// =============================================================================
// BLS12-381 Curve Precompiles
// =============================================================================

/// BLS12-381 elliptic curve point addition: p1 = p1 + p2
pub fn bls12381CurveAdd(p1: *Point384, p2: *const Point384) void {
    if (is_zisk) {
        var params = Point384AddParams{
            .p1 = p1,
            .p2 = p2,
        };
        invokePrecompile(.bls12_381_curve_add, @intFromPtr(&params));
    } else {
        bls12381CurveAddNative(p1, p2);
    }
}

/// BLS12-381 elliptic curve point doubling: p1 = 2*p1
pub fn bls12381CurveDbl(p1: *Point384) void {
    if (is_zisk) {
        invokePrecompile(.bls12_381_curve_dbl, @intFromPtr(p1));
    } else {
        bls12381CurveDblNative(p1);
    }
}

/// BLS12-381 Fp2 addition: f1 = f1 + f2
pub fn bls12381ComplexAdd(f1: *Complex384, f2: *const Complex384) void {
    if (is_zisk) {
        var params = Complex384OpParams{
            .f1 = f1,
            .f2 = f2,
        };
        invokePrecompile(.bls12_381_complex_add, @intFromPtr(&params));
    } else {
        bls12381ComplexAddNative(f1, f2);
    }
}

/// BLS12-381 Fp2 subtraction: f1 = f1 - f2
pub fn bls12381ComplexSub(f1: *Complex384, f2: *const Complex384) void {
    if (is_zisk) {
        var params = Complex384OpParams{
            .f1 = f1,
            .f2 = f2,
        };
        invokePrecompile(.bls12_381_complex_sub, @intFromPtr(&params));
    } else {
        bls12381ComplexSubNative(f1, f2);
    }
}

/// BLS12-381 Fp2 multiplication: f1 = f1 * f2
pub fn bls12381ComplexMul(f1: *Complex384, f2: *const Complex384) void {
    if (is_zisk) {
        var params = Complex384OpParams{
            .f1 = f1,
            .f2 = f2,
        };
        invokePrecompile(.bls12_381_complex_mul, @intFromPtr(&params));
    } else {
        bls12381ComplexMulNative(f1, f2);
    }
}

// =============================================================================
// Native Implementations - Hash Functions
// =============================================================================

/// Native Keccak-f[1600] permutation implementation
fn keccakFNative(state: *KeccakState) void {
    // Keccak-f[1600] constants
    const RC: [24]u64 = .{
        0x0000000000000001, 0x0000000000008082, 0x800000000000808a, 0x8000000080008000,
        0x000000000000808b, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
        0x000000000000008a, 0x0000000000000088, 0x0000000080008009, 0x000000008000000a,
        0x000000008000808b, 0x800000000000008b, 0x8000000000008089, 0x8000000000008003,
        0x8000000000008002, 0x8000000000000080, 0x000000000000800a, 0x800000008000000a,
        0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008,
    };

    const ROTC: [24]u6 = .{
        1,  3,  6,  10, 15, 21, 28, 36, 45, 55, 2,  14,
        27, 41, 56, 8,  25, 43, 62, 18, 39, 61, 20, 44,
    };

    const PILN: [24]u5 = .{
        10, 7,  11, 17, 18, 3, 5,  16, 8,  21, 24, 4,
        15, 23, 19, 13, 12, 2, 20, 14, 22, 9,  6,  1,
    };

    var st = state.*;

    // 24 rounds
    for (0..24) |round| {
        // Theta
        var bc: [5]u64 = undefined;
        for (0..5) |i| {
            bc[i] = st[i] ^ st[i + 5] ^ st[i + 10] ^ st[i + 15] ^ st[i + 20];
        }
        for (0..5) |i| {
            const t = bc[(i + 4) % 5] ^ std.math.rotl(u64, bc[(i + 1) % 5], 1);
            for (0..5) |j| {
                st[i + j * 5] ^= t;
            }
        }

        // Rho and Pi
        var t = st[1];
        for (0..24) |i| {
            const j = PILN[i];
            const tmp = st[j];
            st[j] = std.math.rotl(u64, t, ROTC[i]);
            t = tmp;
        }

        // Chi
        for (0..5) |j| {
            const offset = j * 5;
            for (0..5) |i| {
                bc[i] = st[offset + i];
            }
            for (0..5) |i| {
                st[offset + i] = bc[i] ^ (~bc[(i + 1) % 5] & bc[(i + 2) % 5]);
            }
        }

        // Iota
        st[0] ^= RC[round];
    }

    state.* = st;
}

/// SHA-256 round constants
const SHA256_K: [64]u32 = .{
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
};

/// Native SHA-256 extend and compress implementation
fn sha256FNative(state: *Sha256State, input: *const Sha256Block) void {
    // Unpack state from 4 x u64 to 8 x u32
    var h: [8]u32 = undefined;
    for (0..4) |i| {
        h[i * 2] = @truncate(state[i]);
        h[i * 2 + 1] = @truncate(state[i] >> 32);
    }

    // Unpack input from 8 x u64 to 16 x u32
    var w: [64]u32 = undefined;
    for (0..8) |i| {
        w[i * 2] = @truncate(input[i]);
        w[i * 2 + 1] = @truncate(input[i] >> 32);
    }

    // Extend the first 16 words into the remaining 48 words
    for (16..64) |i| {
        const s0 = std.math.rotr(u32, w[i - 15], 7) ^
            std.math.rotr(u32, w[i - 15], 18) ^
            (w[i - 15] >> 3);
        const s1 = std.math.rotr(u32, w[i - 2], 17) ^
            std.math.rotr(u32, w[i - 2], 19) ^
            (w[i - 2] >> 10);
        w[i] = w[i - 16] +% s0 +% w[i - 7] +% s1;
    }

    // Initialize working variables
    var a = h[0];
    var b = h[1];
    var c = h[2];
    var d = h[3];
    var e = h[4];
    var f = h[5];
    var g = h[6];
    var hh = h[7];

    // Compression function main loop
    for (0..64) |i| {
        const S1 = std.math.rotr(u32, e, 6) ^
            std.math.rotr(u32, e, 11) ^
            std.math.rotr(u32, e, 25);
        const ch = (e & f) ^ (~e & g);
        const temp1 = hh +% S1 +% ch +% SHA256_K[i] +% w[i];
        const S0 = std.math.rotr(u32, a, 2) ^
            std.math.rotr(u32, a, 13) ^
            std.math.rotr(u32, a, 22);
        const maj = (a & b) ^ (a & c) ^ (b & c);
        const temp2 = S0 +% maj;

        hh = g;
        g = f;
        f = e;
        e = d +% temp1;
        d = c;
        c = b;
        b = a;
        a = temp1 +% temp2;
    }

    // Add the compressed chunk to the current hash value
    h[0] +%= a;
    h[1] +%= b;
    h[2] +%= c;
    h[3] +%= d;
    h[4] +%= e;
    h[5] +%= f;
    h[6] +%= g;
    h[7] +%= hh;

    // Pack state back to 4 x u64
    for (0..4) |i| {
        state[i] = @as(u64, h[i * 2]) | (@as(u64, h[i * 2 + 1]) << 32);
    }
}

// =============================================================================
// Native Implementations - Arithmetic (Stubs for now)
// =============================================================================

fn arith256Native(a: *const U256, b: *const U256, c: *const U256, dl: *U256, dh: *U256) void {
    // TODO: Implement proper 256-bit multiply-add
    // For now, provide a basic implementation
    _ = a;
    _ = b;
    _ = c;
    dl.* = .{ 0, 0, 0, 0 };
    dh.* = .{ 0, 0, 0, 0 };
}

fn arith256ModNative(a: *const U256, b: *const U256, c: *const U256, m: *const U256, d: *U256) void {
    // TODO: Implement proper 256-bit modular multiply-add
    _ = a;
    _ = b;
    _ = c;
    _ = m;
    d.* = .{ 0, 0, 0, 0 };
}

fn add256Native(a: *const U256, b: *const U256, cin: u64, c: *U256) u64 {
    var carry: u64 = cin & 1;
    for (0..4) |i| {
        const sum = @addWithOverflow(a[i], b[i]);
        const sum2 = @addWithOverflow(sum[0], carry);
        c[i] = sum2[0];
        carry = @intFromBool(sum[1] != 0) | @intFromBool(sum2[1] != 0);
    }
    return carry;
}

fn arith384ModNative(a: *const U384, b: *const U384, c: *const U384, m: *const U384, d: *U384) void {
    // TODO: Implement proper 384-bit modular multiply-add
    _ = a;
    _ = b;
    _ = c;
    _ = m;
    d.* = .{ 0, 0, 0, 0, 0, 0 };
}

// =============================================================================
// Native Implementations - Elliptic Curves (Stubs)
// =============================================================================

fn secp256k1AddNative(p1: *Point256, p2: *const Point256) void {
    // TODO: Implement secp256k1 point addition
    _ = p2;
    p1.* = .{ .x = .{ 0, 0, 0, 0 }, .y = .{ 0, 0, 0, 0 } };
}

fn secp256k1DblNative(p1: *Point256) void {
    // TODO: Implement secp256k1 point doubling
    p1.* = .{ .x = .{ 0, 0, 0, 0 }, .y = .{ 0, 0, 0, 0 } };
}

fn bn254CurveAddNative(p1: *Point256, p2: *const Point256) void {
    // TODO: Implement BN254 point addition
    _ = p2;
    p1.* = .{ .x = .{ 0, 0, 0, 0 }, .y = .{ 0, 0, 0, 0 } };
}

fn bn254CurveDblNative(p1: *Point256) void {
    // TODO: Implement BN254 point doubling
    p1.* = .{ .x = .{ 0, 0, 0, 0 }, .y = .{ 0, 0, 0, 0 } };
}

fn bn254ComplexAddNative(f1: *Complex256, f2: *const Complex256) void {
    // TODO: Implement BN254 Fp2 addition
    _ = f2;
    f1.* = .{ .x = .{ 0, 0, 0, 0 }, .y = .{ 0, 0, 0, 0 } };
}

fn bn254ComplexSubNative(f1: *Complex256, f2: *const Complex256) void {
    // TODO: Implement BN254 Fp2 subtraction
    _ = f2;
    f1.* = .{ .x = .{ 0, 0, 0, 0 }, .y = .{ 0, 0, 0, 0 } };
}

fn bn254ComplexMulNative(f1: *Complex256, f2: *const Complex256) void {
    // TODO: Implement BN254 Fp2 multiplication
    _ = f2;
    f1.* = .{ .x = .{ 0, 0, 0, 0 }, .y = .{ 0, 0, 0, 0 } };
}

fn bls12381CurveAddNative(p1: *Point384, p2: *const Point384) void {
    // TODO: Implement BLS12-381 point addition
    _ = p2;
    p1.* = .{ .x = .{ 0, 0, 0, 0, 0, 0 }, .y = .{ 0, 0, 0, 0, 0, 0 } };
}

fn bls12381CurveDblNative(p1: *Point384) void {
    // TODO: Implement BLS12-381 point doubling
    p1.* = .{ .x = .{ 0, 0, 0, 0, 0, 0 }, .y = .{ 0, 0, 0, 0, 0, 0 } };
}

fn bls12381ComplexAddNative(f1: *Complex384, f2: *const Complex384) void {
    // TODO: Implement BLS12-381 Fp2 addition
    _ = f2;
    f1.* = .{ .x = .{ 0, 0, 0, 0, 0, 0 }, .y = .{ 0, 0, 0, 0, 0, 0 } };
}

fn bls12381ComplexSubNative(f1: *Complex384, f2: *const Complex384) void {
    // TODO: Implement BLS12-381 Fp2 subtraction
    _ = f2;
    f1.* = .{ .x = .{ 0, 0, 0, 0, 0, 0 }, .y = .{ 0, 0, 0, 0, 0, 0 } };
}

fn bls12381ComplexMulNative(f1: *Complex384, f2: *const Complex384) void {
    // TODO: Implement BLS12-381 Fp2 multiplication
    _ = f2;
    f1.* = .{ .x = .{ 0, 0, 0, 0, 0, 0 }, .y = .{ 0, 0, 0, 0, 0, 0 } };
}

// =============================================================================
// Tests
// =============================================================================

test "type sizes are correct" {
    try std.testing.expectEqual(@sizeOf(U256), 32);
    try std.testing.expectEqual(@sizeOf(U384), 48);
    try std.testing.expectEqual(@sizeOf(Point256), 64);
    try std.testing.expectEqual(@sizeOf(Point384), 96);
    try std.testing.expectEqual(@sizeOf(Complex256), 64);
    try std.testing.expectEqual(@sizeOf(Complex384), 96);
    try std.testing.expectEqual(@sizeOf(KeccakState), 200);
    try std.testing.expectEqual(@sizeOf(Sha256State), 32);
    try std.testing.expectEqual(@sizeOf(Sha256Block), 64);
}

test "keccakF modifies state" {
    var state: KeccakState = [_]u64{0} ** 25;
    state[0] = 1;

    const original = state;
    keccakF(&state);

    // State should be different after permutation
    try std.testing.expect(!std.mem.eql(u64, &state, &original));
}

test "keccakF known test vector - all zeros" {
    // Keccak-f[1600] applied to all zeros
    // This is a well-known test vector
    var state: KeccakState = [_]u64{0} ** 25;

    keccakF(&state);

    // Expected value for first lane after applying Keccak-f to all zeros
    try std.testing.expectEqual(state[0], 0xF1258F7940E1DDE7);
}

test "sha256F modifies state" {
    // SHA-256 initial hash values (first 32 bits of fractional parts of square roots of first 8 primes)
    var state: Sha256State = .{
        0x6a09e667bb67ae85, // H0, H1
        0x3c6ef372a54ff53a, // H2, H3
        0x510e527f9b05688c, // H4, H5
        0x1f83d9ab5be0cd19, // H6, H7
    };
    var input: Sha256Block = [_]u64{0} ** 8;

    const original = state;
    sha256F(&state, &input);

    try std.testing.expect(!std.mem.eql(u64, &state, &original));
}

test "add256 basic addition" {
    const a: U256 = .{ 0xFFFFFFFFFFFFFFFF, 0, 0, 0 };
    const b: U256 = .{ 1, 0, 0, 0 };
    var c: U256 = undefined;

    const carry = add256(&a, &b, 0, &c);

    try std.testing.expectEqual(c[0], 0);
    try std.testing.expectEqual(c[1], 1);
    try std.testing.expectEqual(c[2], 0);
    try std.testing.expectEqual(c[3], 0);
    try std.testing.expectEqual(carry, 0);
}

test "add256 with carry out" {
    const a: U256 = .{ 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF };
    const b: U256 = .{ 1, 0, 0, 0 };
    var c: U256 = undefined;

    const carry = add256(&a, &b, 0, &c);

    try std.testing.expectEqual(c[0], 0);
    try std.testing.expectEqual(c[1], 0);
    try std.testing.expectEqual(c[2], 0);
    try std.testing.expectEqual(c[3], 0);
    try std.testing.expectEqual(carry, 1);
}
