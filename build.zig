const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    // El rasterizado por software es el hot path; ReleaseFast por defecto.
    const optimize = b.option(
        std.builtin.OptimizeMode,
        "optimize",
        "Prioritize performance, safety, or binary size",
    ) orelse .ReleaseFast;

    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = .ReleaseSafe,
        .linkage = .dynamic,
        .raudio = false,
    });
    const raylib = raylib_dep.module("raylib");

    const exe = b.addExecutable(.{
        .name = "solar_system",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "raylib", .module = raylib },
            },
        }),
    });
    b.installArtifact(exe);
    b.installArtifact(raylib_dep.artifact("raylib"));

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the software-rendered solar system");
    run_step.dependOn(&run_cmd.step);
}
