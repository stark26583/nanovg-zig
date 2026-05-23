const std = @import("std");
const builtin = @import("builtin");

const sokol = @import("sokol");
const sg = sokol.gfx;
const stime = sokol.time;
const sapp = sokol.app;
const sglue = sokol.glue;
const slog = sokol.log;

const nvg = @import("nanovg");

var prng: std.Random.DefaultPrng = undefined;
var random: std.Random = undefined;

var cursor_shape: Shape = .star;

const state = struct {
    var gpa = std.heap.DebugAllocator(.{}){};
    var allocator: std.mem.Allocator =
        if (builtin.cpu.arch.isWasm())
            std.heap.c_allocator
        else
            gpa.allocator();

    var pass_action: sg.PassAction = .{
        .stencil = .{
            .load_action = .CLEAR,
            .clear_value = 0,
        },
    };

    var vg: nvg = undefined;

    var mouse_x: f32 = 0;
    var mouse_y: f32 = 0;
};

const Shape = enum {
    rect,
    circle,
    donut,
    star,
    heart,
    twitter_logo,

    fn path(shape: Shape, vg: nvg, r: f32) void {
        switch (shape) {
            .rect => vg.rect(-r, -r, 2 * r, 2 * r),
            .circle => vg.circle(0, 0, r),
            .donut => pathDonut(vg, r),
            .star => pathStar(vg, 5, 0.5 * r, r),
            .heart => {
                vg.translate(-r, -r);
                pathHeart(vg, 2 * r, 2 * r);
                vg.translate(r, r);
            },
            .twitter_logo => {
                vg.translate(-r, -r);
                pathTwitterLogo(vg, 2 * r, 2 * r);
                vg.translate(r, r);
            },
        }
    }
};

const cols = 4;
const rows = 4;

const SpinningShape = struct {
    shape: Shape,
    angle: f32,
    angular_vel: f32 = 0,
};

var shapes: [rows][cols]SpinningShape = undefined;

fn scaleToFit(vg: nvg, w: f32, h: f32, target_w: f32, target_h: f32) void {
    const sx = target_w / w;
    const sy = target_h / h;
    const s = @min(sx, sy);

    vg.translate(0.5 * target_w, 0.5 * target_h);
    vg.scale(s, s);
    vg.translate(-0.5 * w, -0.5 * h);
}

fn pathStar(vg: nvg, n: usize, inr: f32, outr: f32) void {
    const to_angle = 2 * std.math.pi / @as(f32, @floatFromInt(n));

    for (0..n) |i| {
        const fi: f32 = @floatFromInt(i);

        const a0 = fi * to_angle;
        const a1 = (fi + 0.5) * to_angle;

        if (i == 0)
            vg.moveTo(outr * @sin(a0), -outr * @cos(a0))
        else
            vg.lineTo(outr * @sin(a0), -outr * @cos(a0));

        vg.lineTo(inr * @sin(a1), -inr * @cos(a1));
    }

    vg.closePath();
}

fn pathDonut(vg: nvg, r: f32) void {
    vg.circle(0, 0, r);
    vg.pathWinding(.cw);
    vg.circle(0, 0, 0.4 * r);
}

fn pathHeart(vg: nvg, w: f32, h: f32) void {
    vg.save();
    defer vg.restore();

    const min_x = 9;
    const min_y = 11;
    const max_x = 41;
    const max_y = 38;

    scaleToFit(vg, max_x - min_x, max_y - min_y, w, h);

    vg.translate(-min_x, -min_y);

    const heart = nvg.Path{
        .verbs = &.{
            .move,
            .bezier,
            .bezier,
            .bezier,
            .bezier,
            .bezier,
            .bezier,
        },
        .points = &.{
            25,   38,
            20,   34,
            9,    27,
            9,    19,
            9,    14.5,
            12.5, 11,
            17,   11,
            20,   11,
            23,   12,
            25,   15.5,
            27,   12,
            30,   11,
            33,   11,
            37.5, 11,
            41,   14.5,
            41,   19,
            41,   27,
            30,   34,
            25,   38,
        },
    };

    vg.addPath(heart);
}

fn pathTwitterLogo(vg: nvg, w: f32, h: f32) void {
    vg.save();
    defer vg.restore();

    scaleToFit(vg, 248, 204, w, h);

    const twitter_logo = nvg.Path{
        .verbs = &.{
            .move,
            .bezier,
            .bezier,
            .bezier,
            .bezier,
            .bezier,
            .bezier,
            .bezier,
            .bezier,
            .bezier,
            .bezier,
            .bezier,
            .bezier,
            .bezier,
            .bezier,
            .bezier,
            .bezier,
            .bezier,
        },

        .points = &.{
            221.95, 51.29,
            222.1,  53.46,
            222.1,  55.63,
            222.1,  57.82,
            222.1,  124.55,
            171.3,  201.51,
            78.41,  201.51,
            50.97,  201.51,
            24.1,   193.65,
            1,      178.83,
            4.99,   179.31,
            9,      179.55,
            13.02,  179.56,
            35.76,  179.58,
            57.85,  171.95,
            75.74,  157.9,
            54.13,  157.49,
            35.18,  143.4,
            28.56,  122.83,
            36.13,  124.29,
            43.93,  123.99,
            51.36,  121.96,
            27.8,   117.2,
            10.85,  96.5,
            10.85,  72.46,
            17.87,  75.73,
            25.73,  77.9,
            33.77,  78.14,
            11.58,  63.31,
            4.74,   33.79,
            18.14,  10.71,
            43.78,  42.26,
            81.61,  61.44,
            122.22, 63.47,
            118.15, 45.93,
            123.71, 27.55,
            136.83, 15.22,
            157.17, -3.9,
            189.16, -2.92,
            208.28, 17.41,
            219.59, 15.18,
            230.43, 11.03,
            240.35, 5.15,
            236.58, 16.84,
            228.69, 26.77,
            218.15, 33.08,
            228.16, 31.9,
            237.94, 29.22,
            247.15, 25.13,
            240.37, 35.29,
            231.83, 44.14,
            221.95, 51.29,
        },
    };

    vg.addPath(twitter_logo);
}

fn spinShapes(w: f32, h: f32, mx: f32, my: f32, dt: f32) void {
    const sx = w / cols;
    const sy = h / rows;

    for (&shapes, 0..) |*shapes_row, row| {
        for (shapes_row, 0..) |*shape, col| {
            const x: f32 = @floatFromInt(col);
            const y: f32 = @floatFromInt(row);

            const dx = sx * (x + 0.5) - mx;
            const dy = sy * (y + 0.5) - my;

            const d = @max(1000, dx * dx + dy * dy);

            const sign_dx: f32 = @floatFromInt(std.math.sign(dx));
            shape.angular_vel += sign_dx * 10000 / d * dt;
            shape.angle += shape.angular_vel * dt;
            const sign_av: f32 = @floatFromInt(std.math.sign(shape.angular_vel));
            shape.angular_vel -= sign_av * dt;
        }
    }
}

fn pathShapes(vg: nvg, w: f32, h: f32) void {
    const sx = w / cols;
    const sy = h / rows;
    const r = 0.4 * @min(sx, sy);

    for (shapes, 0..) |shapes_row, row| {
        for (shapes_row, 0..) |shape, col| {
            const x: f32 = @floatFromInt(col);
            const y: f32 = @floatFromInt(row);

            vg.save();

            vg.translate(sx * (x + 0.5), sy * (y + 0.5));
            vg.rotate(shape.angle);

            shape.shape.path(vg, r);

            vg.restore();
        }
    }
}

export fn init() void {
    prng = .init(4);
    random = prng.random();

    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{
            .func = slog.func,
        },
    });
    stime.setup();

    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0.3, .g = 0.3, .b = 0.32, .a = 1.0 },
    };

    state.vg = nvg.sokol.init(state.allocator, .{
        .anti_alias = true,
        .stencil_strokes = true,
        .debug = true,
    }) catch |err| {
        std.log.err("NanoVG init failed: {}", .{err});
        std.process.exit(1);
    };

    for (&shapes) |*row| {
        for (row) |*cell| {
            cell.* = .{
                .shape = random.enumValue(Shape),
                .angle = random.float(f32) * std.math.tau,
            };
        }
    }

    std.log.info("Backend: {}", .{sg.queryBackend()});
}

export fn event(ev: [*c]const sapp.Event) void {
    state.mouse_x = ev.*.mouse_x;
    state.mouse_y = ev.*.mouse_y;

    switch (ev.*.type) {
        .MOUSE_DOWN => {
            if (ev.*.mouse_button == .LEFT) {
                cursor_shape = random.enumValue(Shape);
            }
        },

        .KEY_UP => {
            switch (ev.*.key_code) {
                .ESCAPE => sapp.quit(),
                else => {},
            }
        },

        else => {},
    }
}

export fn frame() void {
    const t32: f32 = @floatCast(stime.sec(stime.now()));

    const win_width = sapp.widthf();
    const win_height = sapp.heightf();
    const px_ratio = sapp.dpiScale();

    sg.beginPass(.{
        .action = state.pass_action,
        .swapchain = sglue.swapchain(),
    });

    const vg = state.vg;

    vg.beginFrame(win_width, win_height, px_ratio);

    spinShapes(
        win_width,
        win_height,
        state.mouse_x,
        state.mouse_y,
        @floatCast(sapp.frameDuration()),
    );

    vg.beginPath();

    vg.save();
    vg.translate(state.mouse_x, state.mouse_y);
    cursor_shape.path(vg, 100);
    vg.restore();

    pathShapes(vg, win_width, win_height);

    vg.strokeColor(nvg.rgbf(1, 1, 1));
    vg.strokeWidth(2);
    vg.stroke();

    vg.beginPath();

    vg.save();
    vg.translate(state.mouse_x, state.mouse_y);
    cursor_shape.path(vg, 100);
    vg.restore();

    vg.clip();

    pathShapes(vg, win_width, win_height);

    vg.fill();

    vg.translate(500, 300);

    vg.beginPath();

    vg.save();

    const s = 1.1 + @cos(4 * t32);

    vg.scale(s, s);

    Shape.heart.path(vg, 100);

    vg.restore();

    vg.strokeColor(nvg.rgb(0, 0, 0));
    vg.strokeWidth(8);
    vg.stroke();

    vg.fillColor(nvg.rgbf(1, 0, 0));
    vg.fill();

    vg.clip();

    vg.rotate(3 * t32);

    Shape.star.path(vg, 100);

    vg.stroke();

    vg.fillColor(nvg.rgbf(1, 1, 0));
    vg.fill();

    vg.endFrame();

    sg.endPass();
    sg.commit();
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

        .window_title = "NanoVG Shapes",

        .icon = .{
            .sokol_default = true,
        },

        .logger = .{
            .func = slog.func,
        },

        .win32 = .{
            .console_attach = true,
        },
    });
}
