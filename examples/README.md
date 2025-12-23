# Examples

Small standalone Zig projects that depend on `zigkvm-sdk`.

## Projects

- `double-input` - reads a `u64` input and writes `input * 2` as output.
- `bytes-sum` - reads input bytes, copies them with the SDK allocator, then outputs a checksum and length.
- `private-input-example` - uses Ligero public/private inputs to prove a secret-derived value.

## Build & Run

From each example directory:

```bash
# Build for native testing
zig build -Dbackend=native

# Build for ZisK zkVM
zig build -Dbackend=zisk -Doptimize=ReleaseSmall

# Build for Ligero zkVM
zig build -Dbackend=ligero -Doptimize=ReleaseSmall

# Generate input file
zig build run-host

# Generate ZK proof (includes input generation)
zig build -Dbackend=zisk prove

# Verify proof
zig build -Dbackend=zisk verify
```

## Native input harness

The native backend does not read stdin; it expects input data to be set in memory. For quick checks, you can add a small test harness like this in the example's `src/guest/main.zig`:

```zig
test "native harness" {
    if (!@hasDecl(zigkvm, "setInputData")) return;
    var input: u64 = 21;
    zigkvm.setInputData(std.mem.asBytes(&input));
    main();
}
```

For real projects, replace the local `.path` dependency in `build.zig.zon` with the GitHub URL and hash from the main README.
