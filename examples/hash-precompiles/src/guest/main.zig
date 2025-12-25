//! Hash Precompiles Example - Guest Program
//!
//! This example demonstrates the use of ZisK hash precompiles:
//! - keccakF: Keccak-f[1600] permutation
//! - sha256F: SHA-256 extend and compress
//!
//! These precompiles are hardware-accelerated in the ZisK zkVM,
//! making cryptographic hash operations much more efficient.
//!
//! This version performs 100 iterations of each hash to measure performance.

const std = @import("std");
const zigkvm = @import("zigkvm");
const precompiles = zigkvm.precompiles;

comptime {
    zigkvm.exportEntryPoint(main);
}

pub const panic = zigkvm.panic;

/// Number of hash iterations to perform
const ITERATIONS: usize = 100;

pub fn main() void {
    const input = zigkvm.readInputSlice();

    // ============================================================
    // Keccak-f[1600] Precompile Demo - 100 iterations
    // ============================================================
    //
    // The Keccak-f[1600] permutation is the core of SHA-3 and Keccak hashes.
    // It operates on a 1600-bit state (25 x 64-bit words).
    //
    // We perform 100 iterations, using the output of each round as
    // input to the next round to create a hash chain.

    var keccak_state: precompiles.KeccakState = [_]u64{0} ** 25;

    // Absorb input into state (simplified - absorbs up to rate portion)
    // The rate for Keccak-256 is 1088 bits = 136 bytes = 17 words
    const rate_words = 17;
    const input_words = @min(input.len / 8, rate_words);

    for (0..input_words) |i| {
        const offset = i * 8;
        if (offset + 8 <= input.len) {
            keccak_state[i] = std.mem.readInt(u64, input[offset..][0..8], .little);
        }
    }

    // Apply Keccak-f[1600] permutation 100 times
    for (0..ITERATIONS) |_| {
        precompiles.keccakF(&keccak_state);
    }

    // Output first 256 bits (4 x u64) of the final Keccak state
    zigkvm.setOutputU64(0, keccak_state[0]);
    zigkvm.setOutputU64(2, keccak_state[1]);
    zigkvm.setOutputU64(4, keccak_state[2]);
    zigkvm.setOutputU64(6, keccak_state[3]);

    // ============================================================
    // SHA-256 Precompile Demo - 100 iterations
    // ============================================================
    //
    // The SHA-256 precompile performs the extend and compress operations
    // on a single 512-bit (64-byte) message block.
    //
    // We perform 100 iterations, using the previous hash output
    // as part of the next input block.

    // SHA-256 initial hash values (H0-H7)
    var sha_state: precompiles.Sha256State = .{
        0x6a09e667bb67ae85, // H0 | H1
        0x3c6ef372a54ff53a, // H2 | H3
        0x510e527f9b05688c, // H4 | H5
        0x1f83d9ab5be0cd19, // H6 | H7
    };

    // Prepare a 512-bit (64 byte) message block
    var sha_block: precompiles.Sha256Block = [_]u64{0} ** 8;

    // Copy input into the block (up to 64 bytes)
    const block_words = @min(input.len / 8, 8);
    for (0..block_words) |i| {
        const offset = i * 8;
        if (offset + 8 <= input.len) {
            sha_block[i] = std.mem.readInt(u64, input[offset..][0..8], .little);
        }
    }

    // Apply SHA-256 extend and compress 100 times
    // Each iteration uses the current state, creating a hash chain
    for (0..ITERATIONS) |_| {
        precompiles.sha256F(&sha_state, &sha_block);
        // Use the state as part of the next block for chaining
        sha_block[0] = sha_state[0];
        sha_block[1] = sha_state[1];
        sha_block[2] = sha_state[2];
        sha_block[3] = sha_state[3];
    }

    // Output the final SHA-256 state
    zigkvm.setOutputU64(8, sha_state[0]);
    zigkvm.setOutputU64(10, sha_state[1]);
    zigkvm.setOutputU64(12, sha_state[2]);
    zigkvm.setOutputU64(14, sha_state[3]);

    // Output input length and iteration count for verification
    zigkvm.setOutput(16, @intCast(input.len));
    zigkvm.setOutput(17, ITERATIONS);
}
