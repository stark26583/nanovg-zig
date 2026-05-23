const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const dep_sokol = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
        .vulkan = target.result.os.tag == .linux and !target.result.abi.isAndroid(),

        // .gles3 = target.result.abi.isAndroid(), // TODO: Android target, easy but not planned because requires extra dependency zig-android-sdk and addtional bloat.
        .wgpu = target.result.cpu.arch.isWasm(),
    });

    const nanovg_mod = b.addModule("nanovg", .{
        .root_source_file = b.path("src/nanovg.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = !target.result.cpu.arch.isWasm(),
    });
    nanovg_mod.addImport("sokol", dep_sokol.module("sokol"));

    const c = b.addTranslateC(.{
        .root_source_file = b.path("src/import.c"),
        .target = target,
        .optimize = optimize,
    });

    nanovg_mod.addImport("c", c.createModule());
    nanovg_mod.addIncludePath(b.path("src"));
    nanovg_mod.addCSourceFile(.{ .file = b.path("src/fontstash.c"), .flags = &.{ "-DFONS_NO_STDIO", "-fno-stack-protector" } });
    nanovg_mod.addCSourceFile(.{ .file = b.path("src/stb_image.c"), .flags = &.{ "-DSTBI_NO_STDIO", "-fno-stack-protector" } });

    if (target.result.cpu.arch.isWasm()) {
        nanovg_mod.addIncludePath(b.path("src/web/libc"));
    } else {
        // TODO: port all examples:
        // _ = installDemo(b, target, optimize, "demo_fbo", "examples/example_fbo.zig", nanovg_mod);
        // _ = installDemo(b, target, optimize, "demo_clip", "examples/example_clip.zig", nanovg_mod);
        // _ = installDemo(b, target, optimize, "demo_blur", "examples/example_blur.zig", nanovg_mod);
        const demo_sokol = installDemo(b, target, optimize, "demo_sokol", nanovg_mod, dep_sokol);

        const run_demo_sokol = b.addRunArtifact(demo_sokol);
        const run_step_ = b.step("run", "Run the Sokol demo");
        run_step_.dependOn(&run_demo_sokol.step);
    }
}

fn installDemo(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, name: []const u8, nanovg_mod: *std.Build.Module, dep_sokol: *std.Build.Dependency) *std.Build.Step.Compile {
    const demo = b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/example_sokol.zig"),
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
