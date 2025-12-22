# zigkvm-sdk

A Zig SDK that allows your code to run in a zkVM (zero-knowledge virtual machine).

## Supported Backends

- **zisk** - ZisK zkVM (RISC-V based)
- **native** - Native execution for testing and development

## Installation

Add to your `build.zig.zon`:

```zig
.dependencies = .{
    .zkvm = .{
        .url = "https://github.com/MatteoMer/zigkvm-sdk/archive/<commit>.tar.gz",
        .hash = "...",
    },
},
```

Then in your `build.zig`:

```zig
const zkvm_dep = b.dependency("zkvm", .{
    .backend = .zisk,  // or .native for testing
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("zkvm", zkvm_dep.module("zkvm"));

// For zisk backend, also set the linker script
if (backend == .zisk) {
    exe.setLinkerScript(zkvm_dep.path("src/zisk.ld"));
}
```

## Usage

```zig
const zkvm = @import("zkvm");

// Export entry point (required for zkVM execution)
comptime {
    zkvm.exportEntryPoint(main);
}

// Use the SDK's panic handler
pub const panic = zkvm.panic;

fn main() void {
    // Read input
    const input = zkvm.readInput(u64);

    // Process
    const result = input * 2;

    // Write output
    zkvm.setOutputU64(0, result);
}
```

## Host Utilities

The SDK includes host-side utilities for preparing inputs and reading outputs:

```zig
const host = @import("zkvm_host");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Prepare input for guest program
    var input = host.Input.init(allocator);
    defer input.deinit();

    try input.write(@as(u64, 42));
    try input.toFile("input.bin");

    // Read output from guest program
    var output = try host.Output.fromFile(allocator, "output.bin");
    defer output.deinit();

    const result = output.readU64(0);
}
```

In your `build.zig`, add the host module:

```zig
host_module.addImport("zkvm_host", zkvm_dep.module("zkvm_host"));
```

## Examples

See the `examples/` directory for complete working examples:

- **double-input** - Reads a u64 and outputs double the value
- **bytes-sum** - Reads bytes, copies them, and outputs a checksum

Each example includes both guest and host programs. From an example directory:

```bash
# Build for zisk
zig build -Dbackend=zisk -Doptimize=ReleaseSmall

# Generate input and create a proof
zig build -Dbackend=zisk prove

# Verify the proof
zig build -Dbackend=zisk verify
```

## API Reference

### Input Functions

| Function | Description |
|----------|-------------|
| `readInput(T) T` | Read input as typed value |
| `readInputSlice() []const u8` | Read input as byte slice |
| `readInputAt(T, offset) T` | Read typed value at offset |
| `readInputSize() u64` | Get input size in bytes |

### Output Functions

| Function | Description |
|----------|-------------|
| `setOutput(id, value)` | Set u32 output at slot (0-63) |
| `setOutputU64(id, value)` | Set u64 using two slots |
| `getOutput(id) u32` | Get u32 output value |
| `getOutputU64(id) u64` | Get u64 from two slots |
| `commit(id, value)` | Alias for setOutput |

### Control Functions

| Function | Description |
|----------|-------------|
| `exit(code)` | Exit with status code |
| `exitSuccess()` | Exit with code 0 |
| `exitError()` | Exit with code 1 |
| `isZkVM() bool` | Check if running in zkVM |

### Memory

| Function | Description |
|----------|-------------|
| `allocator()` | Get heap allocator |
| `BumpAllocator` | Simple bump allocator type |

### Entry Point

| Function | Description |
|----------|-------------|
| `exportEntryPoint(fn)` | Export main as zkVM entry |
| `panic` | Panic handler for zkVM |

## Building

```bash
# Build for zisk zkVM
zig build -Dbackend=zisk -Doptimize=ReleaseSmall

# Build for native testing
zig build -Dbackend=native

# Run tests
zig build test
```

## License

MIT
