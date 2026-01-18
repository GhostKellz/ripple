const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const ripple_dep = b.dependency("ripple", .{
        .target = target,
        .optimize = optimize,
    });
    const ripple_mod = ripple_dep.module("ripple");

    const zsync_dep = b.dependency("zsync", .{
        .target = target,
        .optimize = optimize,
    });
    const zsync_mod = zsync_dep.module("zsync");

    const exe = b.addExecutable(.{
        .name = "forms-ssr-pe",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "ripple", .module = ripple_mod },
                .{ .name = "zsync", .module = zsync_mod },
            },
        }),
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the forms SSR + PE demo");
    run_step.dependOn(&run_cmd.step);
}
