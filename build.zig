const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const dep_sokol = b.dependency("sokol_", .{
        .target = target,
        .optimize = optimize,
        .with_tracing = b.option(bool, "with_tracing", "Enable tracing in sokol") orelse false,
        .vulkan = target.result.os.tag == .linux and !target.result.abi.isAndroid(),

        .gles3 = target.result.abi.isAndroid(), // TODO: Android target, easy but not planned because requires extra dependency zig-android-sdk and addtional bloat.
        .wgpu = target.result.cpu.arch.isWasm(),
    });

    const nanovg_mod = module(b, .{
        .sokol = dep_sokol.module("sokol"),
        .target = target,
        .optimize = optimize,
    });

    if (target.result.cpu.arch.isWasm()) {
        nanovg_mod.addIncludePath(b.path("src/web/libc"));
    } else {
        // TODO: port all examples:
        _ = installDemo(b, target, optimize, "demo_fbo", "examples/example_fbo.zig", nanovg_mod, dep_sokol);
        _ = installDemo(b, target, optimize, "demo_clip", "examples/example_clip.zig", nanovg_mod, dep_sokol);
        _ = installDemo(b, target, optimize, "demo_blur", "examples/example_blur.zig", nanovg_mod, dep_sokol);
        _ = installDemo(b, target, optimize, "demo_sokol_", "examples/example_sokol_.zig", nanovg_mod, dep_sokol);
        const demo_sokol = installDemo(b, target, optimize, "demo_sokol", "examples/example_sokol.zig", nanovg_mod, dep_sokol);

        const run_demo_sokol = b.addRunArtifact(demo_sokol);
        const run_step_ = b.step("run", "Run the Sokol demo");
        run_demo_sokol.step.dependOn(b.getInstallStep());
        run_step_.dependOn(&run_demo_sokol.step);
    }
}

pub fn module(
    b: *std.Build,
    options: struct {
        target: std.Build.ResolvedTarget,
        optimize: std.builtin.OptimizeMode,
        sokol: *std.Build.Module,
    },
) *std.Build.Module {
    const mod = b.addModule("nanovg", .{
        .root_source_file = b.path("src/nanovg.zig"),
        .target = options.target,
        .optimize = options.optimize,
    });

    mod.addImport("sokol", options.sokol);

    const c = b.addTranslateC(.{
        .root_source_file = b.path("src/import.c"),
        .target = options.target,
        .optimize = options.optimize,
    });

    mod.addImport("c", c.createModule());
    mod.addIncludePath(b.path("src"));
    mod.addCSourceFile(.{ .file = b.path("src/fontstash.c"), .flags = &.{ "-DFONS_NO_STDIO", "-fno-stack-protector" } });
    mod.addCSourceFile(.{ .file = b.path("src/stb_image.c"), .flags = &.{ "-DSTBI_NO_STDIO", "-fno-stack-protector" } });

    return mod;
}

fn installDemo(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, name: []const u8, path: []const u8, nanovg_mod: *std.Build.Module, dep_sokol: *std.Build.Dependency) *std.Build.Step.Compile {
    const demo = b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(.{
            .root_source_file = b.path(path),
            .target = target,
            .optimize = optimize,
        }),
    });
    demo.root_module.addImport("nanovg", nanovg_mod);
    demo.root_module.addImport("sokol", dep_sokol.module("sokol"));

    // TODO: multiple targets
    // if (target.result.cpu.arch.isWasm()) {
    //     demo.rdynamic = true;
    //     demo.entry = .disabled;
    // } else {
    //     demo.root_module.addImport("glfw_gl", glfwgl);
    //     demo.root_module.addIncludePath(b.path("lib/gl2/include"));
    //     demo.root_module.addCSourceFile(.{ .file = b.path("lib/gl2/src/glad.c"), .flags = &.{} });
    //     switch (target.result.os.tag) {
    //         .windows => {
    //             b.installBinFile("glfw3.dll", "glfw3.dll");
    //             demo.root_module.linkSystemLibrary("glfw3dll", .{});
    //             demo.root_module.linkSystemLibrary("opengl32", .{});
    //         },
    //         .macos => {
    //             demo.root_module.addIncludePath(.{ .cwd_relative = "/opt/homebrew/include" });
    //             demo.root_module.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/lib" });
    //             demo.root_module.linkSystemLibrary("glfw", .{});
    //             demo.root_module.linkFramework("OpenGL", .{});
    //         },
    //         .linux => {
    //             demo.root_module.linkSystemLibrary("glfw3", .{});
    //             demo.root_module.linkSystemLibrary("GL", .{});
    //             demo.root_module.linkSystemLibrary("X11", .{});
    //         },
    //         else => {
    //             std.log.warn("Unsupported target: {}", .{target});
    //             demo.root_module.linkSystemLibrary("glfw3", .{});
    //             demo.root_module.linkSystemLibrary("GL", .{});
    //         },
    //     }
    // }
    b.installArtifact(demo);
    return demo;
}
