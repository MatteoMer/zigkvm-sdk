const std = @import("std");

const Backend = enum {
    zisk,
    native,
};

pub fn build(b: *std.Build) void {
    const backend = b.option(Backend, "backend", "zkVM backend to use (default: native)") orelse .native;
    const native_target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zigkvm_dep = b.dependency("zigkvm", .{
        .backend = backend,
        .target = native_target,
        .optimize = optimize,
    });

    // ============================================================
    // Guest: The zkVM program that gets proven
    // ============================================================
    const guest_target = switch (backend) {
        .zisk => b.resolveTargetQuery(.{
            .cpu_arch = .riscv64,
            .os_tag = .freestanding,
            .abi = .none,
            .cpu_features_sub = std.Target.riscv.featureSet(&.{.c}),
        }),
        .native => native_target,
    };

    var guest_module_options: std.Build.Module.CreateOptions = .{
        .root_source_file = b.path("src/guest/main.zig"),
        .target = guest_target,
        .optimize = if (backend == .zisk) .ReleaseSmall else optimize,
    };

    if (backend == .zisk) {
        guest_module_options.code_model = .medium;
        guest_module_options.red_zone = false;
        guest_module_options.stack_protector = false;
        guest_module_options.single_threaded = true;
    }

    const guest_module = b.createModule(guest_module_options);
    guest_module.addImport("zigkvm", zigkvm_dep.module("zigkvm"));

    const guest_exe = b.addExecutable(.{
        .name = "bytes-sum-guest",
        .root_module = guest_module,
    });

    if (backend == .zisk) {
        guest_exe.setLinkerScript(zigkvm_dep.path("src/zisk.ld"));
    }

    b.installArtifact(guest_exe);

    // ============================================================
    // Host: Prepares inputs and runs on host machine
    // ============================================================
    const host_module = b.createModule(.{
        .root_source_file = b.path("src/host/main.zig"),
        .target = native_target,
        .optimize = optimize,
    });
    host_module.addImport("zigkvm_host", zigkvm_dep.module("zigkvm_host"));

    const host_exe = b.addExecutable(.{
        .name = "bytes-sum-host",
        .root_module = host_module,
    });

    b.installArtifact(host_exe);

    // Run step for host (generates input.bin)
    const run_host = b.addRunArtifact(host_exe);
    run_host.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_host.addArgs(args);
    }

    const run_step = b.step("run-host", "Run the host to generate input.bin");
    run_step.dependOn(&run_host.step);

    // ============================================================
    // Tests
    // ============================================================
    const host_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/host/main.zig"),
            .target = native_target,
            .optimize = optimize,
        }),
    });
    host_tests.root_module.addImport("zigkvm_host", zigkvm_dep.module("zigkvm_host"));

    const run_host_tests = b.addRunArtifact(host_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_host_tests.step);

    // ============================================================
    // Prove: Generate ZK proof using cargo-zisk (zisk backend only)
    // ============================================================
    if (backend == .zisk) {
        const prove_step = b.step("prove", "Generate ZK proof with cargo-zisk");
        prove_step.dependOn(b.getInstallStep());

        // Generate input.bin by running the host
        const gen_input = b.addRunArtifact(host_exe);
        gen_input.step.dependOn(b.getInstallStep());
        prove_step.dependOn(&gen_input.step);

        // Workaround: Create proofs directory (cargo-zisk bug)
        const mkdir_proofs = b.addSystemCommand(&[_][]const u8{
            "mkdir",
            "-p",
            "proofs/proofs",
        });
        mkdir_proofs.step.dependOn(&gen_input.step);
        prove_step.dependOn(&mkdir_proofs.step);

        // Run cargo-zisk prove
        const cargo_prove = b.addSystemCommand(&[_][]const u8{
            "cargo-zisk",
            "prove",
            "--elf",
            "zig-out/bin/bytes-sum-guest",
            "--emulator",
            "--input",
            "input.bin",
            "--output-dir",
            "proofs",
            "-vvvv",
            "-a",
            "-y",
        });
        cargo_prove.step.dependOn(&mkdir_proofs.step);
        prove_step.dependOn(&cargo_prove.step);

        // ============================================================
        // Verify: Verify ZK proof using cargo-zisk (zisk backend only)
        // ============================================================
        const verify_step = b.step("verify", "Verify ZK proof with cargo-zisk");

        const proof_path = b.option([]const u8, "proof", "Path to proof file") orelse "proofs/vadcop_final_proof.compressed.bin";

        const cargo_verify = b.addSystemCommand(&[_][]const u8{
            "cargo-zisk",
            "verify",
            "--proof",
            proof_path,
        });
        verify_step.dependOn(&cargo_verify.step);
    }
}
