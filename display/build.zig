const std = @import("std");
const SERVER = "http://localhost:3000";
const PHOTO_NAME = "RandomPhoto";
const PHOTO_DIR = "photos";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "display",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize, 
            .imports = &.{}
        }),

    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run app");
    const run_cmd = b.addRunArtifact(exe);

    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    run_cmd.addArg(b.pathFromRoot("."));
    run_cmd.addArg(SERVER);
    run_cmd.addArg(PHOTO_NAME);
    run_cmd.addArg(PHOTO_DIR);

    if(b.args) |args| {
        run_cmd.addArgs(args);
    }

    const backend_exe = b.addExecutable(.{
        .name = "backend",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/backend.zig"),
            .target = target,
            .optimize = optimize, 
            .imports = &.{}
        }),

    });

    b.installArtifact(backend_exe);

    const backend_step = b.step("backend", "Run app");
    const backend_cmd = b.addRunArtifact(backend_exe);

    backend_step.dependOn(&backend_cmd.step);
    backend_cmd.step.dependOn(b.getInstallStep());

    backend_cmd.addArg(b.pathFromRoot("."));
    backend_cmd.addArg(SERVER);
    backend_cmd.addArg(PHOTO_NAME);
    backend_cmd.addArg(PHOTO_DIR);

    if(b.args) |args| {
        backend_cmd.addArgs(args);
    }

    //RAYLIB
    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });

    const raylib = raylib_dep.module("raylib"); // main raylib module
    const raygui = raylib_dep.module("raygui"); // raygui module
    const raylib_artifact = raylib_dep.artifact("raylib"); // raylib C library

    exe.root_module.linkLibrary(raylib_artifact);
    exe.root_module.addImport("raylib", raylib);
    exe.root_module.addImport("raygui", raygui);
}
