const std = @import("std");
const sokol = @import("sokol");
const slog = sokol.log;
const stime = sokol.time;
const sg = sokol.gfx;
const sapp = sokol.app;
const sglue = sokol.glue;

const Demo = @import("demo.zig");
const PerfGraph = @import("perf.zig");

const nvg = @import("nanovg");

const state = struct {
    var blowup: bool = false;
    var screenshot: bool = false;
    var premult: bool = false;

    var gpa = std.heap.DebugAllocator(.{}){};
    var allocator: std.mem.Allocator = if (builtin.cpu.arch.isWasm()) std.heap.c_allocator else gpa.allocator();
    var pass_action: sg.PassAction = .{
        .stencil = .{ .load_action = .CLEAR },
    };

    var vg: nvg = undefined;
    var mouse = std.mem.zeroes(struct { x: f32, y: f32 });
    var demo: Demo = undefined;
    var fps = PerfGraph.init(.fps, "Frame Time");
    // var start_time: u64 = 0;
};

export fn init() void {
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });

    stime.setup();
    // state.start_time = stime.now();

    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0.50, .g = 0.51, .b = 0.54, .a = 1.0 },
    };

    state.vg = nvg.sokol.init(state.allocator, .{
        .anti_alias = true,
        .stencil_strokes = true,
        .debug = true,
    }) catch |err| {
        std.log.err("Nvg init failed: {}", .{err});
        std.process.exit(1);
    };
    state.demo.load(state.vg);

    std.log.info("Backend: {}", .{sg.queryBackend()});
}

export fn event(ev: [*c]const sapp.Event) void {
    state.mouse.x = ev.*.mouse_x;
    state.mouse.y = ev.*.mouse_y;

    if (ev.*.type == .KEY_UP) {
        switch (ev.*.key_code) {
            .ESCAPE => {
                sapp.quit();
            },
            .SPACE => {
                state.blowup = !state.blowup;
            },
            .S => {
                state.screenshot = true;
            },
            .P => {
                state.premult = !state.premult;
            },
            else => {},
        }
    }
}

export fn frame() void {
    const t: f32 = @floatCast(stime.sec(stime.now()));
    state.fps.update(@floatCast(sapp.frameDuration()));

    const win_width = sapp.widthf();
    const win_height = sapp.heightf();
    const pxRatio = sapp.dpiScale();

    if (state.premult) {
        state.pass_action.colors[0].clear_value = .{ .r = 0, .g = 0, .b = 0, .a = 0 };
    } else {
        state.pass_action.colors[0].clear_value = .{ .r = 0.3, .g = 0.3, .b = 0.32, .a = 1.0 };
    }

    sg.beginPass(.{
        .action = state.pass_action,
        .swapchain = sglue.swapchain(),
    });

    const vg = state.vg;
    vg.beginFrame(win_width, win_height, pxRatio);

    state.demo.draw(vg, state.mouse.x, state.mouse.y, win_width, win_height, t, state.blowup);
    state.fps.draw(vg, 5, 5);

    vg.endFrame();

    sg.endPass();
    sg.commit();
}

export fn cleanup() void {
    state.demo.free(state.vg);
    state.vg.deinit(); // free NanoVG/internal allocations first
    sg.shutdown(); // then sokol
    std.debug.assert(state.gpa.deinit() == .ok);
}

pub fn main() void {
    sapp.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .event_cb = event,
        .width = 1280,
        .height = 700,
        .swap_interval = 0,
        .sample_count = 4,
        .window_title = "NanoVG quick start",
        .icon = .{ .sokol_default = true },
        .logger = .{ .func = slog.func },
        .win32 = .{ .console_attach = true },
    });
}

const builtin = @import("builtin");
const android = @import("android");

pub const std_options: std.Options = if (builtin.abi.isAndroid())
    .{
        .logFn = android.logFn,
    }
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
        .window_title = "NanoVG quick start",
        .icon = .{ .sokol_default = true },
        .logger = .{ .func = slog.func },
        .win32 = .{ .console_attach = true },
    };
}
