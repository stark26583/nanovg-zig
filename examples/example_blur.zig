const std = @import("std");
const builtin = @import("builtin");

const sokol = @import("sokol");
const sg = sokol.gfx;
const sapp = sokol.app;
const sglue = sokol.glue;
const slog = sokol.log;

const PerfGraph = @import("perf.zig");
const nvg = @import("nanovg");

const state = struct {
    var gpa = std.heap.DebugAllocator(.{}){};
    var allocator: std.mem.Allocator = if (builtin.cpu.arch.isWasm()) std.heap.c_allocator else gpa.allocator();

    var pass_action: sg.PassAction = .{};
    var vg: nvg = undefined;
    var fps = PerfGraph.init(.fps, "Frame Time");

    var mouse_x: f32 = 0;
    var mouse_y: f32 = 0;
    var mouse_down: bool = false;
    var mouse_down_prev: bool = false;

    var blur: f32 = 8.0;
    const blur_max: f32 = 256.0;
    var slider_value: f32 = 0.375;
    var slider_grab: bool = false;

    var image_baboon: nvg.Image = undefined;
};

fn pointInRect(px: f32, py: f32, rx: f32, ry: f32, rw: f32, rh: f32) bool {
    return px >= rx and py >= ry and px < rx + rw and py < ry + rh;
}

fn drawSlider(vg: nvg, x: f32, y: f32, w: f32, value: f32) void {
    vg.fillColor(nvg.rgb(0xdd, 0xdd, 0xdd));
    vg.strokeColor(nvg.rgb(0x55, 0x55, 0x55));
    vg.beginPath();
    vg.roundedRect(x - 2.5, y - 2.5, w + 5, 5, 2.5);
    vg.fill();
    vg.stroke();

    const knob_x = x + @round(w * value);
    vg.beginPath();
    vg.ellipse(knob_x, y, 6.5, 6.6);
    vg.fill();
    vg.stroke();
}

fn drawBlurDemo(vg: nvg, width: f32, height: f32) void {
    const img_w: f32 = 256;
    const img_h: f32 = 256;
    const gap = (width - 2 * img_w) / 3;
    var x: f32 = @round(gap);
    const y: f32 = (height - img_h) / 2;

    vg.save();
    defer vg.restore();

    // Original image.
    vg.beginPath();
    vg.rect(x, y, img_w, img_h);
    vg.fillPaint(vg.imagePattern(x, y, img_w, img_h, 0, state.image_baboon, 1));
    vg.fill();

    vg.fontFace("sans");
    vg.textAlign(.{ .horizontal = .center });
    vg.fillColor(nvg.rgbaf(0, 0, 0, 0.5));
    _ = vg.text(x + img_w * 0.5, y + img_h + 25, "Original");
    vg.fillColor(nvg.rgbf(1, 1, 1));
    _ = vg.text(x + img_w * 0.5, y + img_h + 24, "Original");

    // Blurred image.
    x = @round(gap + img_w + gap);
    vg.beginPath();
    vg.rect(x, y, img_w, img_h);
    vg.fillPaint(vg.imageBlur(x, y, img_w, img_h, state.image_baboon, state.blur, 0));
    vg.fill();

    var buf: [64]u8 = undefined;
    const blur_text = std.fmt.bufPrint(&buf, "Blur {d:0.2}px", .{state.blur}) catch "Blur";
    vg.fillColor(nvg.rgbaf(0, 0, 0, 0.5));
    _ = vg.text(x + img_w * 0.5, y + img_h + 25, blur_text);
    vg.fillColor(nvg.rgbf(1, 1, 1));
    _ = vg.text(x + img_w * 0.5, y + img_h + 24, blur_text);

    // Slider control.
    const slider_w = 256;
    const slider_x = x;
    const slider_y = y + img_h + 40;
    drawSlider(vg, slider_x, slider_y, slider_w, state.slider_value);

    if (!state.mouse_down_prev and state.mouse_down and pointInRect(state.mouse_x, state.mouse_y, slider_x, slider_y - 6, slider_w, 12)) {
        state.slider_grab = true;
    }

    if (state.slider_grab) {
        if (state.mouse_down) {
            state.slider_value = std.math.clamp(state.mouse_x - slider_x, 0, slider_w - 1) / slider_w;
            state.blur = std.math.pow(f32, state.blur_max, state.slider_value) - 1;
        } else {
            state.slider_grab = false;
        }
    }
}

export fn init() void {
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });

    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 132.0 / 255.0, .g = 152.0 / 255.0, .b = 187.0 / 255.0, .a = 1.0 },
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
    state.image_baboon = state.vg.createImageMem(@embedFile("images/baboon.jpg"), .{
        .generate_mipmaps = true,
        .repeat_x = false,
        .repeat_y = false,
        .premultiplied = true,
    });
}

export fn event(ev: [*c]const sapp.Event) void {
    state.mouse_x = ev.*.mouse_x;
    state.mouse_y = ev.*.mouse_y;

    switch (ev.*.type) {
        .MOUSE_DOWN => {
            if (ev.*.mouse_button == .LEFT) {
                state.mouse_down = true;
            }
        },
        .MOUSE_UP => {
            if (ev.*.mouse_button == .LEFT) {
                state.mouse_down = false;
            }
        },
        .KEY_UP => {
            if (ev.*.key_code == .ESCAPE) {
                sapp.quit();
            }
        },
        else => {},
    }
}

export fn frame() void {
    const dt = sapp.frameDuration();

    state.fps.update(@floatCast(dt));

    const win_width = sapp.widthf();
    const win_height = sapp.heightf();
    const px_ratio = sapp.dpiScale();

    sg.beginPass(.{
        .action = state.pass_action,
        .swapchain = sglue.swapchain(),
    });

    const vg = state.vg;
    vg.beginFrame(win_width, win_height, px_ratio);

    drawBlurDemo(vg, win_width, win_height);
    state.fps.draw(vg, 5, 5);

    vg.endFrame();

    sg.endPass();
    sg.commit();

    state.mouse_down_prev = state.mouse_down;
}

export fn cleanup() void {
    state.vg.deinit();
    sg.shutdown();
    std.debug.assert(state.gpa.deinit() == .ok);
}

pub fn main() void {
    sapp.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .event_cb = event,
        .width = 1000,
        .height = 600,
        .sample_count = 4,
        .swap_interval = 0,
        .high_dpi = true,
        .window_title = "NanoVG Blur",
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
        .event_cb = event,
        .high_dpi = true,
        .sample_count = 4,
        .window_title = "NanoVG Blur",
        .icon = .{ .sokol_default = true },
        .logger = .{ .func = slog.func },
        .win32 = .{ .console_attach = true },
    };
}
