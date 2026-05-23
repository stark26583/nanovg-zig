const std = @import("std");
const sokol = @import("sokol");
const slog = sokol.log;
const stime = sokol.time;
const sg = sokol.gfx;
const sapp = sokol.app;
const sglue = sokol.glue;
const Nvg = @import("nanovg");
const font_data = @embedFile("Roboto-Bold.ttf");

const MAX_SAMPLES = 100;

const state = struct {
    var gpa = std.heap.DebugAllocator(.{}){};
    var allocator: std.mem.Allocator = if (builtin.cpu.arch.isWasm()) std.heap.c_allocator else gpa.allocator();
    var pass_action: sg.PassAction = .{};
    var vg: Nvg = undefined;
    var t: f32 = 0.0;
    var frame_times: [MAX_SAMPLES]f32 = @splat(0);
    var frame_index: usize = 0;
    var font: Nvg.Font = undefined;
    // var keyboard: vk.VirtualKeyboard = .{};
    var text = std.ArrayList(u8).empty;
    var mouse: struct { x: f32 = 0, y: f32 = 0 } = undefined;

    var fps: f32 = 0;

    // var font: c_int = -1;
};

export fn init() void {
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });

    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0.50, .g = 0.51, .b = 0.54, .a = 1.0 },
    };

    state.vg = Nvg.sokol.init(state.allocator, .{
        .anti_alias = true,
        .stencil_strokes = true,
    }) catch |err| {
        std.log.err("Nvg init failed: {}", .{err});
        std.process.exit(1);
    };
    state.font = state.vg.createFontMem("roboto", font_data);

    std.log.info("Backend: {}", .{sg.queryBackend()});
    // if (!state.keyboard.init(.{
    //     .on_output = onKeyboardOutput,
    //     // .theme = .light,
    //     // .font_data = @embedFile("assets/helvetica-neue-5/HelveticaNeueMedium.otf"),
    // }, state.vg.?)) return;
    // state.keyboard.setVisible(true);
    // state.keyboard.setTheme(.);
    // state.keyboard.setVisible(false);
    state.text.appendSlice(state.allocator, "hello\x00") catch {
        std.log.info("allocator appendSlice failed", .{});
    };
}

// fn onKeyboardOutput(user_data: ?*anyopaque, out: vk.VirtualKeyboard.Output) void {
//     _ = user_data;
//     switch (out) {
//         .text => |ch| {
//             appendCodepoint(&state.text, state.allocator, ch) catch {
//                 std.log.info("Failed Append code point", .{});
//             };
//         },
//         .backspace => {
//             popCodepoint(&state.text, state.allocator);
//         },
//         .enter => std.log.info("Text: {s}\n", .{state.text.items}),
//         .tab => {
//             _ = state.text.pop();
//             state.text.appendSlice(state.allocator, "    \x00") catch {
//                 std.log.info("Failed Tab", .{});
//             };
//         },
//         .space => {
//             _ = state.text.pop();
//             state.text.appendSlice(state.allocator, " \x00") catch {
//                 std.log.info("Failed Space", .{});
//             };
//         },
//     }
// }

fn updateFPS() void {
    const dt: f32 = @floatCast(sapp.frameDuration()); // seconds

    const fps = 1.0 / dt;

    state.fps = state.fps * 0.9 + fps * 0.1;

    state.frame_times[state.frame_index] = dt; // store seconds
    state.frame_index = (state.frame_index + 1) % MAX_SAMPLES;
}

export fn event(ev: [*c]const sapp.Event) void {
    // _ = state.keyboard.handleSappEvent(ev);
    const h: f32 = @floatFromInt(sapp.height());

    state.mouse.x = ev.*.mouse_x;
    state.mouse.y = ev.*.mouse_y;

    if (ev.*.type == .TOUCHES_ENDED) {
        const touches = ev.*.touches;
        if (touches[0].pos_y < h / 2)
            std.log.info("Touched", .{});
        // state.keyboard.toggleVisible();
    }
    if (ev.*.type == .KEY_DOWN and ev.*.key_code == .SPACE) {
        std.log.info("space", .{});
        // state.keyboard.toggleVisible();
        // state.keyboard.setVisible(!state.keyboard.visible);
    }
}

export fn frame() void {
    state.t += 0.016;
    // state.keyboard.update(@floatCast(sapp.frameDuration() * 1000));
    updateFPS();
    const dpi = sapp.dpiScale();
    const win_w = sapp.widthf();
    const win_h = sapp.heightf();

    sg.beginPass(.{
        .action = state.pass_action,
        .swapchain = sglue.swapchain(),
    });

    const vg = state.vg;
    // sg.resetStateCache();
    vg.beginFrame(win_w, win_h, dpi);
    vg.resetScissor();
    vg.beginPath();
    vg.rect(state.mouse.x, state.mouse.y, 200, 100);
    vg.fillColor(Nvg.rgba(255, 0, 0, 255));
    vg.fill();
    // state.vg.scale(2, 2);

    const place = 120;
    vg.fontSize(place);
    vg.fontFace("roboto");
    vg.fillColor(Nvg.rgba(255, 255, 255, 255));
    _ = vg.text(20, 200, state.text.items);

    drawGraph(10, 10);

    vg.endFrame();

    sg.endPass();
    sg.commit();
}

export fn cleanup() void {
    state.vg.deinit(); // free NanoVG/internal allocations first
    state.text.deinit(state.allocator); // free your own ArrayList
    sg.shutdown(); // then sokol
    std.debug.assert(state.gpa.deinit() == .ok);
}

pub fn main() void {
    sapp.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .event_cb = event,
        .width = 640,
        .height = 480,
        .swap_interval = 0,
        .window_title = "NanoVG quick start",
        .icon = .{ .sokol_default = true },
        .logger = .{ .func = slog.func },
        .win32 = .{ .console_attach = true },
    });
}

fn drawGraph(x: f32, y: f32) void {
    const w: f32 = 200;
    const h: f32 = 60;

    const vg = state.vg;

    // background
    vg.beginPath();
    vg.rect(x, y, w, h);
    vg.fillColor(Nvg.rgba(0, 0, 0, 180));
    vg.fill();

    // graph line
    vg.beginPath();

    for (0..MAX_SAMPLES) |i| {
        const idx = (state.frame_index + i) % MAX_SAMPLES;
        const t = state.frame_times[idx]; // ms

        const vx = x + (@as(f32, @floatFromInt(i)) / MAX_SAMPLES) * w;
        const vy = y + h - (t / 0.033) * h; // 0.033s ≈ 30 FPS

        if (i == 0) {
            vg.moveTo(vx, vy);
        } else {
            vg.lineTo(vx, vy);
        }
    }

    vg.strokeColor(Nvg.rgba(0, 255, 0, 255));
    vg.strokeWidth(2);
    vg.stroke();

    // FPS text
    var buf: [64]u8 = undefined;
    const fps_text = std.fmt.bufPrintSentinel(&buf, "FPS: {d:.3}", .{state.fps}, 0) catch unreachable;

    vg.fontSize(18);
    vg.fontFace("roboto");
    vg.fillColor(Nvg.rgba(255, 255, 255, 255));
    _ = vg.text(x + 5, y + 20, fps_text);
}

fn appendCodepoint(text: *std.ArrayList(u8), allocator: std.mem.Allocator, cp: u21) !void {
    if (text.items.len > 0 and text.items[text.items.len - 1] == 0) {
        _ = text.pop();
    }

    var buf: [4]u8 = undefined;
    const n = try std.unicode.utf8Encode(cp, &buf);
    try text.appendSlice(allocator, buf[0..n]);
    try text.append(allocator, 0);
}

fn popCodepoint(text: *std.ArrayList(u8), allocator: std.mem.Allocator) void {
    if (text.items.len == 0) return;

    if (text.items.len > 0 and text.items[text.items.len - 1] == 0) {
        _ = text.pop();
    }

    while (text.items.len > 0) {
        const b = text.items[text.items.len - 1];
        _ = text.pop();
        if ((b & 0b1100_0000) != 0b1000_0000) break;
    }

    if (text.items.len == 0 or text.items[text.items.len - 1] != 0) {
        text.append(allocator, 0) catch {};
    }
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
        .window_title = "NanoVG quick start",
        .icon = .{ .sokol_default = true },
        .logger = .{ .func = slog.func },
        .win32 = .{ .console_attach = true },
    };
}
