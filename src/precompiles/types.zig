//! Precompile Types
//!
//! Common type definitions shared across backend-specific precompile implementations.
//! These types define the data structures used by cryptographic precompiles.

// =============================================================================
// Fundamental Types
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
// Parameter Structures
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
