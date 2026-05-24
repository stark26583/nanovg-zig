const std = @import("std");
const sg = @import("sokol").gfx;
const nvg = @import("nanovg.zig");
const internal = @import("internal.zig");
const shaders = @import("shader/snvg_shader.zig");

pub const Options = struct {
    anti_alias: bool = false,
    stencil_strokes: bool = false,
    debug: bool = false,
};

pub const Desc = struct {
    allocator: std.mem.Allocator,
};

const ShaderType = enum(u8) {
    fillgrad,
    fillimg,
    simple,
    img,
    blur_image,
};

const CallType = enum(u8) {
    none = 0,
    fill,
    convexfill,
    stroke,
    triangles,
};

const Texture = struct {
    id: i32 = 0,
    img: sg.Image = .{},
    view: sg.View = .{},
    sampler: sg.Sampler = .{},
    width: u32 = 0,
    height: u32 = 0,
    type_: internal.TextureType = .none,
    flags: nvg.ImageFlags = .{},
    dirty: bool = false,
    pending_data: ?[]u8 = null,
};

const Call = struct {
    type_: CallType = .none,
    image: i32 = 0,
    path_offset: usize = 0,
    path_count: usize = 0,
    triangle_offset: usize = 0,
    triangle_count: usize = 0,
    uniform_offset: usize = 0,
};

const PathItem = struct {
    fill_offset: usize = 0,
    fill_count: usize = 0,
    stroke_offset: usize = 0,
    stroke_count: usize = 0,
};

const FragUniforms = extern struct {
    scissorMat: [12]f32,
    paintMat: [12]f32,
    innerCol: [4]f32,
    outerCol: [4]f32,
    scissorExt: [2]f32,
    scissorScale: [2]f32,
    extent: [2]f32,
    radius: f32,
    feather: f32,
    strokeMult: f32,
    strokeThr: f32,
    texType: f32,
    shader_type: f32,
    blurDir: [2]f32,
};

const ArrayList = std.array_list.Managed;

const Context = struct {
    allocator: std.mem.Allocator,
    options: Options,
    texture_id: i32 = 0,

    shader: sg.Shader = .{},
    pip_fill: sg.Pipeline = .{},
    pip_fill_stencil: sg.Pipeline = .{},
    pip_fill_antialias: sg.Pipeline = .{},
    pip_fill_draw: sg.Pipeline = .{},
    pip_stroke: sg.Pipeline = .{},
    pip_stroke_stencil: sg.Pipeline = .{},
    pip_stroke_antialias: sg.Pipeline = .{},
    pip_stroke_clear: sg.Pipeline = .{},
    pip_triangles: sg.Pipeline = .{},
    vbuf: sg.Buffer = .{},
    default_sampler: sg.Sampler = .{},
    dummy_tex: sg.Image = .{},
    dummy_view: sg.View = .{},
    bindings: sg.Bindings = .{},

    view: [2]f32 = .{ 0, 0 },

    textures: ArrayList(Texture),
    calls: ArrayList(Call),
    paths: ArrayList(PathItem),
    verts: ArrayList(internal.Vertex),
    uniforms: ArrayList(FragUniforms),
};

fn maxi(a: usize, b: usize) usize {
    return if (a > b) a else b;
}

fn fanToTriCount(fan_count: usize) usize {
    if (fan_count < 3) return 0;
    return (fan_count - 2) * 3;
}

fn fanToTriangles(dst: []internal.Vertex, src: []const internal.Vertex, fan_count: usize) usize {
    if (fan_count < 3) return 0;
    var tri_count: usize = 0;
    var i: usize = 2;
    while (i < fan_count) : (i += 1) {
        dst[tri_count] = src[0];
        tri_count += 1;
        dst[tri_count] = src[i - 1];
        tri_count += 1;
        dst[tri_count] = src[i];
        tri_count += 1;
    }
    return tri_count;
}

fn zeroFrag() FragUniforms {
    return std.mem.zeroes(FragUniforms);
}

fn allocTexture(ctx: *Context) !*Texture {
    for (ctx.textures.items) |*tex| {
        if (tex.id == 0) {
            tex.* = .{};
            ctx.texture_id += 1;
            tex.id = ctx.texture_id;
            return tex;
        }
    }

    const tex = try ctx.textures.addOne();
    tex.* = .{};
    ctx.texture_id += 1;
    tex.id = ctx.texture_id;
    return tex;
}

fn destroyTextureResources(ctx: *Context, tex: *Texture) void {
    if (tex.img.id != sg.invalid_id) sg.destroyImage(tex.img);
    if (tex.view.id != sg.invalid_id) sg.destroyView(tex.view);
    if (tex.sampler.id != sg.invalid_id) sg.destroySampler(tex.sampler);
    if (tex.pending_data) |buf| ctx.allocator.free(buf);
    tex.* = .{};
}

fn findTexture(ctx: *Context, id: i32) ?*Texture {
    for (ctx.textures.items) |*tex| {
        if (tex.id == id) return tex;
    }
    return null;
}

fn deleteTexture(ctx: *Context, id: i32) bool {
    for (ctx.textures.items) |*tex| {
        if (tex.id == id) {
            destroyTextureResources(ctx, tex);
            return true;
        }
    }
    return false;
}

fn allocCall(ctx: *Context) !*Call {
    const call = try ctx.calls.addOne();
    call.* = .{};
    return call;
}

fn allocPaths(ctx: *Context, n: usize) !usize {
    const start = ctx.paths.items.len;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const item = try ctx.paths.addOne();
        item.* = .{};
    }
    return start;
}

fn allocVerts(ctx: *Context, n: usize) !usize {
    const start = ctx.verts.items.len;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const v = try ctx.verts.addOne();
        v.* = std.mem.zeroes(internal.Vertex);
    }
    return start;
}

fn allocFragUniforms(ctx: *Context, n: usize) !usize {
    const start = ctx.uniforms.items.len;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const u = try ctx.uniforms.addOne();
        u.* = zeroFrag();
    }
    return start;
}

fn fragUniformPtr(ctx: *Context, idx: usize) *FragUniforms {
    return &ctx.uniforms.items[idx];
}

fn xformToMat3x4(m3: *[12]f32, t: *const [6]f32) void {
    m3[0] = t[0];
    m3[1] = t[1];
    m3[2] = 0.0;
    m3[3] = 0.0;
    m3[4] = t[2];
    m3[5] = t[3];
    m3[6] = 0.0;
    m3[7] = 0.0;
    m3[8] = t[4];
    m3[9] = t[5];
    m3[10] = 1.0;
    m3[11] = 0.0;
}

fn premulColor(c: nvg.Color) nvg.Color {
    return .{
        .r = c.r * c.a,
        .g = c.g * c.a,
        .b = c.b * c.a,
        .a = c.a,
    };
}

fn convertPaint(
    ctx: *Context,
    frag: *FragUniforms,
    paint: *const nvg.Paint,
    scissor: *const internal.Scissor,
    width: f32,
    fringe: f32,
    stroke_thr: f32,
) void {
    var invxform: [6]f32 = .{ 0, 0, 0, 0, 0, 0 };
    const inner = premulColor(paint.inner_color);
    const outer = premulColor(paint.outer_color);

    frag.* = zeroFrag();
    frag.innerCol = .{ inner.r, inner.g, inner.b, inner.a };
    frag.outerCol = .{ outer.r, outer.g, outer.b, outer.a };
    frag.extent = .{ paint.extent[0], paint.extent[1] };
    frag.strokeMult = (width * 0.5 + fringe * 0.5) / fringe;
    frag.strokeThr = stroke_thr;

    if (scissor.extent[0] < -0.5 or scissor.extent[1] < -0.5) {
        frag.scissorExt = .{ 1.0, 1.0 };
        frag.scissorScale = .{ 1.0, 1.0 };
    } else {
        _ = nvg.transformInverse(&invxform, &scissor.xform);
        xformToMat3x4(&frag.scissorMat, &invxform);
        frag.scissorExt = .{ scissor.extent[0], scissor.extent[1] };
        frag.scissorScale = .{
            @sqrt(scissor.xform[0] * scissor.xform[0] + scissor.xform[2] * scissor.xform[2]) / fringe,
            @sqrt(scissor.xform[1] * scissor.xform[1] + scissor.xform[3] * scissor.xform[3]) / fringe,
        };
    }

    if (paint.image.handle != 0) {
        if (findTexture(ctx, paint.image.handle)) |tex| {
            if (tex.flags.flip_y) {
                var m1: [6]f32 = .{ 0, 0, 0, 0, 0, 0 };
                var m2: [6]f32 = .{ 0, 0, 0, 0, 0, 0 };
                nvg.transformTranslate(&m1, 0.0, frag.extent[1] * 0.5);
                nvg.transformMultiply(&m1, &paint.xform);
                nvg.transformScale(&m2, 1.0, -1.0);
                nvg.transformMultiply(&m2, &m1);
                nvg.transformTranslate(&m1, 0.0, -frag.extent[1] * 0.5);
                nvg.transformMultiply(&m1, &m2);
                _ = nvg.transformInverse(&invxform, &m1);
            } else {
                _ = nvg.transformInverse(&invxform, &paint.xform);
            }

            if (paint.blur[0] > 0 or paint.blur[1] > 0) {
                frag.shader_type = @floatFromInt(@intFromEnum(ShaderType.blur_image));
                frag.blurDir = paint.blur;
            } else {
                frag.shader_type = @floatFromInt(@intFromEnum(ShaderType.fillimg));
            }
            if (tex.type_ == .rgba) {
                frag.texType = if (tex.flags.premultiplied) 0.0 else 1.0;
            } else {
                frag.texType = 2.0;
            }
        } else {
            _ = nvg.transformInverse(&invxform, &paint.xform);
            frag.shader_type = @floatFromInt(@intFromEnum(ShaderType.fillimg));
        }
    } else {
        frag.shader_type = @floatFromInt(@intFromEnum(ShaderType.fillgrad));
        frag.radius = paint.radius;
        frag.feather = paint.feather;
        _ = nvg.transformInverse(&invxform, &paint.xform);
    }

    xformToMat3x4(&frag.paintMat, &invxform);
}

fn flushTextureUpdates(ctx: *Context) void {
    for (ctx.textures.items) |*tex| {
        if (!tex.dirty) continue;
        const data = tex.pending_data orelse continue;
        const bpp: usize = if (tex.type_ == .rgba) 4 else 1;
        const pitch: usize = @as(usize, tex.width) * bpp;
        const total_size: usize = @as(usize, tex.height) * pitch;

        var img_data: sg.ImageData = .{};
        img_data.mip_levels[0] = .{ .ptr = data.ptr, .size = total_size };
        sg.updateImage(tex.img, img_data);
        tex.dirty = false;
    }
}

fn setUniforms(ctx: *Context, uniform_offset: usize, image: i32) void {
    const frag = fragUniformPtr(ctx, uniform_offset);

    const vs_params = shaders.VsParams{
        .viewSize = .{ .x = ctx.view[0], .y = ctx.view[1] },
    };
    sg.applyUniforms(shaders.UB_vs_params, sg.Range{ .ptr = &vs_params, .size = @sizeOf(@TypeOf(vs_params)) });

    const fs_params = shaders.FsParams{
        .scissorMat0 = .{ .x = frag.scissorMat[0], .y = frag.scissorMat[1], .z = frag.scissorMat[2], .w = frag.scissorMat[3] },
        .scissorMat1 = .{ .x = frag.scissorMat[4], .y = frag.scissorMat[5], .z = frag.scissorMat[6], .w = frag.scissorMat[7] },
        .scissorMat2 = .{ .x = frag.scissorMat[8], .y = frag.scissorMat[9], .z = frag.scissorMat[10], .w = frag.scissorMat[11] },
        .paintMat0 = .{ .x = frag.paintMat[0], .y = frag.paintMat[1], .z = frag.paintMat[2], .w = frag.paintMat[3] },
        .paintMat1 = .{ .x = frag.paintMat[4], .y = frag.paintMat[5], .z = frag.paintMat[6], .w = frag.paintMat[7] },
        .paintMat2 = .{ .x = frag.paintMat[8], .y = frag.paintMat[9], .z = frag.paintMat[10], .w = frag.paintMat[11] },
        .innerCol = .{ .x = frag.innerCol[0], .y = frag.innerCol[1], .z = frag.innerCol[2], .w = frag.innerCol[3] },
        .outerCol = .{ .x = frag.outerCol[0], .y = frag.outerCol[1], .z = frag.outerCol[2], .w = frag.outerCol[3] },
        .scissorExtScale = .{ .x = frag.scissorExt[0], .y = frag.scissorExt[1], .z = frag.scissorScale[0], .w = frag.scissorScale[1] },
        .extentRadiusFeather = .{ .x = frag.extent[0], .y = frag.extent[1], .z = frag.radius, .w = frag.feather },
        .params = .{ .x = frag.strokeMult, .y = frag.strokeThr, .z = frag.texType, .w = frag.shader_type },
        .blurDir = .{ .x = frag.blurDir[0], .y = frag.blurDir[1], .z = 0.0, .w = 0.0 }, // NEW
    };
    sg.applyUniforms(shaders.UB_fs_params, sg.Range{ .ptr = &fs_params, .size = @sizeOf(@TypeOf(fs_params)) });

    if (image != 0) {
        if (findTexture(ctx, image)) |tex| {
            ctx.bindings.views[shaders.VIEW_tex] = tex.view;
            ctx.bindings.samplers[shaders.SMP_smp] = tex.sampler;
        } else {
            ctx.bindings.views[shaders.VIEW_tex] = ctx.dummy_view;
            ctx.bindings.samplers[shaders.SMP_smp] = ctx.default_sampler;
        }
    } else {
        ctx.bindings.views[shaders.VIEW_tex] = ctx.dummy_view;
        ctx.bindings.samplers[shaders.SMP_smp] = ctx.default_sampler;
    }

    sg.applyBindings(ctx.bindings);
}

fn drawPathRangeFill(paths: []const PathItem) void {
    for (paths) |path| {
        if (path.fill_count > 0) sg.draw(@intCast(path.fill_offset), @intCast(path.fill_count), 1);
    }
}

fn drawPathRangeStroke(paths: []const PathItem) void {
    for (paths) |path| {
        if (path.stroke_count > 0) sg.draw(@intCast(path.stroke_offset), @intCast(path.stroke_count), 1);
    }
}

fn fillInternal(ctx: *Context, call: *const Call) void {
    const paths = ctx.paths.items[call.path_offset .. call.path_offset + call.path_count];

    sg.applyPipeline(ctx.pip_fill_stencil);
    setUniforms(ctx, call.uniform_offset, 0);
    drawPathRangeFill(paths);

    if (ctx.options.anti_alias) {
        sg.applyPipeline(ctx.pip_fill_antialias);
        setUniforms(ctx, call.uniform_offset + 1, call.image);
        drawPathRangeStroke(paths);
    }

    sg.applyPipeline(ctx.pip_fill_draw);
    setUniforms(ctx, call.uniform_offset + 1, call.image);
    sg.draw(@intCast(call.triangle_offset), @intCast(call.triangle_count), 1);
}

fn convexFillInternal(ctx: *Context, call: *const Call) void {
    const paths = ctx.paths.items[call.path_offset .. call.path_offset + call.path_count];

    sg.applyPipeline(ctx.pip_fill);
    setUniforms(ctx, call.uniform_offset, call.image);
    drawPathRangeFill(paths);

    if (ctx.options.anti_alias) {
        sg.applyPipeline(ctx.pip_stroke);
        setUniforms(ctx, call.uniform_offset, call.image);
        drawPathRangeStroke(paths);
    }
}

fn strokeInternal(ctx: *Context, call: *const Call) void {
    const paths = ctx.paths.items[call.path_offset .. call.path_offset + call.path_count];

    if (ctx.options.stencil_strokes) {
        sg.applyPipeline(ctx.pip_stroke_stencil);
        setUniforms(ctx, call.uniform_offset + 1, call.image);
        drawPathRangeStroke(paths);

        sg.applyPipeline(ctx.pip_stroke_antialias);
        setUniforms(ctx, call.uniform_offset, call.image);
        drawPathRangeStroke(paths);

        sg.applyPipeline(ctx.pip_stroke_clear);
        setUniforms(ctx, call.uniform_offset, 0);
        drawPathRangeStroke(paths);
    } else {
        sg.applyPipeline(ctx.pip_stroke);
        setUniforms(ctx, call.uniform_offset, call.image);
        drawPathRangeStroke(paths);
    }
}

fn trianglesInternal(ctx: *Context, call: *const Call) void {
    sg.applyPipeline(ctx.pip_triangles);
    setUniforms(ctx, call.uniform_offset, call.image);
    sg.draw(@intCast(call.triangle_offset), @intCast(call.triangle_count), 1);
}

fn renderCreate(uptr: *anyopaque) anyerror!void {
    const ctx: *Context = @ptrCast(@alignCast(uptr));

    ctx.shader = sg.makeShader(shaders.snvgShaderDesc(sg.queryBackend()));
    if (ctx.shader.id == sg.invalid_id) return error.ShaderCreationFailed;

    var pip_desc: sg.PipelineDesc = .{};
    pip_desc.shader = ctx.shader;
    pip_desc.color_count = 1;
    pip_desc.layout.attrs[shaders.ATTR_snvg_vertex].format = .FLOAT2;
    pip_desc.layout.attrs[shaders.ATTR_snvg_tcoord].format = .FLOAT2;
    pip_desc.colors[0].write_mask = .RGBA;
    pip_desc.colors[0].blend = .{
        .enabled = true,
        .src_factor_rgb = .ONE,
        .dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
        .src_factor_alpha = .ONE,
        .dst_factor_alpha = .ONE_MINUS_SRC_ALPHA,
    };
    pip_desc.depth.pixel_format = .DEPTH_STENCIL;
    pip_desc.stencil.enabled = false;
    pip_desc.primitive_type = .TRIANGLES;
    pip_desc.cull_mode = .BACK;
    pip_desc.face_winding = .CCW;
    pip_desc.label = "snvg-pip-fill";
    ctx.pip_fill = sg.makePipeline(pip_desc);

    pip_desc.label = "snvg-pip-triangles";
    ctx.pip_triangles = sg.makePipeline(pip_desc);

    pip_desc.colors[0].write_mask = .NONE;
    pip_desc.stencil = .{
        .enabled = true,
        .front = .{
            .compare = .ALWAYS,
            .fail_op = .KEEP,
            .depth_fail_op = .KEEP,
            .pass_op = .INCR_WRAP,
        },
        .back = .{
            .compare = .ALWAYS,
            .fail_op = .KEEP,
            .depth_fail_op = .KEEP,
            .pass_op = .DECR_WRAP,
        },
        .read_mask = 0xff,
        .write_mask = 0xff,
        .ref = 0,
    };
    pip_desc.cull_mode = .NONE;
    pip_desc.label = "snvg-pip-fill-stencil";
    ctx.pip_fill_stencil = sg.makePipeline(pip_desc);

    pip_desc.primitive_type = .TRIANGLE_STRIP;
    pip_desc.colors[0].write_mask = .RGBA;
    pip_desc.colors[0].blend = .{
        .enabled = true,
        .src_factor_rgb = .ONE,
        .dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
        .src_factor_alpha = .ONE,
        .dst_factor_alpha = .ONE_MINUS_SRC_ALPHA,
    };
    pip_desc.stencil = .{
        .enabled = true,
        .front = .{
            .compare = .EQUAL,
            .fail_op = .KEEP,
            .depth_fail_op = .KEEP,
            .pass_op = .KEEP,
        },
        .back = .{
            .compare = .EQUAL,
            .fail_op = .KEEP,
            .depth_fail_op = .KEEP,
            .pass_op = .KEEP,
        },
        .read_mask = 0xff,
        .write_mask = 0xff,
        .ref = 0,
    };
    pip_desc.cull_mode = .BACK;
    pip_desc.label = "snvg-pip-fill-antialias";
    ctx.pip_fill_antialias = sg.makePipeline(pip_desc);

    pip_desc.stencil = .{
        .enabled = true,
        .front = .{
            .compare = .NOT_EQUAL,
            .fail_op = .ZERO,
            .depth_fail_op = .ZERO,
            .pass_op = .ZERO,
        },
        .back = .{
            .compare = .NOT_EQUAL,
            .fail_op = .ZERO,
            .depth_fail_op = .ZERO,
            .pass_op = .ZERO,
        },
        .read_mask = 0xff,
        .write_mask = 0xff,
        .ref = 0,
    };
    pip_desc.label = "snvg-pip-fill-draw";
    ctx.pip_fill_draw = sg.makePipeline(pip_desc);

    pip_desc.stencil.enabled = false;
    pip_desc.label = "snvg-pip-stroke";
    ctx.pip_stroke = sg.makePipeline(pip_desc);

    pip_desc.stencil = .{
        .enabled = true,
        .front = .{
            .compare = .EQUAL,
            .fail_op = .KEEP,
            .depth_fail_op = .KEEP,
            .pass_op = .INCR_CLAMP,
        },
        .back = .{
            .compare = .EQUAL,
            .fail_op = .KEEP,
            .depth_fail_op = .KEEP,
            .pass_op = .INCR_CLAMP,
        },
        .read_mask = 0xff,
        .write_mask = 0xff,
        .ref = 0,
    };
    pip_desc.label = "snvg-pip-stroke-stencil";
    ctx.pip_stroke_stencil = sg.makePipeline(pip_desc);

    pip_desc.stencil.front.compare = .EQUAL;
    pip_desc.stencil.back.compare = .EQUAL;
    pip_desc.stencil.front.pass_op = .KEEP;
    pip_desc.stencil.back.pass_op = .KEEP;
    pip_desc.label = "snvg-pip-stroke-antialias";
    ctx.pip_stroke_antialias = sg.makePipeline(pip_desc);

    pip_desc.colors[0].write_mask = .NONE;
    pip_desc.stencil = .{
        .enabled = true,
        .front = .{
            .compare = .ALWAYS,
            .fail_op = .ZERO,
            .depth_fail_op = .ZERO,
            .pass_op = .ZERO,
        },
        .back = .{
            .compare = .ALWAYS,
            .fail_op = .ZERO,
            .depth_fail_op = .ZERO,
            .pass_op = .ZERO,
        },
        .read_mask = 0xff,
        .write_mask = 0xff,
        .ref = 0,
    };
    pip_desc.label = "snvg-pip-stroke-clear";
    ctx.pip_stroke_clear = sg.makePipeline(pip_desc);

    ctx.vbuf = sg.makeBuffer(sg.BufferDesc{
        .usage = .{
            .vertex_buffer = true,
            .stream_update = true,
            .immutable = false,
        },
        .size = 65536 * @sizeOf(internal.Vertex),
        .label = "snvg-vbuf",
    });

    ctx.default_sampler = sg.makeSampler(sg.SamplerDesc{
        .min_filter = .LINEAR,
        .mag_filter = .LINEAR,
        .mipmap_filter = .NEAREST,
        .wrap_u = .CLAMP_TO_EDGE,
        .wrap_v = .CLAMP_TO_EDGE,
        .label = "snvg-sampler",
    });

    const white: u32 = 0xFFFFFFFF;
    var image_data = sg.ImageData{};
    image_data.mip_levels[0] = .{ .ptr = &white, .size = @sizeOf(u32) };
    ctx.dummy_tex = sg.makeImage(sg.ImageDesc{
        .width = 1,
        .height = 1,
        .pixel_format = .RGBA8,
        .usage = .{ .immutable = true },
        .data = image_data,
        .label = "snvg-dummy",
    });
    if (ctx.dummy_tex.id == sg.invalid_id) return error.ImageCreationFailed;

    ctx.dummy_view = sg.makeView(sg.ViewDesc{
        .texture = .{ .image = ctx.dummy_tex },
        .label = "snvg-dummy-view",
    });
    if (ctx.dummy_view.id == sg.invalid_id) return error.ViewCreationFailed;

    ctx.bindings.vertex_buffers[0] = ctx.vbuf;
    ctx.bindings.vertex_buffer_offsets[0] = 0;
}

fn renderCreateTexture(uptr: *anyopaque, tex_type: internal.TextureType, w: u32, h: u32, image_flags: nvg.ImageFlags, data: ?[]const u8) anyerror!i32 {
    const ctx: *Context = @ptrCast(@alignCast(uptr));
    const tex = try allocTexture(ctx);

    const fmt: sg.PixelFormat = switch (tex_type) {
        .rgba => .RGBA8,
        .alpha => .R8,
        .none => .RGBA8,
    };

    var img_desc: sg.ImageDesc = .{
        .width = @intCast(w),
        .height = @intCast(h),
        .pixel_format = fmt,
        .label = "snvg-texture",
    };

    if (data) |src| {
        img_desc.usage = .{ .immutable = true };
        const pitch: usize = if (tex_type == .rgba) @as(usize, w) * 4 else @as(usize, w);
        img_desc.data.mip_levels[0] = .{ .ptr = src.ptr, .size = @as(usize, h) * pitch };
    } else {
        img_desc.usage = .{ .immutable = false, .stream_update = true };
    }

    if (image_flags.generate_mipmaps) {
        img_desc.num_mipmaps = 0;
    }

    tex.img = sg.makeImage(img_desc);
    if (tex.img.id == sg.invalid_id) {
        tex.* = .{};
        return error.TextureCreationFailed;
    }

    tex.view = sg.makeView(sg.ViewDesc{
        .texture = .{ .image = tex.img },
        .label = "snvg-texture-view",
    });
    if (tex.view.id == sg.invalid_id) {
        destroyTextureResources(ctx, tex);
        return error.TextureCreationFailed;
    }

    var min_filter: sg.Filter = .LINEAR;
    var mag_filter: sg.Filter = .LINEAR;
    const mip_filter: sg.Filter = if (image_flags.generate_mipmaps) .LINEAR else .NEAREST;
    const wrap_u: sg.Wrap = if (image_flags.repeat_x) .REPEAT else .CLAMP_TO_EDGE;
    const wrap_v: sg.Wrap = if (image_flags.repeat_y) .REPEAT else .CLAMP_TO_EDGE;

    if (image_flags.nearest) {
        min_filter = .NEAREST;
        mag_filter = .NEAREST;
    }

    tex.sampler = sg.makeSampler(sg.SamplerDesc{
        .min_filter = min_filter,
        .mag_filter = mag_filter,
        .mipmap_filter = mip_filter,
        .min_lod = 0.0,
        .max_lod = if (image_flags.generate_mipmaps) 1000.0 else 0.0,
        .wrap_u = wrap_u,
        .wrap_v = wrap_v,
        .label = "snvg-sampler",
    });
    if (tex.sampler.id == sg.invalid_id) {
        destroyTextureResources(ctx, tex);
        return error.TextureCreationFailed;
    }

    tex.width = w;
    tex.height = h;
    tex.type_ = tex_type;
    tex.flags = image_flags;
    return tex.id;
}

fn renderDeleteTexture(uptr: *anyopaque, image: i32) void {
    const ctx: *Context = @ptrCast(@alignCast(uptr));
    _ = deleteTexture(ctx, image);
}

fn renderUpdateTexture(uptr: *anyopaque, image: i32, x: u32, y: u32, w: u32, h: u32, data: ?[]const u8) i32 {
    _ = x;
    _ = y;
    _ = w;
    _ = h;

    const ctx: *Context = @ptrCast(@alignCast(uptr));
    const tex = findTexture(ctx, image) orelse return 0;
    const src = data orelse return 0;
    const bpp: usize = if (tex.type_ == .rgba) 4 else 1;
    const data_size: usize = @as(usize, tex.width) * @as(usize, tex.height) * bpp;

    if (src.len < data_size) return 0;

    if (tex.pending_data == null) {
        tex.pending_data = ctx.allocator.alloc(u8, data_size) catch return 0;
    }

    if (tex.pending_data) |buf| {
        @memcpy(buf[0..data_size], src[0..data_size]);
        tex.dirty = true;
    }
    return 1;
}

fn renderGetTextureSize(uptr: *anyopaque, image: i32, w: *u32, h: *u32) i32 {
    const ctx: *Context = @ptrCast(@alignCast(uptr));
    const tex = findTexture(ctx, image) orelse return 0;
    w.* = tex.width;
    h.* = tex.height;
    return 1;
}

fn renderViewport(uptr: *anyopaque, width: f32, height: f32, device_pixel_ratio: f32) void {
    _ = device_pixel_ratio;
    const ctx: *Context = @ptrCast(@alignCast(uptr));
    ctx.view = .{ width, height };
}

fn renderCancel(uptr: *anyopaque) void {
    const ctx: *Context = @ptrCast(@alignCast(uptr));
    ctx.verts.items.len = 0;
    ctx.paths.items.len = 0;
    ctx.calls.items.len = 0;
    ctx.uniforms.items.len = 0;
}

fn renderFlush(uptr: *anyopaque) void {
    const ctx: *Context = @ptrCast(@alignCast(uptr));
    flushTextureUpdates(ctx);

    if (ctx.calls.items.len > 0) {
        sg.updateBuffer(ctx.vbuf, sg.Range{ .ptr = ctx.verts.items.ptr, .size = ctx.verts.items.len * @sizeOf(internal.Vertex) });
        for (ctx.calls.items) |call| {
            switch (call.type_) {
                .fill => fillInternal(ctx, &call),
                .convexfill => convexFillInternal(ctx, &call),
                .stroke => strokeInternal(ctx, &call),
                .triangles => trianglesInternal(ctx, &call),
                .none => {},
            }
        }
    }

    ctx.verts.items.len = 0;
    ctx.paths.items.len = 0;
    ctx.calls.items.len = 0;
    ctx.uniforms.items.len = 0;
}

fn appendPathGeometry(ctx: *Context, dst: *PathItem, src: internal.Path, v_off: *usize) void {
    dst.* = .{};

    if (src.fill.len > 0) {
        dst.fill_offset = v_off.*;
        dst.fill_count = fanToTriangles(ctx.verts.items[v_off.*..], src.fill, src.fill.len);
        v_off.* += dst.fill_count;
    }

    if (src.stroke.len > 0) {
        dst.stroke_offset = v_off.*;
        dst.stroke_count = src.stroke.len;
        @memcpy(ctx.verts.items[v_off.* .. v_off.* + dst.stroke_count], src.stroke);
        v_off.* += dst.stroke_count;
    }
}

fn renderFill(uptr: *anyopaque, paint: *nvg.Paint, composite_operation: nvg.CompositeOperationState, scissor: *internal.Scissor, bounds: [4]f32, clip_paths: []const internal.Path, paths: []const internal.Path) void {
    _ = composite_operation;
    const ctx: *Context = @ptrCast(@alignCast(uptr));
    const call = allocCall(ctx) catch return;

    call.type_ = .fill;
    call.triangle_count = 4;
    call.path_offset = allocPaths(ctx, clip_paths.len + paths.len) catch {
        ctx.calls.items.len -= 1;
        return;
    };
    call.path_count = clip_paths.len + paths.len;
    call.image = paint.image.handle;

    if (paths.len == 1 and paths[0].convex and clip_paths.len == 0) {
        call.type_ = .convexfill;
        call.triangle_count = 0;
    }

    var maxverts: usize = 0;
    for (clip_paths) |path| {
        maxverts += fanToTriCount(path.fill.len);
        maxverts += path.stroke.len;
    }
    for (paths) |path| {
        maxverts += fanToTriCount(path.fill.len);
        maxverts += path.stroke.len;
    }
    if (call.type_ == .fill) maxverts += 4;

    const offset = allocVerts(ctx, maxverts) catch {
        ctx.calls.items.len -= 1;
        return;
    };

    var v_off = offset;
    var path_idx: usize = 0;
    for (clip_paths) |path| {
        appendPathGeometry(ctx, &ctx.paths.items[call.path_offset + path_idx], path, &v_off);
        path_idx += 1;
    }
    for (paths) |path| {
        appendPathGeometry(ctx, &ctx.paths.items[call.path_offset + path_idx], path, &v_off);
        path_idx += 1;
    }

    if (call.type_ == .fill) {
        call.triangle_offset = v_off;
        const quad = ctx.verts.items[v_off .. v_off + 4];
        quad[0] = .{ .x = bounds[2], .y = bounds[3], .u = 0.5, .v = 1.0 };
        quad[1] = .{ .x = bounds[2], .y = bounds[1], .u = 0.5, .v = 1.0 };
        quad[2] = .{ .x = bounds[0], .y = bounds[3], .u = 0.5, .v = 1.0 };
        quad[3] = .{ .x = bounds[0], .y = bounds[1], .u = 0.5, .v = 1.0 };

        call.uniform_offset = allocFragUniforms(ctx, 2) catch {
            ctx.calls.items.len -= 1;
            return;
        };

        const simple = fragUniformPtr(ctx, call.uniform_offset);
        simple.* = zeroFrag();
        simple.strokeThr = -1.0;
        simple.shader_type = @floatFromInt(@intFromEnum(ShaderType.simple));

        convertPaint(ctx, fragUniformPtr(ctx, call.uniform_offset + 1), paint, scissor, 1.0, 1.0, -1.0);
    } else {
        call.uniform_offset = allocFragUniforms(ctx, 1) catch {
            ctx.calls.items.len -= 1;
            return;
        };
        convertPaint(ctx, fragUniformPtr(ctx, call.uniform_offset), paint, scissor, 1.0, 1.0, -1.0);
    }
}

fn renderStroke(uptr: *anyopaque, paint: *nvg.Paint, composite_operation: nvg.CompositeOperationState, scissor: *internal.Scissor, bounds: [4]f32, clip_paths: []const internal.Path, paths: []const internal.Path) void {
    _ = composite_operation;
    _ = bounds;
    const ctx: *Context = @ptrCast(@alignCast(uptr));
    const call = allocCall(ctx) catch return;
    call.type_ = .stroke;
    call.path_offset = allocPaths(ctx, clip_paths.len + paths.len) catch {
        ctx.calls.items.len -= 1;
        return;
    };
    call.path_count = clip_paths.len + paths.len;
    call.image = paint.image.handle;

    var maxverts: usize = 0;
    for (clip_paths) |path| maxverts += path.stroke.len;
    for (paths) |path| maxverts += path.stroke.len;

    const offset = allocVerts(ctx, maxverts) catch {
        ctx.calls.items.len -= 1;
        return;
    };

    var v_off = offset;
    var path_idx: usize = 0;
    for (clip_paths) |path| {
        const dst = &ctx.paths.items[call.path_offset + path_idx];
        dst.* = .{};
        if (path.stroke.len > 0) {
            dst.stroke_offset = v_off;
            dst.stroke_count = path.stroke.len;
            @memcpy(ctx.verts.items[v_off .. v_off + dst.stroke_count], path.stroke);
            v_off += dst.stroke_count;
        }
        path_idx += 1;
    }
    for (paths) |path| {
        const dst = &ctx.paths.items[call.path_offset + path_idx];
        dst.* = .{};
        if (path.stroke.len > 0) {
            dst.stroke_offset = v_off;
            dst.stroke_count = path.stroke.len;
            @memcpy(ctx.verts.items[v_off .. v_off + dst.stroke_count], path.stroke);
            v_off += dst.stroke_count;
        }
        path_idx += 1;
    }

    if (ctx.options.stencil_strokes) {
        call.uniform_offset = allocFragUniforms(ctx, 2) catch {
            ctx.calls.items.len -= 1;
            return;
        };
        convertPaint(ctx, fragUniformPtr(ctx, call.uniform_offset), paint, scissor, 1.0, 1.0, -1.0);
        convertPaint(ctx, fragUniformPtr(ctx, call.uniform_offset + 1), paint, scissor, 1.0, 1.0, 1.0 - 0.5 / 255.0);
    } else {
        call.uniform_offset = allocFragUniforms(ctx, 1) catch {
            ctx.calls.items.len -= 1;
            return;
        };
        convertPaint(ctx, fragUniformPtr(ctx, call.uniform_offset), paint, scissor, 1.0, 1.0, -1.0);
    }
}

fn renderTriangles(uptr: *anyopaque, paint: *nvg.Paint, composite_operation: nvg.CompositeOperationState, scissor: *internal.Scissor, verts: []const internal.Vertex) void {
    _ = composite_operation;
    const ctx: *Context = @ptrCast(@alignCast(uptr));
    const call = allocCall(ctx) catch return;
    call.type_ = .triangles;
    call.image = paint.image.handle;
    call.triangle_offset = allocVerts(ctx, verts.len) catch {
        ctx.calls.items.len -= 1;
        return;
    };
    call.triangle_count = verts.len;

    @memcpy(ctx.verts.items[call.triangle_offset .. call.triangle_offset + verts.len], verts);

    call.uniform_offset = allocFragUniforms(ctx, 1) catch {
        ctx.calls.items.len -= 1;
        return;
    };
    const frag = fragUniformPtr(ctx, call.uniform_offset);
    convertPaint(ctx, frag, paint, scissor, 1.0, 1.0, -1.0);
    frag.shader_type = @floatFromInt(@intFromEnum(ShaderType.img));
}

fn renderDelete(uptr: *anyopaque) void {
    const ctx: *Context = @ptrCast(@alignCast(uptr));

    for (ctx.textures.items) |*tex| {
        if (tex.img.id != sg.invalid_id) sg.destroyImage(tex.img);
        if (tex.view.id != sg.invalid_id) sg.destroyView(tex.view);
        if (tex.sampler.id != sg.invalid_id) sg.destroySampler(tex.sampler);
        if (tex.pending_data) |buf| ctx.allocator.free(buf);
    }

    sg.destroyBuffer(ctx.vbuf);
    sg.destroySampler(ctx.default_sampler);
    sg.destroyImage(ctx.dummy_tex);
    sg.destroyView(ctx.dummy_view);
    sg.destroyPipeline(ctx.pip_fill);
    sg.destroyPipeline(ctx.pip_fill_stencil);
    sg.destroyPipeline(ctx.pip_fill_antialias);
    sg.destroyPipeline(ctx.pip_fill_draw);
    sg.destroyPipeline(ctx.pip_stroke);
    sg.destroyPipeline(ctx.pip_stroke_stencil);
    sg.destroyPipeline(ctx.pip_stroke_antialias);
    sg.destroyPipeline(ctx.pip_stroke_clear);
    sg.destroyPipeline(ctx.pip_triangles);
    sg.destroyShader(ctx.shader);

    ctx.textures.deinit();
    ctx.calls.deinit();
    ctx.paths.deinit();
    ctx.verts.deinit();
    ctx.uniforms.deinit();
    ctx.allocator.destroy(ctx);
}

pub fn init(allocator: std.mem.Allocator, options: Options) !nvg {
    return initWithDesc(allocator, options, null);
}

pub fn initWithDesc(allocator: std.mem.Allocator, options: Options, desc: ?*const Desc) !nvg {
    const backend_allocator = if (desc) |d| d.allocator else allocator;
    const ctx = try backend_allocator.create(Context);
    ctx.* = .{
        .allocator = backend_allocator,
        .options = options,
        .textures = ArrayList(Texture).init(backend_allocator),
        .calls = ArrayList(Call).init(backend_allocator),
        .paths = ArrayList(PathItem).init(backend_allocator),
        .verts = ArrayList(internal.Vertex).init(backend_allocator),
        .uniforms = ArrayList(FragUniforms).init(backend_allocator),
    };

    const params: internal.Params = .{
        .user_ptr = ctx,
        .renderCreate = renderCreate,
        .renderCreateTexture = renderCreateTexture,
        .renderDeleteTexture = renderDeleteTexture,
        .renderUpdateTexture = renderUpdateTexture,
        .renderGetTextureSize = renderGetTextureSize,
        .renderViewport = renderViewport,
        .renderCancel = renderCancel,
        .renderFlush = renderFlush,
        .renderFill = renderFill,
        .renderStroke = renderStroke,
        .renderTriangles = renderTriangles,
        .renderDelete = renderDelete,
    };

    const nv = try internal.Context.init(backend_allocator, params);
    return .{ .ctx = nv };
}
