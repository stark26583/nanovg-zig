const std = @import("std");

var glfwgl: *std.Build.Module = undefined;

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const dep_sokol = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
    });

    const nanovg_mod = b.addModule("nanovg", .{
        .root_source_file = b.path("src/nanovg.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = !target.result.cpu.arch.isWasm(),
    });
    nanovg_mod.addImport("sokol", dep_sokol.module("sokol"));

    const glfwglc = b.addTranslateC(.{
        .root_source_file = b.path("src/glfw_dep/glfw_glad.c"),
        .target = target,
        .optimize = optimize,
    });
    glfwglc.addIncludePath(b.path("lib/gl2/include"));
    glfwgl = glfwglc.createModule();

    const c = b.addTranslateC(.{
        .root_source_file = b.path("src/import.c"),
        .target = target,
        .optimize = optimize,
    });

    nanovg_mod.addImport("c", c.createModule());
    nanovg_mod.addImport("glfw_gl", glfwgl);
    nanovg_mod.addIncludePath(b.path("src"));
    nanovg_mod.addIncludePath(b.path("lib/gl2/include"));
    nanovg_mod.addCSourceFile(.{ .file = b.path("src/fontstash.c"), .flags = &.{ "-DFONS_NO_STDIO", "-fno-stack-protector" } });
    nanovg_mod.addCSourceFile(.{ .file = b.path("src/stb_image.c"), .flags = &.{ "-DSTBI_NO_STDIO", "-fno-stack-protector" } });

    if (target.result.cpu.arch.isWasm()) {
        nanovg_mod.addIncludePath(b.path("src/web/libc"));
        _ = installDemo(b, target, optimize, "demo", "examples/example_wasm.zig", nanovg_mod);
    } else {
        const demo_glfw = installDemo(b, target, optimize, "demo_glfw", "examples/example_glfw.zig", nanovg_mod);
        _ = installDemo(b, target, optimize, "demo_fbo", "examples/example_fbo.zig", nanovg_mod);
        _ = installDemo(b, target, optimize, "demo_clip", "examples/example_clip.zig", nanovg_mod);
        _ = installDemo(b, target, optimize, "demo_blur", "examples/example_blur.zig", nanovg_mod);

        const run_demo_glfw = b.addRunArtifact(demo_glfw);
        const run_step = b.step("run", "Run the demo");
        run_step.dependOn(&run_demo_glfw.step);
    }
}

fn installDemo(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, name: []const u8, root_source_file: []const u8, nanovg_mod: *std.Build.Module) *std.Build.Step.Compile {
    const demo = b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(.{
            .root_source_file = b.path(root_source_file),
            .target = target,
            .optimize = optimize,
        }),
    });
    demo.root_module.addImport("nanovg", nanovg_mod);

    if (target.result.cpu.arch.isWasm()) {
        demo.rdynamic = true;
        demo.entry = .disabled;
    } else {
        demo.root_module.addImport("glfw_gl", glfwgl);
        demo.root_module.addIncludePath(b.path("lib/gl2/include"));
        demo.root_module.addCSourceFile(.{ .file = b.path("lib/gl2/src/glad.c"), .flags = &.{} });
        switch (target.result.os.tag) {
            .windows => {
                b.installBinFile("glfw3.dll", "glfw3.dll");
                demo.root_module.linkSystemLibrary("glfw3dll", .{});
                demo.root_module.linkSystemLibrary("opengl32", .{});
            },
            .macos => {
                demo.root_module.addIncludePath(.{ .cwd_relative = "/opt/homebrew/include" });
                demo.root_module.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/lib" });
                demo.root_module.linkSystemLibrary("glfw", .{});
                demo.root_module.linkFramework("OpenGL", .{});
            },
            .linux => {
                demo.root_module.linkSystemLibrary("glfw3", .{});
                demo.root_module.linkSystemLibrary("GL", .{});
                demo.root_module.linkSystemLibrary("X11", .{});
            },
            else => {
                std.log.warn("Unsupported target: {}", .{target});
                demo.root_module.linkSystemLibrary("glfw3", .{});
                demo.root_module.linkSystemLibrary("GL", .{});
            },
        }
    }
    b.installArtifact(demo);
    return demo;
}
