const std = @import("std");
const SERVER = "http://localhost:3000";
const PHOTO_NAME = "RandomPhoto";
const PHOTO_DIR = "photos";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("Display", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const exe = b.addExecutable(.{
        .name = "display",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize, 
            .imports = &.{
                .{ .name = "Display", .module = mod },
            },
        }),

    });

    exe.link_gc_sections = true;

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

    const PhaseToolExe= b.addExecutable(.{
        .name = "display",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/PhaseTool.zig"),
            .target = target,
            .optimize = optimize, 
            .imports = &.{}
        }),

    });

    b.installArtifact(exe);

    const phaseToolStep = b.step("phase", "Run app");
    const phaseCmd = b.addRunArtifact(PhaseToolExe);

    phaseToolStep.dependOn(&phaseCmd.step);
    phaseCmd.step.dependOn(b.getInstallStep());

    if(b.args) |args| {
        phaseCmd.addArgs(args);
    }

    const zigclient_dep = b.dependency("ZigClient", .{
        .target = target,
        .optimize = optimize,
    });
    const zigclient_mod = zigclient_dep.module("ZigClient");
    mod.addImport("ZigClient", zigclient_mod);

    // then when creating your exe/module:
    exe.root_module.addImport("ZigClient", zigclient_mod);

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
