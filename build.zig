const std = @import("std");

/// Available zkVM backends
pub const Backend = enum {
    /// ZisK zkVM backend
    zisk,
    /// Native backend for testing (default)
    native,
    /// Ligero zkVM backend (WebGPU-based)
    ligero,

    pub fn fromString(str: ?[]const u8) Backend {
        const s = str orelse return .native;
        if (std.mem.eql(u8, s, "zisk")) return .zisk;
        if (std.mem.eql(u8, s, "native")) return .native;
        if (std.mem.eql(u8, s, "ligero")) return .ligero;
        std.debug.print("Unknown backend: {s}. Valid options: native, zisk, ligero\n", .{s});
        return .native;
    }
};

pub fn build(b: *std.Build) void {
    // Backend selection option (accepts string for easier dependency forwarding)
    const backend_str = b.option([]const u8, "backend", "zkVM backend to use: native (default), zisk, ligero");
    const backend = Backend.fromString(backend_str);

    // Standard options for native builds
    const native_target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Determine target based on backend
    const target = switch (backend) {
        .zisk => b.resolveTargetQuery(.{
            .cpu_arch = .riscv64,
            .os_tag = .freestanding,
            .abi = .none,
            .cpu_features_sub = std.Target.riscv.featureSet(&.{.c}),
        }),
        .ligero => b.resolveTargetQuery(.{
            .cpu_arch = .wasm32,
            .os_tag = .wasi,
            .abi = .musl,
        }),
        .native => native_target,
    };

    // Build options module to pass backend selection to source code
    const options = b.addOptions();
    options.addOption(Backend, "backend", backend);
    const options_mod = options.createModule();

    // Create precompiles types module (shared across backends that support precompiles)
    const precompiles_types_mod = b.createModule(.{
        .root_source_file = b.path("src/precompiles/types.zig"),
        .target = target,
        .optimize = if (backend == .zisk or backend == .ligero) .ReleaseSmall else optimize,
    });

    // Create precompiles module (only for ZisK backend)
    const lib_precompiles_mod = if (backend == .zisk) b.createModule(.{
        .root_source_file = b.path("src/precompiles/zisk/precompiles.zig"),
        .target = target,
        .optimize = .ReleaseSmall,
        .imports = &.{
            .{ .name = "types.zig", .module = precompiles_types_mod },
        },
    }) else null;

    // Create the library module (for use as a dependency)
    // Select backend file directly as module root - no re-export wrapper needed
    const zigkvm_module = b.addModule("zigkvm", .{
        .root_source_file = switch (backend) {
            .zisk => b.path("src/backends/zisk.zig"),
            .native => b.path("src/backends/native.zig"),
            .ligero => b.path("src/backends/ligero.zig"),
        },
        .target = target,
        .optimize = if (backend == .zisk or backend == .ligero) .ReleaseSmall else optimize,
        .imports = if (backend == .zisk) &.{
            .{ .name = "build_options", .module = options_mod },
            .{ .name = "precompiles", .module = lib_precompiles_mod.? },
        } else &.{
            .{ .name = "build_options", .module = options_mod },
        },
    });

    if (backend == .zisk) {
        zigkvm_module.code_model = .medium;
        zigkvm_module.red_zone = false;
        zigkvm_module.stack_protector = false;
        zigkvm_module.single_threaded = true;
    }

    if (backend == .ligero) {
        zigkvm_module.single_threaded = true;
        zigkvm_module.stack_check = false;
    }

    // Host utilities module (always runs on host machine, not in zkVM)
    // Used for preparing inputs, running tests, etc.
    const host_module = b.addModule("zigkvm_host", .{
        .root_source_file = b.path("src/host.zig"),
        .target = native_target, // Always target host machine
        .optimize = optimize,
        .imports = &.{
            .{ .name = "build_options", .module = options_mod },
        },
    });

    // Runtime module for programmatic proving and emulation
    // Backend is selected at runtime, not compile time
    _ = b.addModule("zigkvm_runtime", .{
        .root_source_file = b.path("src/runtime/runtime.zig"),
        .target = native_target, // Always target host machine
        .optimize = optimize,
        .imports = &.{
            .{ .name = "host", .module = host_module },
        },
    });

    // Tests (always run with native backend)
    const test_options = b.addOptions();
    test_options.addOption(Backend, "backend", .native);
    const test_options_mod = test_options.createModule();

    const test_module = b.createModule(.{
        .root_source_file = b.path("src/backends/native.zig"),
        .target = native_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "build_options", .module = test_options_mod },
        },
    });

    const tests = b.addTest(.{
        .root_module = test_module,
    });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);

    // Host module tests (native encoder)
    const host_native_test_module = b.createModule(.{
        .root_source_file = b.path("src/host/backends/native/encoder.zig"),
        .target = native_target,
        .optimize = optimize,
    });

    const host_native_tests = b.addTest(.{
        .root_module = host_native_test_module,
    });

    const run_host_native_tests = b.addRunArtifact(host_native_tests);
    test_step.dependOn(&run_host_native_tests.step);

    // Host module tests (zisk encoder)
    const host_zisk_test_module = b.createModule(.{
        .root_source_file = b.path("src/host/backends/zisk/encoder.zig"),
        .target = native_target,
        .optimize = optimize,
    });

    const host_zisk_tests = b.addTest(.{
        .root_module = host_zisk_test_module,
    });

    const run_host_zisk_tests = b.addRunArtifact(host_zisk_tests);
    test_step.dependOn(&run_host_zisk_tests.step);

    // Host module tests (native output decoder)
    const host_output_native_test_module = b.createModule(.{
        .root_source_file = b.path("src/host/backends/native/decoder.zig"),
        .target = native_target,
        .optimize = optimize,
    });

    const host_output_native_tests = b.addTest(.{
        .root_module = host_output_native_test_module,
    });

    const run_host_output_native_tests = b.addRunArtifact(host_output_native_tests);
    test_step.dependOn(&run_host_output_native_tests.step);

    // Host module tests (zisk output decoder)
    const host_output_zisk_test_module = b.createModule(.{
        .root_source_file = b.path("src/host/backends/zisk/decoder.zig"),
        .target = native_target,
        .optimize = optimize,
    });

    const host_output_zisk_tests = b.addTest(.{
        .root_module = host_output_zisk_test_module,
    });

    const run_host_output_zisk_tests = b.addRunArtifact(host_output_zisk_tests);
    test_step.dependOn(&run_host_output_zisk_tests.step);

    // Runtime module tests
    const runtime_test_module = b.createModule(.{
        .root_source_file = b.path("src/runtime/runtime.zig"),
        .target = native_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "host", .module = host_module },
        },
    });

    const runtime_tests = b.addTest(.{
        .root_module = runtime_test_module,
    });

    const run_runtime_tests = b.addRunArtifact(runtime_tests);
    test_step.dependOn(&run_runtime_tests.step);

    // Encoder/Decoder module tests
    const encoder_test_module = b.createModule(.{
        .root_source_file = b.path("src/host/encoder.zig"),
        .target = native_target,
        .optimize = optimize,
    });

    const encoder_tests = b.addTest(.{
        .root_module = encoder_test_module,
    });

    const run_encoder_tests = b.addRunArtifact(encoder_tests);
    test_step.dependOn(&run_encoder_tests.step);

    const decoder_test_module = b.createModule(.{
        .root_source_file = b.path("src/host/decoder.zig"),
        .target = native_target,
        .optimize = optimize,
    });

    const decoder_tests = b.addTest(.{
        .root_module = decoder_test_module,
    });

    const run_decoder_tests = b.addRunArtifact(decoder_tests);
    test_step.dependOn(&run_decoder_tests.step);
}
