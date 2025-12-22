# Examples

Small standalone Zig projects that depend on `zigkvm-sdk`.

## Projects

- `double-input` - reads a `u64` input and writes `input * 2` as output.
- `bytes-sum` - reads input bytes, copies them with the SDK allocator, then outputs a checksum and length.

## Build

From each example directory:

```bash
zig build -Dbackend=native
zig build -Dbackend=zisk -Doptimize=ReleaseSmall
```

## Native input harness

The native backend does not read stdin; it expects input data to be set in memory. For quick checks, you can add a small test harness like this in the example's `src/main.zig`:

```zig
test "native harness" {
    if (!@hasDecl(zkvm, "setInputData")) return;
    var input: u64 = 21;
    zkvm.setInputData(std.mem.asBytes(&input));
    main();
}
```

For real projects, replace the local `.path` dependency in `build.zig.zon` with the GitHub URL and hash from the main README.
