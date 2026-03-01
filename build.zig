const std = @import("std");
const zgpu_build = @import("zgpu");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "tc_debugger",
        .root_module = mod,
    });

    const protobuf = b.dependency("protobuf", .{ .target = target });
    exe.root_module.addImport("protobuf", protobuf.module("protobuf"));

    const zglfw = b.dependency("zglfw", .{ .target = target });
    exe.root_module.addImport("zglfw", zglfw.module("root"));
    if (target.result.os.tag == .linux) {
        // Add glfw C sources directly to exe to avoid libX11.so being embedded
        // inside libglfw.a, which causes both linkers to fail in Zig 0.14.1.
        const glfw_src = "libs/glfw/src/";
        exe.addIncludePath(zglfw.path("libs/glfw/include"));
        exe.addIncludePath(zglfw.path("libs/glfw/src"));
        exe.addIncludePath(zglfw.path("libs/glfw/src/wayland"));
        exe.addCSourceFiles(.{
            .root = zglfw.path(""),
            .files = &.{
                glfw_src ++ "platform.c",
                glfw_src ++ "monitor.c",
                glfw_src ++ "init.c",
                glfw_src ++ "vulkan.c",
                glfw_src ++ "input.c",
                glfw_src ++ "context.c",
                glfw_src ++ "window.c",
                glfw_src ++ "osmesa_context.c",
                glfw_src ++ "egl_context.c",
                glfw_src ++ "null_init.c",
                glfw_src ++ "null_monitor.c",
                glfw_src ++ "null_window.c",
                glfw_src ++ "null_joystick.c",
                glfw_src ++ "posix_time.c",
                glfw_src ++ "posix_thread.c",
                glfw_src ++ "posix_module.c",
                glfw_src ++ "xkb_unicode.c",
                glfw_src ++ "linux_joystick.c",
                glfw_src ++ "posix_poll.c",
                glfw_src ++ "x11_init.c",
                glfw_src ++ "x11_monitor.c",
                glfw_src ++ "x11_window.c",
                glfw_src ++ "glx_context.c",
                glfw_src ++ "wl_init.c",
                glfw_src ++ "wl_monitor.c",
                glfw_src ++ "wl_window.c",
            },
            .flags = &.{},
        });
        exe.root_module.addCMacro("_GLFW_X11", "1");
        exe.root_module.addCMacro("_GLFW_WAYLAND", "1");
        exe.linkLibC();
        exe.linkSystemLibrary("X11");
    } else {
        exe.linkLibrary(zglfw.artifact("glfw"));
    }

    // Add dawn C sources directly to exe to avoid libdawn.a being embedded
    // inside libzdawn.a, which causes both linkers to fail in Zig 0.14.1.
    zgpu_build.addLibraryPathsTo(exe);
    const zgpu = b.dependency("zgpu", .{ .target = target });
    exe.root_module.addImport("zgpu", zgpu.module("root"));
    exe.addIncludePath(zgpu.path("libs/dawn/include"));
    exe.addIncludePath(zgpu.path("src"));
    exe.addCSourceFile(.{
        .file = zgpu.path("src/dawn.cpp"),
        .flags = &.{ "-std=c++17", "-fno-sanitize=undefined" },
    });
    exe.addCSourceFile(.{
        .file = zgpu.path("src/dawn_proc.c"),
        .flags = &.{"-fno-sanitize=undefined"},
    });
    exe.linkSystemLibrary("dawn");
    exe.linkLibCpp();

    const zgui = b.dependency("zgui", .{ .target = target, .backend = .glfw_wgpu });
    exe.root_module.addImport("zgui", zgui.module("root"));
    exe.linkLibrary(zgui.artifact("imgui"));

    const zmath = b.dependency("zmath", .{ .target = target });
    exe.root_module.addImport("zmath", zmath.module("root"));

    const zmesh = b.dependency("zmesh", .{ .target = target });
    exe.root_module.addImport("zmesh", zmesh.module("root"));
    exe.linkLibrary(zmesh.artifact("zmesh"));

    const znoise = b.dependency("znoise", .{ .target = target });
    exe.root_module.addImport("znoise", znoise.module("root"));
    exe.linkLibrary(znoise.artifact("FastNoiseLite"));

    const ztracy = b.dependency("ztracy", .{ .target = target });
    exe.root_module.addImport("ztracy", ztracy.module("root"));
    exe.linkLibrary(ztracy.artifact("tracy"));

    if (target.result.os.tag == .macos) {
        if (b.lazyDependency("system_sdk", .{})) |system_sdk| {
            exe.addLibraryPath(system_sdk.path("macos12/usr/lib"));
            exe.addSystemFrameworkPath(system_sdk.path("macos12/System/Library/Frameworks"));
        }
    } else if (target.result.os.tag == .linux) {
        if (b.lazyDependency("system_sdk", .{})) |system_sdk| {
            exe.addLibraryPath(system_sdk.path("linux/lib/x86_64-linux-gnu"));
            exe.addSystemIncludePath(system_sdk.path("linux/include"));
            exe.addSystemIncludePath(system_sdk.path("linux/include/wayland"));
        }
    }

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());
}
