const std = @import("std");
const sg = @import("sokol").gfx;
const nvg = @import("nanovg.zig");
const internal = @import("internal.zig");

pub const Options = struct {
    anti_alias: bool = false,
    stencil_strokes: bool = false,
    debug: bool = false,
};

// typedef struct snvg_allocator_t {
//     void* (*alloc_fn)(size_t size, void* user_data);
//     void (*free_fn)(void* ptr, void* user_data);
//     void* user_data;
// } snvg_allocator_t;
//
// typedef struct snvg_desc_t {
//     snvg_allocator_t allocator;
// } snvg_desc_t;
//
// SOKOL_NANOVG_API_DECL NVGcontext* nvgCreateSokol(int flags);
pub fn init(allocator: std.mem.Allocator, options: Options) !nvg {
    _ = allocator;
    _ = options;
}
// TODO:
// SOKOL_NANOVG_API_DECL NVGcontext* nvgCreateSokolWithDesc(int flags, const snvg_desc_t* desc);

// SOKOL_NANOVG_API_DECL void nvgDeleteSokol(NVGcontext* ctx);
// pub fn deinit()
//
// #ifdef __cplusplus
// } /* extern "C" */
// #endif
//
// #endif /* SOKOL_NANOVG_INCLUDED */
//
// /*--- IMPLEMENTATION ---------------------------------------------------------*/
//
const ShaderType = enum {
    fillgrad,
    fillimg,
    simple,
    img,
};
//
const CallType = enum(u8) {
    none = 0,
    fill,
    convexfill,
    stroke,
    triangles,
};
//
const Texture = struct {
    id: i32,
    img: sg.Image,
    view: sg.View,
    sampler: sg.Sampler,
    width: i32,
    height: i32,
    type_: i32,
    dirty: i32,
    pending_data: []u8,
};

const Call = struct {
    type_: i32,
    image: i32,
    pathoffset: i32,
    pathcount: i32,
    triangleoffset: i32,
    trianglecount: i32,
    uniformoffset: i32,
};

const Path = struct {
    fillOffset: i32,
    fillCount: i32,
    strokeOffset: i32,
    strokeCount: i32,
};
//
// // Fragment uniforms (must match shader fs_params layout)
const FragUniforms = struct {
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
    type: f32,
};

const Context = struct {
    shader: sg.Shader,
    pip_fill: sg.Pipeline,
    pip_fill_stencil: sg.Pipeline,
    pip_fill_antialias: sg.Pipeline,
    pip_fill_draw: sg.Pipeline,
    pip_stroke: sg.Pipeline,
    pip_stroke_stencil: sg.Pipeline,
    pip_stroke_antialias: sg.Pipeline,
    pip_stroke_clear: sg.Pipeline,
    pip_triangles: sg.Pipeline,
    vbuf: sg.Buffer,
    default_sampler: sg.Sampler,
    dummy_tex: sg.Image,
    dummy_view: sg.View,
    bindings: sg.Bindings,

    view: [2]f32,

    textures: std.ArrayList(Texture),
    //     int ntextures;
    //     int ctextures;
    //     int textureId;
    //
    //     SNVGcall* calls;
    //     int ccalls;
    //     SNVGpath* paths;
    //     int cpaths;
    //     int npaths;
    //     struct NVGvertex* verts;
    //     int cverts;
    //     int nverts;
    //     unsigned char* uniforms;
    //     int cuniforms;
    //     int nuniforms;
    //
    //     int flags;
    //     int fragSize;
    //     snvg_allocator_t allocator;
};
//
// static int snvg__maxi(int a, int b) { return a > b ? a : b; }
//
// static int snvg__fanToTriCount(int fanCount) {
//     if (fanCount < 3) return 0;
//     return (fanCount - 2) * 3;
// }
//
// // Convert triangle fan to triangle list (sokol doesn't support fans)
// static int snvg__fanToTriangles(struct NVGvertex* dst, const struct NVGvertex* src, int fanCount) {
//     int i, triCount = 0;
//     if (fanCount < 3) return 0;
//     for (i = 2; i < fanCount; i++) {
//         dst[triCount++] = src[0];
//         dst[triCount++] = src[i - 1];
//         dst[triCount++] = src[i];
//     }
//     return triCount;
// }
//
// static void* snvg__alloc(SNVGcontext* ctx, size_t size) {
//     if (ctx->allocator.alloc_fn) {
//         return ctx->allocator.alloc_fn(size, ctx->allocator.user_data);
//     }
//     return malloc(size);
// }
//
// static void* snvg__realloc(SNVGcontext* ctx, void* ptr, size_t old_size, size_t new_size) {
//     if (ctx->allocator.alloc_fn) {
//         void* new_ptr = ctx->allocator.alloc_fn(new_size, ctx->allocator.user_data);
//         if (new_ptr && ptr) {
//             memcpy(new_ptr, ptr, old_size < new_size ? old_size : new_size);
//             ctx->allocator.free_fn(ptr, ctx->allocator.user_data);
//         }
//         return new_ptr;
//     }
//     return realloc(ptr, new_size);
// }
//
// static void snvg__free(SNVGcontext* ctx, void* ptr) {
//     if (ctx->allocator.free_fn) {
//         ctx->allocator.free_fn(ptr, ctx->allocator.user_data);
//     } else {
//         free(ptr);
//     }
// }
//
// /*
//  * Texture management
//  */
//
// static SNVGtexture* snvg__allocTexture(SNVGcontext* ctx) {
//     SNVGtexture* tex = NULL;
//     int i;
//
//     for (i = 0; i < ctx->ntextures; i++) {
//         if (ctx->textures[i].id == 0) {
//             tex = &ctx->textures[i];
//             break;
//         }
//     }
//     if (tex == NULL) {
//         if (ctx->ntextures + 1 > ctx->ctextures) {
//             int ctextures = snvg__maxi(ctx->ntextures + 1, 4) + ctx->ctextures / 2;
//             SNVGtexture* textures = (SNVGtexture*)snvg__realloc(ctx, ctx->textures,
//                 sizeof(SNVGtexture) * ctx->ctextures, sizeof(SNVGtexture) * ctextures);
//             if (textures == NULL) return NULL;
//             ctx->textures = textures;
//             ctx->ctextures = ctextures;
//         }
//         tex = &ctx->textures[ctx->ntextures++];
//     }
//
//     memset(tex, 0, sizeof(*tex));
//     tex->id = ++ctx->textureId;
//
//     return tex;
// }
//
// static SNVGtexture* snvg__findTexture(SNVGcontext* ctx, int id) {
//     int i;
//     for (i = 0; i < ctx->ntextures; i++) {
//         if (ctx->textures[i].id == id) {
//             return &ctx->textures[i];
//         }
//     }
//     return NULL;
// }
//
// static int snvg__deleteTexture(SNVGcontext* ctx, int id) {
//     int i;
//     for (i = 0; i < ctx->ntextures; i++) {
//         if (ctx->textures[i].id == id) {
//             if (ctx->textures[i].img.id != SG_INVALID_ID) {
//                 sg_destroy_image(ctx->textures[i].img);
//             }
//             if (ctx->textures[i].tex_view.id != SG_INVALID_ID) {
//                 sg_destroy_view(ctx->textures[i].tex_view);
//             }
//             if (ctx->textures[i].smp.id != SG_INVALID_ID) {
//                 sg_destroy_sampler(ctx->textures[i].smp);
//             }
//             if (ctx->textures[i].pending_data)
//                 snvg__free(ctx, ctx->textures[i].pending_data);
//             memset(&ctx->textures[i], 0, sizeof(ctx->textures[i]));
//             return 1;
//         }
//     }
//     return 0;
// }
//
// // sokol_gfx requires blend state in pipelines at creation time, so custom
// // composite operations (nvgGlobalCompositeOperation) are not supported.
// // Pipelines use premultiplied alpha (ONE, ONE_MINUS_SRC_ALPHA).
//
// static void snvg__xformToMat3x4(float* m3, float* t) {
//     m3[0] = t[0]; m3[1] = t[1]; m3[2] = 0.0f; m3[3] = 0.0f;
//     m3[4] = t[2]; m3[5] = t[3]; m3[6] = 0.0f; m3[7] = 0.0f;
//     m3[8] = t[4]; m3[9] = t[5]; m3[10] = 1.0f; m3[11] = 0.0f;
// }
//
// static NVGcolor snvg__premulColor(NVGcolor c) {
//     c.r *= c.a;
//     c.g *= c.a;
//     c.b *= c.a;
//     return c;
// }
//
// static int snvg__convertPaint(SNVGcontext* ctx, SNVGfragUniforms* frag, NVGpaint* paint,
//                               NVGscissor* scissor, float width, float fringe, float strokeThr) {
//     SNVGtexture* tex = NULL;
//     float invxform[6];
//     NVGcolor innerCol, outerCol;
//
//     memset(frag, 0, sizeof(*frag));
//
//     innerCol = snvg__premulColor(paint->innerColor);
//     outerCol = snvg__premulColor(paint->outerColor);
//     frag->innerCol[0] = innerCol.r;
//     frag->innerCol[1] = innerCol.g;
//     frag->innerCol[2] = innerCol.b;
//     frag->innerCol[3] = innerCol.a;
//     frag->outerCol[0] = outerCol.r;
//     frag->outerCol[1] = outerCol.g;
//     frag->outerCol[2] = outerCol.b;
//     frag->outerCol[3] = outerCol.a;
//
//     if (scissor->extent[0] < -0.5f || scissor->extent[1] < -0.5f) {
//         memset(frag->scissorMat, 0, sizeof(frag->scissorMat));
//         frag->scissorExt[0] = 1.0f;
//         frag->scissorExt[1] = 1.0f;
//         frag->scissorScale[0] = 1.0f;
//         frag->scissorScale[1] = 1.0f;
//     } else {
//         nvgTransformInverse(invxform, scissor->xform);
//         snvg__xformToMat3x4(frag->scissorMat, invxform);
//         frag->scissorExt[0] = scissor->extent[0];
//         frag->scissorExt[1] = scissor->extent[1];
//         frag->scissorScale[0] = sqrtf(scissor->xform[0]*scissor->xform[0] + scissor->xform[2]*scissor->xform[2]) / fringe;
//         frag->scissorScale[1] = sqrtf(scissor->xform[1]*scissor->xform[1] + scissor->xform[3]*scissor->xform[3]) / fringe;
//     }
//
//     frag->extent[0] = paint->extent[0];
//     frag->extent[1] = paint->extent[1];
//     frag->strokeMult = (width * 0.5f + fringe * 0.5f) / fringe;
//     frag->strokeThr = strokeThr;
//
//     if (paint->image != 0) {
//         tex = snvg__findTexture(ctx, paint->image);
//         if (tex == NULL) return 0;
//         if ((tex->flags & NVG_IMAGE_FLIPY) != 0) {
//             float m1[6], m2[6];
//             nvgTransformTranslate(m1, 0.0f, frag->extent[1] * 0.5f);
//             nvgTransformMultiply(m1, paint->xform);
//             nvgTransformScale(m2, 1.0f, -1.0f);
//             nvgTransformMultiply(m2, m1);
//             nvgTransformTranslate(m1, 0.0f, -frag->extent[1] * 0.5f);
//             nvgTransformMultiply(m1, m2);
//             nvgTransformInverse(invxform, m1);
//         } else {
//             nvgTransformInverse(invxform, paint->xform);
//         }
//         frag->type = (float)SNVG_SHADER_FILLIMG;
//
//         if (tex->type == NVG_TEXTURE_RGBA)
//             frag->texType = (tex->flags & NVG_IMAGE_PREMULTIPLIED) ? 0.0f : 1.0f;
//         else
//             frag->texType = 2.0f;
//     } else {
//         frag->type = (float)SNVG_SHADER_FILLGRAD;
//         frag->radius = paint->radius;
//         frag->feather = paint->feather;
//         nvgTransformInverse(invxform, paint->xform);
//     }
//
//     snvg__xformToMat3x4(frag->paintMat, invxform);
//
//     return 1;
// }
//
// static int snvg__allocFragUniforms(SNVGcontext* ctx, int n) {
//     int ret = 0, structSize = sizeof(SNVGfragUniforms);
//     if (ctx->nuniforms + n > ctx->cuniforms) {
//         unsigned char* uniforms;
//         int cuniforms = snvg__maxi(ctx->nuniforms + n, 128) + ctx->cuniforms / 2;
//         uniforms = (unsigned char*)snvg__realloc(ctx, ctx->uniforms,
//             structSize * ctx->cuniforms, structSize * cuniforms);
//         if (uniforms == NULL) return -1;
//         ctx->uniforms = uniforms;
//         ctx->cuniforms = cuniforms;
//     }
//     ret = ctx->nuniforms * structSize;
//     ctx->nuniforms += n;
//     return ret;
// }
//
// static SNVGfragUniforms* snvg__fragUniformPtr(SNVGcontext* ctx, int i) {
//     return (SNVGfragUniforms*)&ctx->uniforms[i];
// }
//
// static SNVGcall* snvg__allocCall(SNVGcontext* ctx) {
//     SNVGcall* ret = NULL;
//     if (ctx->ncalls + 1 > ctx->ccalls) {
//         SNVGcall* calls;
//         int ccalls = snvg__maxi(ctx->ncalls + 1, 128) + ctx->ccalls / 2;
//         calls = (SNVGcall*)snvg__realloc(ctx, ctx->calls,
//             sizeof(SNVGcall) * ctx->ccalls, sizeof(SNVGcall) * ccalls);
//         if (calls == NULL) return NULL;
//         ctx->calls = calls;
//         ctx->ccalls = ccalls;
//     }
//     ret = &ctx->calls[ctx->ncalls++];
//     memset(ret, 0, sizeof(*ret));
//     return ret;
// }
//
// static int snvg__allocPaths(SNVGcontext* ctx, int n) {
//     int ret = 0;
//     if (ctx->npaths + n > ctx->cpaths) {
//         SNVGpath* paths;
//         int cpaths = snvg__maxi(ctx->npaths + n, 128) + ctx->cpaths / 2;
//         paths = (SNVGpath*)snvg__realloc(ctx, ctx->paths,
//             sizeof(SNVGpath) * ctx->cpaths, sizeof(SNVGpath) * cpaths);
//         if (paths == NULL) return -1;
//         ctx->paths = paths;
//         ctx->cpaths = cpaths;
//     }
//     ret = ctx->npaths;
//     ctx->npaths += n;
//     return ret;
// }
//
// static int snvg__allocVerts(SNVGcontext* ctx, int n) {
//     int ret = 0;
//     if (ctx->nverts + n > ctx->cverts) {
//         struct NVGvertex* verts;
//         int cverts = snvg__maxi(ctx->nverts + n, 4096) + ctx->cverts / 2;
//         verts = (struct NVGvertex*)snvg__realloc(ctx, ctx->verts,
//             sizeof(struct NVGvertex) * ctx->cverts, sizeof(struct NVGvertex) * cverts);
//         if (verts == NULL) return -1;
//         ctx->verts = verts;
//         ctx->cverts = cverts;
//     }
//     ret = ctx->nverts;
//     ctx->nverts += n;
//     return ret;
// }
//
// /*
//  * NVGparams render callbacks
//  */
//
// static int snvg__renderCreate(void* uptr) {
//     SNVGcontext* ctx = (SNVGcontext*)uptr;
//
//     ctx->shader = sg_make_shader(snvg_shader_desc(sg_query_backend()));
//     if (ctx->shader.id == SG_INVALID_ID) {
//         return 0;
//     }
//
//     sg_pipeline_desc pip_desc = {
//         .shader = ctx->shader,
//         .layout = {
//             .attrs = {
//                 [ATTR_snvg_vertex] = { .format = SG_VERTEXFORMAT_FLOAT2 },
//                 [ATTR_snvg_tcoord] = { .format = SG_VERTEXFORMAT_FLOAT2 },
//             },
//         },
//         .colors[0] = {
//             .blend = {
//                 .enabled = true,
//                 .src_factor_rgb = SG_BLENDFACTOR_ONE,
//                 .dst_factor_rgb = SG_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
//                 .src_factor_alpha = SG_BLENDFACTOR_ONE,
//                 .dst_factor_alpha = SG_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
//             },
//             .write_mask = SG_COLORMASK_RGBA,
//         },
//         .depth = {
//             .pixel_format = SG_PIXELFORMAT_DEPTH_STENCIL,
//         },
//         .stencil = {
//             .enabled = false,
//         },
//         .primitive_type = SG_PRIMITIVETYPE_TRIANGLE_STRIP,
//         .cull_mode = SG_CULLMODE_BACK,
//         .face_winding = SG_FACEWINDING_CCW,
//         .label = "snvg-pip-fill",
//     };
//
//     pip_desc.primitive_type = SG_PRIMITIVETYPE_TRIANGLES;
//     ctx->pip_fill = sg_make_pipeline(&pip_desc);
//
//     pip_desc.label = "snvg-pip-triangles";
//     ctx->pip_triangles = sg_make_pipeline(&pip_desc);
//
//     // Stencil fill pass 1: write to stencil (no color write)
//     pip_desc.colors[0].write_mask = SG_COLORMASK_NONE;
//     pip_desc.stencil = (sg_stencil_state){
//         .enabled = true,
//         .front = {
//             .compare = SG_COMPAREFUNC_ALWAYS,
//             .fail_op = SG_STENCILOP_KEEP,
//             .depth_fail_op = SG_STENCILOP_KEEP,
//             .pass_op = SG_STENCILOP_INCR_WRAP,
//         },
//         .back = {
//             .compare = SG_COMPAREFUNC_ALWAYS,
//             .fail_op = SG_STENCILOP_KEEP,
//             .depth_fail_op = SG_STENCILOP_KEEP,
//             .pass_op = SG_STENCILOP_DECR_WRAP,
//         },
//         .read_mask = 0xff,
//         .write_mask = 0xff,
//         .ref = 0,
//     };
//     pip_desc.cull_mode = SG_CULLMODE_NONE;
//     pip_desc.label = "snvg-pip-fill-stencil";
//     ctx->pip_fill_stencil = sg_make_pipeline(&pip_desc);
//
//     // Stencil fill pass 2: anti-aliased edge
//     pip_desc.primitive_type = SG_PRIMITIVETYPE_TRIANGLE_STRIP;
//     pip_desc.colors[0].write_mask = SG_COLORMASK_RGBA;
//     pip_desc.colors[0].blend = (sg_blend_state){
//         .enabled = true,
//         .src_factor_rgb = SG_BLENDFACTOR_ONE,
//         .dst_factor_rgb = SG_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
//         .src_factor_alpha = SG_BLENDFACTOR_ONE,
//         .dst_factor_alpha = SG_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
//     };
//     pip_desc.stencil = (sg_stencil_state){
//         .enabled = true,
//         .front = {
//             .compare = SG_COMPAREFUNC_EQUAL,
//             .fail_op = SG_STENCILOP_KEEP,
//             .depth_fail_op = SG_STENCILOP_KEEP,
//             .pass_op = SG_STENCILOP_KEEP,
//         },
//         .back = {
//             .compare = SG_COMPAREFUNC_EQUAL,
//             .fail_op = SG_STENCILOP_KEEP,
//             .depth_fail_op = SG_STENCILOP_KEEP,
//             .pass_op = SG_STENCILOP_KEEP,
//         },
//         .read_mask = 0xff,
//         .write_mask = 0xff,
//         .ref = 0,
//     };
//     pip_desc.cull_mode = SG_CULLMODE_BACK;
//     pip_desc.label = "snvg-pip-fill-antialias";
//     ctx->pip_fill_antialias = sg_make_pipeline(&pip_desc);
//
//     // Stencil fill pass 3: draw fill where stencil != 0, then clear stencil
//     pip_desc.stencil = (sg_stencil_state){
//         .enabled = true,
//         .front = {
//             .compare = SG_COMPAREFUNC_NOT_EQUAL,
//             .fail_op = SG_STENCILOP_ZERO,
//             .depth_fail_op = SG_STENCILOP_ZERO,
//             .pass_op = SG_STENCILOP_ZERO,
//         },
//         .back = {
//             .compare = SG_COMPAREFUNC_NOT_EQUAL,
//             .fail_op = SG_STENCILOP_ZERO,
//             .depth_fail_op = SG_STENCILOP_ZERO,
//             .pass_op = SG_STENCILOP_ZERO,
//         },
//         .read_mask = 0xff,
//         .write_mask = 0xff,
//         .ref = 0,
//     };
//     pip_desc.label = "snvg-pip-fill-draw";
//     ctx->pip_fill_draw = sg_make_pipeline(&pip_desc);
//
//     // Stroke pipelines
//     pip_desc.stencil.enabled = false;
//     pip_desc.label = "snvg-pip-stroke";
//     ctx->pip_stroke = sg_make_pipeline(&pip_desc);
//
//     pip_desc.stencil = (sg_stencil_state){
//         .enabled = true,
//         .front = {
//             .compare = SG_COMPAREFUNC_EQUAL,
//             .fail_op = SG_STENCILOP_KEEP,
//             .depth_fail_op = SG_STENCILOP_KEEP,
//             .pass_op = SG_STENCILOP_INCR_CLAMP,
//         },
//         .back = {
//             .compare = SG_COMPAREFUNC_EQUAL,
//             .fail_op = SG_STENCILOP_KEEP,
//             .depth_fail_op = SG_STENCILOP_KEEP,
//             .pass_op = SG_STENCILOP_INCR_CLAMP,
//         },
//         .read_mask = 0xff,
//         .write_mask = 0xff,
//         .ref = 0,
//     };
//     pip_desc.label = "snvg-pip-stroke-stencil";
//     ctx->pip_stroke_stencil = sg_make_pipeline(&pip_desc);
//
//     pip_desc.stencil.front.compare = SG_COMPAREFUNC_EQUAL;
//     pip_desc.stencil.back.compare = SG_COMPAREFUNC_EQUAL;
//     pip_desc.stencil.front.pass_op = SG_STENCILOP_KEEP;
//     pip_desc.stencil.back.pass_op = SG_STENCILOP_KEEP;
//     pip_desc.label = "snvg-pip-stroke-antialias";
//     ctx->pip_stroke_antialias = sg_make_pipeline(&pip_desc);
//
//     pip_desc.colors[0].write_mask = SG_COLORMASK_NONE;
//     pip_desc.stencil = (sg_stencil_state){
//         .enabled = true,
//         .front = {
//             .compare = SG_COMPAREFUNC_ALWAYS,
//             .fail_op = SG_STENCILOP_ZERO,
//             .depth_fail_op = SG_STENCILOP_ZERO,
//             .pass_op = SG_STENCILOP_ZERO,
//         },
//         .back = {
//             .compare = SG_COMPAREFUNC_ALWAYS,
//             .fail_op = SG_STENCILOP_ZERO,
//             .depth_fail_op = SG_STENCILOP_ZERO,
//             .pass_op = SG_STENCILOP_ZERO,
//         },
//         .read_mask = 0xff,
//         .write_mask = 0xff,
//         .ref = 0,
//     };
//     pip_desc.label = "snvg-pip-stroke-clear";
//     ctx->pip_stroke_clear = sg_make_pipeline(&pip_desc);
//
//     ctx->vbuf = sg_make_buffer(&(sg_buffer_desc){
//         .usage = {
//             .vertex_buffer = true,
//             .stream_update = true,
//             .immutable = false,
//         },
//         .size = 65536 * sizeof(struct NVGvertex),
//         .label = "snvg-vbuf",
//     });
//
//     ctx->default_sampler = sg_make_sampler(&(sg_sampler_desc){
//         .min_filter = SG_FILTER_LINEAR,
//         .mag_filter = SG_FILTER_LINEAR,
//         .mipmap_filter = SG_FILTER_NEAREST,
//         .wrap_u = SG_WRAP_CLAMP_TO_EDGE,
//         .wrap_v = SG_WRAP_CLAMP_TO_EDGE,
//         .label = "snvg-sampler",
//     });
//
//     uint32_t white = 0xFFFFFFFF;
//     ctx->dummy_tex = sg_make_image(&(sg_image_desc){
//         .width = 1,
//         .height = 1,
//         .pixel_format = SG_PIXELFORMAT_RGBA8,
//         .data.mip_levels[0] = { .ptr = &white, .size = sizeof(white) },
//         .label = "snvg-dummy",
//     });
//
//     ctx->dummy_view = sg_make_view(&(sg_view_desc){
//         .texture.image = ctx->dummy_tex,
//         .label = "snvg-dummy-view",
//     });
//
//     ctx->bindings.vertex_buffers[0] = ctx->vbuf;
//
//     return 1;
// }
//
// static int snvg__renderCreateTexture(void* uptr, int type, int w, int h, int imageFlags, const unsigned char* data) {
//     SNVGcontext* ctx = (SNVGcontext*)uptr;
//     SNVGtexture* tex = snvg__allocTexture(ctx);
//     if (tex == NULL) return 0;
//
//     sg_pixel_format fmt;
//     if (type == NVG_TEXTURE_RGBA) {
//         fmt = SG_PIXELFORMAT_RGBA8;
//     } else {
//         fmt = SG_PIXELFORMAT_R8;
//     }
//
//     sg_image_desc img_desc = {
//         .width = w,
//         .height = h,
//         .pixel_format = fmt,
//         .label = "snvg-texture",
//     };
//
//     if (data != NULL) {
//         img_desc.usage.immutable = true;
//         size_t pitch = (type == NVG_TEXTURE_RGBA) ? w * 4 : w;
//         img_desc.data.mip_levels[0] = (sg_range){ .ptr = data, .size = h * pitch };
//     } else {
//         // stream_update allows multiple updates per frame (font glyphs)
//         img_desc.usage.immutable = false;
//         img_desc.usage.stream_update = true;
//     }
//
//     if (imageFlags & NVG_IMAGE_GENERATE_MIPMAPS) {
//         img_desc.num_mipmaps = 0;
//     }
//
//     tex->img = sg_make_image(&img_desc);
//
//     tex->tex_view = sg_make_view(&(sg_view_desc){
//         .texture.image = tex->img,
//         .label = "snvg-texture-view",
//     });
//
//     sg_filter min_filter = SG_FILTER_LINEAR;
//     sg_filter mag_filter = SG_FILTER_LINEAR;
//     sg_filter mip_filter = (imageFlags & NVG_IMAGE_GENERATE_MIPMAPS) ? SG_FILTER_LINEAR : SG_FILTER_NEAREST;
//     sg_wrap wrap_u = (imageFlags & NVG_IMAGE_REPEATX) ? SG_WRAP_REPEAT : SG_WRAP_CLAMP_TO_EDGE;
//     sg_wrap wrap_v = (imageFlags & NVG_IMAGE_REPEATY) ? SG_WRAP_REPEAT : SG_WRAP_CLAMP_TO_EDGE;
//
//     if (imageFlags & NVG_IMAGE_NEAREST) {
//         min_filter = SG_FILTER_NEAREST;
//         mag_filter = SG_FILTER_NEAREST;
//     }
//
//     sg_sampler_desc smp_desc = {
//         .min_filter = min_filter,
//         .mag_filter = mag_filter,
//         .mipmap_filter = mip_filter,
//         .min_lod = 0.0f,
//         .max_lod = (imageFlags & NVG_IMAGE_GENERATE_MIPMAPS) ? 1000.0f : 0.0f,
//         .wrap_u = wrap_u,
//         .wrap_v = wrap_v,
//     };
//     tex->smp = sg_make_sampler(&smp_desc);
//
//     tex->width = w;
//     tex->height = h;
//     tex->type = type;
//     tex->flags = imageFlags;
//
//     return tex->id;
// }
//
// static int snvg__renderDeleteTexture(void* uptr, int image) {
//     SNVGcontext* ctx = (SNVGcontext*)uptr;
//     return snvg__deleteTexture(ctx, image);
// }
//
// static int snvg__renderUpdateTexture(void* uptr, int image, int x, int y, int w, int h, const unsigned char* data) {
//     SNVGcontext* ctx = (SNVGcontext*)uptr;
//     SNVGtexture* tex = snvg__findTexture(ctx, image);
//     if (tex == NULL) return 0;
//
//     (void)x; (void)y; (void)w; (void)h;
//
//     // Defer texture updates - nanovg may call this multiple times per frame for font glyphs
//     size_t bpp = (tex->type == NVG_TEXTURE_RGBA) ? 4 : 1;
//     size_t data_size = (size_t)(tex->width * tex->height) * bpp;
//
//     if (tex->pending_data == NULL) {
//         tex->pending_data = (unsigned char*)snvg__alloc(ctx, data_size);
//     }
//     if (tex->pending_data != NULL) {
//         memcpy(tex->pending_data, data, data_size);
//         tex->dirty = 1;
//     }
//
//     return 1;
// }
//
// static void snvg__flushTextureUpdates(SNVGcontext* ctx) {
//     for (int i = 0; i < ctx->ntextures; i++) {
//         SNVGtexture* tex = &ctx->textures[i];
//         if (tex->dirty && tex->pending_data != NULL) {
//             size_t bpp = (tex->type == NVG_TEXTURE_RGBA) ? 4 : 1;
//             size_t pitch = (size_t)tex->width * bpp;
//
//             sg_image_data img_data = {0};
//             img_data.mip_levels[0] = (sg_range){ .ptr = tex->pending_data, .size = (size_t)tex->height * pitch };
//             sg_update_image(tex->img, &img_data);
//
//             tex->dirty = 0;
//         }
//     }
// }
//
// static int snvg__renderGetTextureSize(void* uptr, int image, int* w, int* h) {
//     SNVGcontext* ctx = (SNVGcontext*)uptr;
//     SNVGtexture* tex = snvg__findTexture(ctx, image);
//     if (tex == NULL) return 0;
//     *w = tex->width;
//     *h = tex->height;
//     return 1;
// }
//
// static void snvg__renderViewport(void* uptr, float width, float height, float devicePixelRatio) {
//     SNVGcontext* ctx = (SNVGcontext*)uptr;
//     (void)devicePixelRatio;
//     ctx->view[0] = width;
//     ctx->view[1] = height;
// }
//
// static void snvg__renderCancel(void* uptr) {
//     SNVGcontext* ctx = (SNVGcontext*)uptr;
//     ctx->nverts = 0;
//     ctx->npaths = 0;
//     ctx->ncalls = 0;
//     ctx->nuniforms = 0;
// }
//
// static void snvg__setUniforms(SNVGcontext* ctx, int uniformOffset, int image) {
//     SNVGfragUniforms* frag = snvg__fragUniformPtr(ctx, uniformOffset);
//
//     vs_params_t vs_params = {
//         .viewSize = { ctx->view[0], ctx->view[1] },
//     };
//     sg_apply_uniforms(UB_vs_params, &SG_RANGE(vs_params));
//
//     fs_params_t fs_params = {
//         .scissorMat0 = { frag->scissorMat[0], frag->scissorMat[1], frag->scissorMat[2], frag->scissorMat[3] },
//         .scissorMat1 = { frag->scissorMat[4], frag->scissorMat[5], frag->scissorMat[6], frag->scissorMat[7] },
//         .scissorMat2 = { frag->scissorMat[8], frag->scissorMat[9], frag->scissorMat[10], frag->scissorMat[11] },
//         .paintMat0 = { frag->paintMat[0], frag->paintMat[1], frag->paintMat[2], frag->paintMat[3] },
//         .paintMat1 = { frag->paintMat[4], frag->paintMat[5], frag->paintMat[6], frag->paintMat[7] },
//         .paintMat2 = { frag->paintMat[8], frag->paintMat[9], frag->paintMat[10], frag->paintMat[11] },
//         .innerCol = { frag->innerCol[0], frag->innerCol[1], frag->innerCol[2], frag->innerCol[3] },
//         .outerCol = { frag->outerCol[0], frag->outerCol[1], frag->outerCol[2], frag->outerCol[3] },
//         .scissorExtScale = { frag->scissorExt[0], frag->scissorExt[1], frag->scissorScale[0], frag->scissorScale[1] },
//         .extentRadiusFeather = { frag->extent[0], frag->extent[1], frag->radius, frag->feather },
//         .params = { frag->strokeMult, frag->strokeThr, frag->texType, frag->type },
//     };
//     sg_apply_uniforms(UB_fs_params, &SG_RANGE(fs_params));
//
//     SNVGtexture* tex = (image != 0) ? snvg__findTexture(ctx, image) : NULL;
//     if (tex) {
//         ctx->bindings.views[VIEW_tex] = tex->tex_view;
//         ctx->bindings.samplers[SMP_smp] = tex->smp;
//     } else {
//         ctx->bindings.views[VIEW_tex] = ctx->dummy_view;
//         ctx->bindings.samplers[SMP_smp] = ctx->default_sampler;
//     }
//     sg_apply_bindings(&ctx->bindings);
// }
//
// static void snvg__fill(SNVGcontext* ctx, SNVGcall* call) {
//     SNVGpath* paths = &ctx->paths[call->pathOffset];
//     int i, npaths = call->pathCount;
//
//     sg_apply_pipeline(ctx->pip_fill_stencil);
//     snvg__setUniforms(ctx, call->uniformOffset, 0);
//
//     for (i = 0; i < npaths; i++) {
//         if (paths[i].fillCount > 0)
//             sg_draw(paths[i].fillOffset, paths[i].fillCount, 1);
//     }
//
//     sg_apply_pipeline(ctx->pip_fill_antialias);
//     snvg__setUniforms(ctx, call->uniformOffset + ctx->fragSize, call->image);
//
//     if (ctx->flags & NVG_ANTIALIAS) {
//         for (i = 0; i < npaths; i++) {
//             if (paths[i].strokeCount > 0)
//                 sg_draw(paths[i].strokeOffset, paths[i].strokeCount, 1);
//         }
//     }
//
//     sg_apply_pipeline(ctx->pip_fill_draw);
//     snvg__setUniforms(ctx, call->uniformOffset + ctx->fragSize, call->image);
//     sg_draw(call->triangleOffset, call->triangleCount, 1);
// }
//
// static void snvg__convexFill(SNVGcontext* ctx, SNVGcall* call) {
//     SNVGpath* paths = &ctx->paths[call->pathOffset];
//     int i, npaths = call->pathCount;
//
//     sg_apply_pipeline(ctx->pip_fill);
//     snvg__setUniforms(ctx, call->uniformOffset, call->image);
//     for (i = 0; i < npaths; i++) {
//         if (paths[i].fillCount > 0)
//             sg_draw(paths[i].fillOffset, paths[i].fillCount, 1);
//     }
//
//     // Draw anti-aliasing fringe (uses triangle strip, not triangles)
//     sg_apply_pipeline(ctx->pip_stroke);
//     snvg__setUniforms(ctx, call->uniformOffset, call->image);
//     for (i = 0; i < npaths; i++) {
//         if (paths[i].strokeCount > 0)
//             sg_draw(paths[i].strokeOffset, paths[i].strokeCount, 1);
//     }
// }
//
// static void snvg__stroke(SNVGcontext* ctx, SNVGcall* call) {
//     SNVGpath* paths = &ctx->paths[call->pathOffset];
//     int i, npaths = call->pathCount;
//
//     if (ctx->flags & NVG_STENCIL_STROKES) {
//         sg_apply_pipeline(ctx->pip_stroke_stencil);
//         snvg__setUniforms(ctx, call->uniformOffset + ctx->fragSize, call->image);
//         for (i = 0; i < npaths; i++) {
//             if (paths[i].strokeCount > 0)
//                 sg_draw(paths[i].strokeOffset, paths[i].strokeCount, 1);
//         }
//
//         sg_apply_pipeline(ctx->pip_stroke_antialias);
//         snvg__setUniforms(ctx, call->uniformOffset, call->image);
//         for (i = 0; i < npaths; i++) {
//             if (paths[i].strokeCount > 0)
//                 sg_draw(paths[i].strokeOffset, paths[i].strokeCount, 1);
//         }
//
//         sg_apply_pipeline(ctx->pip_stroke_clear);
//         snvg__setUniforms(ctx, call->uniformOffset, 0);
//         for (i = 0; i < npaths; i++) {
//             if (paths[i].strokeCount > 0)
//                 sg_draw(paths[i].strokeOffset, paths[i].strokeCount, 1);
//         }
//     } else {
//         sg_apply_pipeline(ctx->pip_stroke);
//         snvg__setUniforms(ctx, call->uniformOffset, call->image);
//         for (i = 0; i < npaths; i++) {
//             if (paths[i].strokeCount > 0)
//                 sg_draw(paths[i].strokeOffset, paths[i].strokeCount, 1);
//         }
//     }
// }
//
// static void snvg__triangles(SNVGcontext* ctx, SNVGcall* call) {
//     sg_apply_pipeline(ctx->pip_triangles);
//     snvg__setUniforms(ctx, call->uniformOffset, call->image);
//     sg_draw(call->triangleOffset, call->triangleCount, 1);
// }
//
// static void snvg__renderFlush(void* uptr) {
//     SNVGcontext* ctx = (SNVGcontext*)uptr;
//     int i;
//
//     snvg__flushTextureUpdates(ctx);
//
//     if (ctx->ncalls > 0) {
//         sg_update_buffer(ctx->vbuf, &(sg_range){
//             .ptr = ctx->verts,
//             .size = ctx->nverts * sizeof(struct NVGvertex)
//         });
//
//         for (i = 0; i < ctx->ncalls; i++) {
//             SNVGcall* call = &ctx->calls[i];
//             switch (call->type) {
//                 case SNVG_FILL:       snvg__fill(ctx, call); break;
//                 case SNVG_CONVEXFILL: snvg__convexFill(ctx, call); break;
//                 case SNVG_STROKE:     snvg__stroke(ctx, call); break;
//                 case SNVG_TRIANGLES:  snvg__triangles(ctx, call); break;
//             }
//         }
//     }
//
//     ctx->nverts = 0;
//     ctx->npaths = 0;
//     ctx->ncalls = 0;
//     ctx->nuniforms = 0;
// }
//
// static void snvg__renderFill(void* uptr, NVGpaint* paint, NVGcompositeOperationState compositeOperation,
//                              NVGscissor* scissor, float fringe, const float* bounds, const NVGpath* paths, int npaths) {
//     SNVGcontext* ctx = (SNVGcontext*)uptr;
//     SNVGcall* call = snvg__allocCall(ctx);
//     struct NVGvertex* quad;
//     SNVGfragUniforms* frag;
//     int i, maxverts, offset;
//
//     if (call == NULL) return;
//
//     call->type = SNVG_FILL;
//     call->triangleCount = 4;
//     call->pathOffset = snvg__allocPaths(ctx, npaths);
//     if (call->pathOffset == -1) goto error;
//     call->pathCount = npaths;
//     call->image = paint->image;
//     (void)compositeOperation; // sokol_gfx doesn't support per-call blend state
//
//     if (npaths == 1 && paths[0].convex) {
//         call->type = SNVG_CONVEXFILL;
//         call->triangleCount = 0;
//     }
//
//     maxverts = 0;
//     for (i = 0; i < npaths; i++) {
//         maxverts += snvg__fanToTriCount(paths[i].nfill);
//         maxverts += paths[i].nstroke;
//     }
//     if (call->type == SNVG_FILL)
//         maxverts += 4;
//
//     offset = snvg__allocVerts(ctx, maxverts);
//     if (offset == -1) goto error;
//
//     for (i = 0; i < npaths; i++) {
//         SNVGpath* copy = &ctx->paths[call->pathOffset + i];
//         const NVGpath* path = &paths[i];
//         memset(copy, 0, sizeof(*copy));
//         if (path->nfill > 0) {
//             copy->fillOffset = offset;
//             copy->fillCount = snvg__fanToTriangles(&ctx->verts[offset], path->fill, path->nfill);
//             offset += copy->fillCount;
//         }
//         if (path->nstroke > 0) {
//             copy->strokeOffset = offset;
//             copy->strokeCount = path->nstroke;
//             memcpy(&ctx->verts[offset], path->stroke, sizeof(struct NVGvertex) * path->nstroke);
//             offset += path->nstroke;
//         }
//     }
//
//     if (call->type == SNVG_FILL) {
//         call->triangleOffset = offset;
//         quad = &ctx->verts[offset];
//         quad[0].x = bounds[2]; quad[0].y = bounds[3]; quad[0].u = 0.5f; quad[0].v = 1.0f;
//         quad[1].x = bounds[2]; quad[1].y = bounds[1]; quad[1].u = 0.5f; quad[1].v = 1.0f;
//         quad[2].x = bounds[0]; quad[2].y = bounds[3]; quad[2].u = 0.5f; quad[2].v = 1.0f;
//         quad[3].x = bounds[0]; quad[3].y = bounds[1]; quad[3].u = 0.5f; quad[3].v = 1.0f;
//
//         call->uniformOffset = snvg__allocFragUniforms(ctx, 2);
//         if (call->uniformOffset == -1) goto error;
//
//         frag = snvg__fragUniformPtr(ctx, call->uniformOffset);
//         memset(frag, 0, sizeof(*frag));
//         frag->strokeThr = -1.0f;
//         frag->type = (float)SNVG_SHADER_SIMPLE;
//
//         snvg__convertPaint(ctx, snvg__fragUniformPtr(ctx, call->uniformOffset + ctx->fragSize),
//                           paint, scissor, fringe, fringe, -1.0f);
//     } else {
//         call->uniformOffset = snvg__allocFragUniforms(ctx, 1);
//         if (call->uniformOffset == -1) goto error;
//         snvg__convertPaint(ctx, snvg__fragUniformPtr(ctx, call->uniformOffset),
//                           paint, scissor, fringe, fringe, -1.0f);
//     }
//
//     return;
//
// error:
//     if (ctx->ncalls > 0) ctx->ncalls--;
// }
//
// static void snvg__renderStroke(void* uptr, NVGpaint* paint, NVGcompositeOperationState compositeOperation,
//                                NVGscissor* scissor, float fringe, float strokeWidth, const NVGpath* paths, int npaths) {
//     SNVGcontext* ctx = (SNVGcontext*)uptr;
//     SNVGcall* call = snvg__allocCall(ctx);
//     int i, maxverts, offset;
//
//     if (call == NULL) return;
//
//     call->type = SNVG_STROKE;
//     call->pathOffset = snvg__allocPaths(ctx, npaths);
//     if (call->pathOffset == -1) goto error;
//     call->pathCount = npaths;
//     call->image = paint->image;
//     (void)compositeOperation;
//
//     maxverts = 0;
//     for (i = 0; i < npaths; i++) {
//         maxverts += paths[i].nstroke;
//     }
//
//     offset = snvg__allocVerts(ctx, maxverts);
//     if (offset == -1) goto error;
//
//     for (i = 0; i < npaths; i++) {
//         SNVGpath* copy = &ctx->paths[call->pathOffset + i];
//         const NVGpath* path = &paths[i];
//         memset(copy, 0, sizeof(*copy));
//         if (path->nstroke > 0) {
//             copy->strokeOffset = offset;
//             copy->strokeCount = path->nstroke;
//             memcpy(&ctx->verts[offset], path->stroke, sizeof(struct NVGvertex) * path->nstroke);
//             offset += path->nstroke;
//         }
//     }
//
//     if (ctx->flags & NVG_STENCIL_STROKES) {
//         call->uniformOffset = snvg__allocFragUniforms(ctx, 2);
//         if (call->uniformOffset == -1) goto error;
//         snvg__convertPaint(ctx, snvg__fragUniformPtr(ctx, call->uniformOffset),
//                           paint, scissor, strokeWidth, fringe, -1.0f);
//         snvg__convertPaint(ctx, snvg__fragUniformPtr(ctx, call->uniformOffset + ctx->fragSize),
//                           paint, scissor, strokeWidth, fringe, 1.0f - 0.5f/255.0f);
//     } else {
//         call->uniformOffset = snvg__allocFragUniforms(ctx, 1);
//         if (call->uniformOffset == -1) goto error;
//         snvg__convertPaint(ctx, snvg__fragUniformPtr(ctx, call->uniformOffset),
//                           paint, scissor, strokeWidth, fringe, -1.0f);
//     }
//
//     return;
//
// error:
//     if (ctx->ncalls > 0) ctx->ncalls--;
// }
//
// static void snvg__renderTriangles(void* uptr, NVGpaint* paint, NVGcompositeOperationState compositeOperation,
//                                   NVGscissor* scissor, const NVGvertex* verts, int nverts, float fringe) {
//     SNVGcontext* ctx = (SNVGcontext*)uptr;
//     SNVGcall* call = snvg__allocCall(ctx);
//     SNVGfragUniforms* frag;
//
//     if (call == NULL) return;
//
//     call->type = SNVG_TRIANGLES;
//     call->image = paint->image;
//     (void)compositeOperation;
//
//     call->triangleOffset = snvg__allocVerts(ctx, nverts);
//     if (call->triangleOffset == -1) goto error;
//     call->triangleCount = nverts;
//
//     memcpy(&ctx->verts[call->triangleOffset], verts, sizeof(struct NVGvertex) * nverts);
//
//     call->uniformOffset = snvg__allocFragUniforms(ctx, 1);
//     if (call->uniformOffset == -1) goto error;
//
//     frag = snvg__fragUniformPtr(ctx, call->uniformOffset);
//     snvg__convertPaint(ctx, frag, paint, scissor, 1.0f, fringe, -1.0f);
//     frag->type = (float)SNVG_SHADER_IMG;
//
//     return;
//
// error:
//     if (ctx->ncalls > 0) ctx->ncalls--;
// }
//
// static void snvg__renderDelete(void* uptr) {
//     SNVGcontext* ctx = (SNVGcontext*)uptr;
//     int i;
//
//     if (ctx == NULL) return;
//
//     for (i = 0; i < ctx->ntextures; i++) {
//         if (ctx->textures[i].img.id != SG_INVALID_ID) {
//             sg_destroy_image(ctx->textures[i].img);
//         }
//         if (ctx->textures[i].tex_view.id != SG_INVALID_ID) {
//             sg_destroy_view(ctx->textures[i].tex_view);
//         }
//         if (ctx->textures[i].smp.id != SG_INVALID_ID) {
//             sg_destroy_sampler(ctx->textures[i].smp);
//         }
//         if (ctx->textures[i].pending_data != NULL) {
//             snvg__free(ctx, ctx->textures[i].pending_data);
//         }
//     }
//
//     sg_destroy_buffer(ctx->vbuf);
//     sg_destroy_sampler(ctx->default_sampler);
//     sg_destroy_image(ctx->dummy_tex);
//     sg_destroy_view(ctx->dummy_view);
//     sg_destroy_pipeline(ctx->pip_fill);
//     sg_destroy_pipeline(ctx->pip_fill_stencil);
//     sg_destroy_pipeline(ctx->pip_fill_antialias);
//     sg_destroy_pipeline(ctx->pip_fill_draw);
//     sg_destroy_pipeline(ctx->pip_stroke);
//     sg_destroy_pipeline(ctx->pip_stroke_stencil);
//     sg_destroy_pipeline(ctx->pip_stroke_antialias);
//     sg_destroy_pipeline(ctx->pip_stroke_clear);
//     sg_destroy_pipeline(ctx->pip_triangles);
//     sg_destroy_shader(ctx->shader);
//
//     snvg__free(ctx, ctx->textures);
//     snvg__free(ctx, ctx->paths);
//     snvg__free(ctx, ctx->verts);
//     snvg__free(ctx, ctx->uniforms);
//     snvg__free(ctx, ctx->calls);
//     snvg__free(ctx, ctx);
// }
//
// SOKOL_NANOVG_API_DECL NVGcontext* nvgCreateSokol(int flags) {
//     return nvgCreateSokolWithDesc(flags, NULL);
// }
//
// SOKOL_NANOVG_API_DECL NVGcontext* nvgCreateSokolWithDesc(int flags, const snvg_desc_t* desc) {
//     NVGparams params;
//     NVGcontext* ctx = NULL;
//     SNVGcontext* sg = NULL;
//
//     sg = (SNVGcontext*)malloc(sizeof(SNVGcontext));
//     if (sg == NULL) goto error;
//     memset(sg, 0, sizeof(SNVGcontext));
//
//     sg->flags = flags;
//     sg->fragSize = sizeof(SNVGfragUniforms);
//
//     if (desc != NULL) {
//         sg->allocator = desc->allocator;
//     }
//
//     memset(&params, 0, sizeof(params));
//     params.renderCreate = snvg__renderCreate;
//     params.renderCreateTexture = snvg__renderCreateTexture;
//     params.renderDeleteTexture = snvg__renderDeleteTexture;
//     params.renderUpdateTexture = snvg__renderUpdateTexture;
//     params.renderGetTextureSize = snvg__renderGetTextureSize;
//     params.renderViewport = snvg__renderViewport;
//     params.renderCancel = snvg__renderCancel;
//     params.renderFlush = snvg__renderFlush;
//     params.renderFill = snvg__renderFill;
//     params.renderStroke = snvg__renderStroke;
//     params.renderTriangles = snvg__renderTriangles;
//     params.renderDelete = snvg__renderDelete;
//     params.userPtr = sg;
//     params.edgeAntiAlias = flags & NVG_ANTIALIAS ? 1 : 0;
//
//     ctx = nvgCreateInternal(&params);
//     if (ctx == NULL) goto error;
//
//     return ctx;
//
// error:
//     if (sg != NULL) free(sg);
//     return NULL;
// }
//
// SOKOL_NANOVG_API_DECL void nvgDeleteSokol(NVGcontext* ctx) {
//     nvgDeleteInternal(ctx);
// }
//
// #endif /* SOKOL_NANOVG_IMPL */
