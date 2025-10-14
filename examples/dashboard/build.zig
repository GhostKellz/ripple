const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const ripple_dep = b.dependency("ripple", .{
        .target = target,
        .optimize = optimize,
    });
    const ripple_mod = ripple_dep.module("ripple");

    const exe = b.addExecutable(.{
        .name = "dashboard",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("ripple", ripple_mod);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the dashboard example");
    run_step.dependOn(&run_cmd.step);
}
