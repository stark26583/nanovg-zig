const std = @import("std");
const builtin = @import("builtin");

const sokol = @import("sokol");
const sg = sokol.gfx;
const sapp = sokol.app;
const sglue = sokol.glue;
const slog = sokol.log;
const stime = sokol.time;

const nvg = @import("nanovg");
const PerfGraph = @import("perf.zig");

const Framebuffer = nvg.sokol.Framebuffer;

const state = struct {
    var gpa = std.heap.DebugAllocator(.{}){};
    var allocator: std.mem.Allocator = if (builtin.cpu.arch.isWasm()) std.heap.c_allocator else gpa.allocator();

    var pass_action: sg.PassAction = .{};
    var vg: nvg = undefined;
    var fps = PerfGraph.init(.fps, "Frame Time");

    var fb: ?Framebuffer = null;
    var fb_size: u32 = 0;

    var t0: u64 = 0;
};

fn renderPattern(vg: nvg, fb: Framebuffer, t: f32, pxRatio: f32) void {
    const s: f32 = 20.0;
    const sr = (@cos(t) + 1.0) * 0.5;
    const r = s * 0.6 * (0.2 + 0.8 * sr);

    var fbo_width: u32 = undefined;
    var fbo_height: u32 = undefined;
    vg.imageSize(fb.image, &fbo_width, &fbo_height);

    const win_width: f32 = @as(f32, @floatFromInt(fbo_width)) / pxRatio;
    const win_height: f32 = @as(f32, @floatFromInt(fbo_height)) / pxRatio;

    fb.begin();
    defer fb.end();

    vg.beginFrame(win_width, win_height, pxRatio);

    const pw: u32 = @intFromFloat(std.math.ceil(win_width / s));
    const ph: u32 = @intFromFloat(std.math.ceil(win_height / s));

    vg.beginPath();
    for (0..ph) |y| {
        for (0..pw) |x| {
            const cx: f32 = (@as(f32, @floatFromInt(x)) + 0.5) * s;
            const cy: f32 = (@as(f32, @floatFromInt(y)) + 0.5) * s;
            vg.circle(cx, cy, r);
        }
    }
    vg.fillColor(nvg.rgba(220, 160, 0, 200));
    vg.fill();

    vg.endFrame();
}

fn ensureFramebuffer(px_ratio: f32) void {
    const size: u32 = @intFromFloat(100.0 * px_ratio);
    if (size == 0) return;

    if (state.fb) |*fb| {
        if (state.fb_size == size) return;
        fb.delete(state.vg);
        state.fb = null;
    }

    state.fb = Framebuffer.create(state.vg, size, size, .{
        .repeat_x = true,
        .repeat_y = true,
        .premultiplied = true,
    }) catch |err| {
        std.log.err("Framebuffer create failed: {}", .{err});
        return;
    };
    state.fb_size = size;
}

export fn init() void {
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });
    stime.setup();

    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0.3, .g = 0.3, .b = 0.32, .a = 1.0 },
    };
    state.pass_action.stencil = .{
        .load_action = .CLEAR,
        .clear_value = 0,
    };

    state.vg = nvg.sokol.init(state.allocator, .{
        .anti_alias = true,
        .stencil_strokes = true,
        .debug = true,
    }) catch |err| {
        std.log.err("NanoVG init failed: {}", .{err});
        std.process.exit(1);
    };

    _ = state.vg.createFontMem("sans", @embedFile("Roboto-Regular.ttf"));
    state.t0 = stime.now();
}

export fn frame() void {
    const t: f32 = @floatCast(stime.sec(stime.now()));

    const win_width = sapp.widthf();
    const win_height = sapp.heightf();
    const pxRatio = sapp.dpiScale();

    ensureFramebuffer(pxRatio);
    const fb = state.fb orelse return;

    renderPattern(state.vg, fb, t, pxRatio);

    sg.beginPass(.{
        .action = state.pass_action,
        .swapchain = sglue.swapchain(),
    });

    const vg = state.vg;
    vg.beginFrame(win_width, win_height, pxRatio);

    {
        const img = vg.imagePattern(0, 0, 100, 100, 0, fb.image, 1);
        vg.save();
        defer vg.restore();

        for (0..20) |i| {
            const fi: f32 = @floatFromInt(i);
            vg.beginPath();
            vg.rect(10 + fi * 30, 10, 10, win_height - 20);
            vg.fillColor(nvg.hsla(fi / 19.0, 0.5, 0.5, 255));
            vg.fill();
        }

        vg.beginPath();
        vg.roundedRect(140 + @sin(t * 1.3) * 100, 140 + @cos(t * 1.71244) * 100, 250, 250, 20);
        vg.fillPaint(img);
        vg.fill();
        vg.strokeColor(nvg.rgba(220, 160, 0, 255));
        vg.strokeWidth(3);
        vg.stroke();
    }

    vg.endFrame();
    sg.endPass();
    sg.commit();
}

export fn cleanup() void {
    if (state.fb) |*fb| {
        fb.delete(state.vg);
        state.fb = null;
    }
    state.vg.deinit();
    sg.shutdown();
    std.debug.assert(state.gpa.deinit() == .ok);
}

pub fn main() void {
    sapp.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .width = 1000,
        .height = 600,
        .sample_count = 4,
        .swap_interval = 0,
        .high_dpi = true,
        .window_title = "NanoVG Pattern",
        .icon = .{ .sokol_default = true },
        .logger = .{ .func = slog.func },
        .win32 = .{ .console_attach = true },
    });
}

const android = @import("android");

pub const std_options: std.Options = if (builtin.abi.isAndroid())
    .{ .logFn = android.logFn }
else
    .{};

comptime {
    if (builtin.abi.isAndroid()) {
        @export(&sokol_main, .{ .name = "sokol_main" });
    }
}

fn sokol_main() callconv(.c) sapp.Desc {
    return .{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .high_dpi = true,
        .sample_count = 4,
        .window_title = "NanoVG Pattern",
        .icon = .{ .sokol_default = true },
        .logger = .{ .func = slog.func },
        .win32 = .{ .console_attach = true },
    };
}
