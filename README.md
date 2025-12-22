# zigkvm-sdk

> Build zero-knowledge applications in Zig

**zigkvm-sdk** is a lightweight, ergonomic SDK for writing zkVM programs in Zig. Write once, test locally, and generate ZK proofs without changing your code.

**New to ZK?** Read [Understanding Zero-Knowledge Proofs](#understanding-zero-knowledge-and-validity-proofs) first, or jump straight to the [Quick Start](#quick-start).

## What's a Zero-Knowledge proof?
Zero-knowledge proofs (ZKPs) let you prove that a computation was executed correctly without revealing the underlying inputs or execution details. In a zkVM, this means you can prove that a program ran and produced a specific output, while optionally keeping its data private.

In practice, there are two related proof types:

- **Validity proofs** prove correct execution with a small, fast-to-verify proof, but may reveal inputs or execution details.

- **Zero-knowledge proofs** additionally guarantee privacy, hiding inputs and intermediate state.

Most zkVMs today (including the default [ZisK](https://github.com/0xPolygonHermez/zisk) backend) produce validity proofs, not full zero-knowledge proofs.

I will soon add support for the [Ligero](https://github.com/ligeroinc/ligero-prover) backend, enabling true zero-knowledge guarantees and privacy-preserving applications.

## Quick Start

### Host vs Guest Architecture

This SDK uses a **host/guest** split common in zkVM development:

- **Guest programs** run inside the zkVM in a sandboxed RISC-V environment. They execute your computation logic, and the zkVM produces a cryptographic proof that the execution was correct. Guests are restricted (no file I/O, no network, minimal syscalls) to keep execution deterministic and provable.

- **Host programs** run normally on your machine with full system access. They prepare inputs for the guest, invoke the zkVM to generate proofs, and read the guest's outputs. The host handles everything the guest cannot: file operations, network requests, user interaction, etc.

**Typical workflow:** Host prepares inputs → Guest executes computation inside zkVM → zkVM generates proof → Anyone can verify the proof to trust the output → Computation is verified without re-execution.

### Requirements

- Zig 0.13.0 or later
- For ZK proofs: [cargo-zisk](https://github.com/0xPolygonHermez/zisk) toolchain (more backends on the way!)

### Guest Program

Write your zkVM program using the guest API:

```zig
const zigkvm = @import("zigkvm");

comptime {
    zigkvm.exportEntryPoint(main);
}

pub const panic = zigkvm.panic;

pub fn main() void {
    const input = zigkvm.readInput(u64);
    zigkvm.setOutputU64(0, input * 2);
}
```

### Host Program

Prepare inputs and read outputs from the host:

```zig
const host = @import("zigkvm_host");

pub fn main() !void {
    var input = host.Input.init(allocator);
    defer input.deinit();

    try input.write(@as(u64, 42));
    try input.toFile("input.bin");
}
```

### Build & Prove

```bash
# Test locally (fast)
zig build -Dbackend=native test

# Build for zkVM
zig build -Dbackend=zisk

# Generate proof
zig build -Dbackend=zisk prove

# Verify proof
zig build -Dbackend=zisk verify
```

## Installation

Check the [GitHub repository](https://github.com/MatteoMer/zigkvm-sdk) for the latest release and installation instructions.

See [`examples/`](examples/) for complete project setup with `build.zig` and `build.zig.zon` configuration.

## API Overview

### Guest API

**Input/Output**
- `readInput(T)` / `readInputSlice()` - Read typed data or bytes
- `setOutput(id, value)` / `setOutputU64(id, value)` - Write results to output slots
- `commit(id, value)` - Alias for `setOutput` (proof outputs)

**Memory**
- `allocator()` - Get heap allocator (bump allocator for zisk, GPA for native)
- `BumpAllocator` - Simple bump allocator for zkVM

**Control**
- `exportEntryPoint(fn)` - Export entry point for zkVM
- `exit(code)` / `exitSuccess()` / `exitError()` - Exit with status
- `isZkVM()` - Detect if running in zkVM or native
- `panic` - Panic handler

### Host API

**Input Preparation**
- `Input.init(allocator)` - Create input builder
- `input.write(value)` - Write typed value
- `input.toFile(path)` - Save to file for zkVM

**Output Reading**
- `Output.fromFile(allocator, path)` - Load outputs from file
- `output.read(id)` / `output.readU64(id)` - Read output values
- `output.slice()` - Get all outputs as slice

## Examples

Check out [`examples/`](examples/) for complete working projects:

- **[double-input](examples/double-input)** - Simple u64 doubling with proofs
- **[bytes-sum](examples/bytes-sum)** - Byte processing with allocator usage

Each example includes guest program, host utilities, and proof generation.

