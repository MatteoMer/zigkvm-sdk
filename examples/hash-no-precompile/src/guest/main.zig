//! Hash Example (No Precompiles) - Guest Program
//!
//! This example performs the same hash operations as the precompiles version
//! but uses Zig's standard library cryptographic implementations instead
//! of the ZisK hardware-accelerated precompiles.
//!
//! This allows for direct performance comparison between:
//! - Software-only hashing (this example)
//! - Hardware-accelerated precompiles (hash-precompiles example)
//!
//! This version performs 100 iterations of each hash to measure performance.

const std = @import("std");
const zigkvm = @import("zigkvm");

comptime {
    zigkvm.exportEntryPoint(main);
}

pub const panic = zigkvm.panic;

/// Number of hash iterations to perform
const ITERATIONS: usize = 100;

pub fn main() void {
    const input = zigkvm.readInputSlice();

    // ============================================================
    // Keccak-256 using std.crypto - 100 iterations
    // ============================================================
    //
    // Uses Zig's standard library Keccak-256 implementation.
    // Each iteration hashes the previous output, creating a chain.

    var keccak_hash: [32]u8 = undefined;

    // First hash: hash the input
    var keccak = std.crypto.hash.sha3.Keccak256.init(.{});
    keccak.update(input);
    keccak.final(&keccak_hash);

    // Chain 99 more iterations (100 total)
    for (1..ITERATIONS) |_| {
        var k = std.crypto.hash.sha3.Keccak256.init(.{});
        k.update(&keccak_hash);
        k.final(&keccak_hash);
    }

    // Output the 256-bit Keccak hash (4 x u64)
    zigkvm.setOutputU64(0, std.mem.readInt(u64, keccak_hash[0..8], .little));
    zigkvm.setOutputU64(2, std.mem.readInt(u64, keccak_hash[8..16], .little));
    zigkvm.setOutputU64(4, std.mem.readInt(u64, keccak_hash[16..24], .little));
    zigkvm.setOutputU64(6, std.mem.readInt(u64, keccak_hash[24..32], .little));

    // ============================================================
    // SHA-256 using std.crypto - 100 iterations
    // ============================================================
    //
    // Uses Zig's standard library SHA-256 implementation.
    // Each iteration hashes the previous output, creating a chain.

    var sha_hash: [32]u8 = undefined;

    // First hash: hash the input
    var sha = std.crypto.hash.sha2.Sha256.init(.{});
    sha.update(input);
    sha.final(&sha_hash);

    // Chain 99 more iterations (100 total)
    for (1..ITERATIONS) |_| {
        var s = std.crypto.hash.sha2.Sha256.init(.{});
        s.update(&sha_hash);
        s.final(&sha_hash);
    }

    // Output the 256-bit SHA-256 hash (4 x u64)
    zigkvm.setOutputU64(8, std.mem.readInt(u64, sha_hash[0..8], .little));
    zigkvm.setOutputU64(10, std.mem.readInt(u64, sha_hash[8..16], .little));
    zigkvm.setOutputU64(12, std.mem.readInt(u64, sha_hash[16..24], .little));
    zigkvm.setOutputU64(14, std.mem.readInt(u64, sha_hash[24..32], .little));

    // Output input length and iteration count for verification
    zigkvm.setOutput(16, @intCast(input.len));
    zigkvm.setOutput(17, ITERATIONS);
}
