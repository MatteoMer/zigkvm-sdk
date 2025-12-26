const std = @import("std");

pub fn build(b: *std.Build) void {
    // Forward backend string to the SDK - it owns the Backend enum
    const backend_str = b.option([]const u8, "backend", "zkVM backend: native (default), zisk, ligero");
    const native_target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zigkvm_dep = b.dependency("zigkvm", .{
        .backend = backend_str,
        .target = native_target,
        .optimize = optimize,
    });

    // Parse backend locally for build logic (target selection, prove steps, etc.)
    const Backend = enum { zisk, native, ligero };
    const backend: Backend = blk: {
        const s = backend_str orelse break :blk .native;
        if (std.mem.eql(u8, s, "zisk")) break :blk .zisk;
        if (std.mem.eql(u8, s, "ligero")) break :blk .ligero;
        break :blk .native;
    };

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
        .ligero => b.resolveTargetQuery(.{
            .cpu_arch = .wasm32,
            .os_tag = .wasi,
            .abi = .musl,
        }),
        .native => native_target,
    };

    var guest_module_options: std.Build.Module.CreateOptions = .{
        .root_source_file = b.path("src/guest/main.zig"),
        .target = guest_target,
        .optimize = if (backend == .zisk or backend == .ligero) .ReleaseSmall else optimize,
    };

    if (backend == .zisk) {
        guest_module_options.code_model = .medium;
        guest_module_options.red_zone = false;
        guest_module_options.stack_protector = false;
        guest_module_options.single_threaded = true;
    }

    if (backend == .ligero) {
        guest_module_options.single_threaded = true;
        guest_module_options.stack_check = false;
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
    // Host: Executes guest using the runtime API
    // ============================================================

    // Create build options for host (backend and guest path)
    const RuntimeBackend = enum { zisk, ligero };
    const options = b.addOptions();

    // Map backend to runtime backend (runtime doesn't support native)
    if (backend == .zisk) {
        options.addOption(RuntimeBackend, "backend", .zisk);
    } else if (backend == .ligero) {
        options.addOption(RuntimeBackend, "backend", .ligero);
    }

    // Pass guest binary path - use the installed path
    const guest_install_path = b.getInstallPath(.bin, guest_exe.out_filename);
    options.addOption([]const u8, "guest_binary", guest_install_path);

    const host_module = b.createModule(.{
        .root_source_file = b.path("src/host/main.zig"),
        .target = native_target,
        .optimize = optimize,
    });
    host_module.addImport("zigkvm_host", zigkvm_dep.module("zigkvm_host"));
    host_module.addImport("zigkvm_runtime", zigkvm_dep.module("zigkvm_runtime"));
    host_module.addImport("build_options", options.createModule());

    const host_exe = b.addExecutable(.{
        .name = "bytes-sum-host",
        .root_module = host_module,
    });

    b.installArtifact(host_exe);

    // ============================================================
    // Run: Execute guest using runtime (zisk/ligero only)
    // ============================================================
    if (backend == .zisk or backend == .ligero) {
        const run_host = b.addRunArtifact(host_exe);
        run_host.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_host.addArgs(args);
        }

        const run_step = b.step("run", "Execute guest program using runtime");
        run_step.dependOn(&run_host.step);
    }

    // ============================================================
    // Tests
    // ============================================================
    const test_module = b.createModule(.{
        .root_source_file = b.path("src/host/main.zig"),
        .target = native_target,
        .optimize = optimize,
    });
    test_module.addImport("zigkvm_host", zigkvm_dep.module("zigkvm_host"));
    test_module.addImport("zigkvm_runtime", zigkvm_dep.module("zigkvm_runtime"));
    test_module.addImport("build_options", options.createModule());

    const host_tests = b.addTest(.{
        .root_module = test_module,
    });

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

        const proof_path = b.option([]const u8, "proof", "Path to proof file") orelse "proofs/vadcop_final_proof.bin";

        const cargo_verify = b.addSystemCommand(&[_][]const u8{
            "cargo-zisk",
            "verify",
            "--proof",
            proof_path,
        });
        verify_step.dependOn(&cargo_verify.step);
    }

    // ============================================================
    // Prove: Generate ZK proof using webgpu_prover (ligero backend only)
    // ============================================================
    if (backend == .ligero) {
        const prove_step = b.step("prove", "Generate ZK proof with Ligero webgpu_prover");
        prove_step.dependOn(b.getInstallStep());

        // Generate input.bin by running the host
        const gen_input = b.addRunArtifact(host_exe);
        gen_input.step.dependOn(b.getInstallStep());
        prove_step.dependOn(&gen_input.step);

        const shader_path = blk: {
            if (b.option([]const u8, "ligero_shader_path", "Path to Ligero shader directory")) |opt| {
                break :blk opt;
            }
            const home_opt = std.process.getEnvVarOwned(b.allocator, "LIGERO_HOME") catch null;
            if (home_opt) |home| {
                defer b.allocator.free(home);
                const joined = std.fs.path.join(b.allocator, &.{ home, "src", "ligero-prover", "shader" }) catch break :blk "../../ligero-prover/shader";
                break :blk joined;
            }
            const user_home_opt = std.process.getEnvVarOwned(b.allocator, "HOME") catch null;
            if (user_home_opt) |user_home| {
                defer b.allocator.free(user_home);
                const joined = std.fs.path.join(b.allocator, &.{ user_home, ".ligero", "src", "ligero-prover", "shader" }) catch break :blk "../../ligero-prover/shader";
                break :blk joined;
            }
            break :blk "../../ligero-prover/shader";
        };

        // Create ligero-config.json from input.bin
        const create_config = b.addSystemCommand(&[_][]const u8{
            "zig",
            "run",
            "../../scripts/ligero/create-ligero-config.zig",
            "--",
            "zig-out/bin/bytes-sum-guest.wasm",
            shader_path,
            "input.bin",
            "ligero-config.json",
        });
        create_config.step.dependOn(&gen_input.step);
        prove_step.dependOn(&create_config.step);

        // Run webgpu_prover
        const ligero_prove = b.addSystemCommand(&[_][]const u8{
            "zig",
            "run",
            "../../scripts/ligero/run-ligero.zig",
            "--",
            "webgpu_prover",
            "ligero-config.json",
        });
        ligero_prove.step.dependOn(&create_config.step);
        prove_step.dependOn(&ligero_prove.step);

        // ============================================================
        // Verify: Verify ZK proof using webgpu_verifier (ligero backend only)
        // ============================================================
        const verify_step = b.step("verify", "Verify ZK proof with Ligero webgpu_verifier");

        const ligero_verify = b.addSystemCommand(&[_][]const u8{
            "zig",
            "run",
            "../../scripts/ligero/run-ligero.zig",
            "--",
            "webgpu_verifier",
            "ligero-config.json",
        });
        verify_step.dependOn(&ligero_verify.step);
    }
}
