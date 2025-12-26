const std = @import("std");

pub const Backend = enum {
    zisk,
    ligero,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Backend selection option
    const backend = b.option(Backend, "backend", "Runtime backend: zisk (default), ligero") orelse .zisk;

    // Get the zigkvm-sdk dependency
    const zigkvm_dep = b.dependency("zigkvm", .{
        .target = target,
        .optimize = optimize,
    });

    // Get the runtime module
    const runtime_mod = zigkvm_dep.module("zigkvm_runtime");

    // Build options to pass backend to source code
    const options = b.addOptions();
    options.addOption(Backend, "backend", backend);
    const options_mod = options.createModule();

    // Create the main module
    const main_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    main_module.addImport("zigkvm_runtime", runtime_mod);
    main_module.addImport("build_options", options_mod);

    // Build the host executable
    const exe = b.addExecutable(.{
        .name = "library-api-demo",
        .root_module = main_module,
    });

    b.installArtifact(exe);

    // Run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the demo");
    run_step.dependOn(&run_cmd.step);
}
