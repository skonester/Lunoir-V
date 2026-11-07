// C helpers for the V binding. V cannot model the anonymous union in mpv_node,
// so all union access and C-heap node building happens here.
#ifndef VMPV_HELPER_H
#define VMPV_HELPER_H

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <mpv/client.h>
#include <mpv/render.h>
#include <mpv/render_gl.h>

// --- reading nodes (from mpv or from vmpv_node_*) ---

static inline char *vmpv_node_string(const mpv_node *n) { return n->u.string; }
static inline int vmpv_node_flag(const mpv_node *n) { return n->u.flag; }
static inline int64_t vmpv_node_int64(const mpv_node *n) { return n->u.int64; }
static inline double vmpv_node_double(const mpv_node *n) { return n->u.double_; }
static inline mpv_node_list *vmpv_node_list(const mpv_node *n) { return n->u.list; }
static inline mpv_byte_array *vmpv_node_ba(const mpv_node *n) { return n->u.ba; }
static inline mpv_node *vmpv_node_list_at(const mpv_node_list *l, int i) { return &l->values[i]; }
static inline char *vmpv_node_list_key(const mpv_node_list *l, int i) { return l->keys[i]; }

// --- building nodes on the C heap; free with vmpv_node_free ---

static inline mpv_node *vmpv_node_new(void) {
    mpv_node *n = calloc(1, sizeof(mpv_node));
    if (n) n->format = MPV_FORMAT_NONE;
    return n;
}

// Copies len bytes of s (which need not be NUL-terminated) into a C string.
static inline char *vmpv_strndup(const char *s, size_t len) {
    char *d = malloc(len + 1);
    if (!d) return NULL;
    if (len) memcpy(d, s, len);
    d[len] = 0;
    return d;
}

static inline void vmpv_node_set_none(mpv_node *n) { n->format = MPV_FORMAT_NONE; }
static inline void vmpv_node_set_string(mpv_node *n, const char *s, size_t len) {
    n->format = MPV_FORMAT_STRING;
    n->u.string = vmpv_strndup(s, len);
}
static inline void vmpv_node_set_flag(mpv_node *n, int v) { n->format = MPV_FORMAT_FLAG; n->u.flag = v; }
static inline void vmpv_node_set_int64(mpv_node *n, int64_t v) { n->format = MPV_FORMAT_INT64; n->u.int64 = v; }
static inline void vmpv_node_set_double(mpv_node *n, double v) { n->format = MPV_FORMAT_DOUBLE; n->u.double_ = v; }

static inline void vmpv_node_set_bytes(mpv_node *n, const void *data, size_t size) {
    mpv_byte_array *ba = calloc(1, sizeof(mpv_byte_array));
    n->format = MPV_FORMAT_BYTE_ARRAY;
    n->u.ba = ba;
    if (ba && size) {
        ba->data = malloc(size);
        if (ba->data) {
            memcpy(ba->data, data, size);
            ba->size = size;
        }
    }
}

// Turns n into an empty array or map of num entries and returns the list; fill
// entries with vmpv_node_list_at and map keys with vmpv_node_list_set_key.
static inline mpv_node_list *vmpv_node_set_list(mpv_node *n, int num, int is_map) {
    mpv_node_list *l = calloc(1, sizeof(mpv_node_list));
    n->format = is_map ? MPV_FORMAT_NODE_MAP : MPV_FORMAT_NODE_ARRAY;
    n->u.list = l;
    if (!l || num <= 0) return l;
    l->values = calloc(num, sizeof(mpv_node));
    if (is_map) l->keys = calloc(num, sizeof(char *));
    if (l->values && (!is_map || l->keys)) l->num = num;
    return l;
}

static inline void vmpv_node_list_set_key(mpv_node_list *l, int i, const char *s, size_t len) {
    l->keys[i] = vmpv_strndup(s, len);
}

// Frees what n references; not n itself. Only for trees built by the functions
// above: trees returned by mpv must be freed with mpv_free_node_contents.
static void vmpv_node_free_contents(mpv_node *n) {
    switch (n->format) {
    case MPV_FORMAT_STRING:
        free(n->u.string);
        break;
    case MPV_FORMAT_BYTE_ARRAY:
        if (n->u.ba) free(n->u.ba->data);
        free(n->u.ba);
        break;
    case MPV_FORMAT_NODE_ARRAY:
    case MPV_FORMAT_NODE_MAP: {
        mpv_node_list *l = n->u.list;
        if (!l) break;
        for (int i = 0; i < l->num; i++) {
            vmpv_node_free_contents(&l->values[i]);
            if (l->keys) free(l->keys[i]);
        }
        free(l->values);
        free(l->keys);
        free(l);
        break;
    }
    default:
        break;
    }
    n->format = MPV_FORMAT_NONE;
}

static inline void vmpv_node_free(mpv_node *n) {
    if (!n) return;
    vmpv_node_free_contents(n);
    free(n);
}

// The format and data pointer to pass to mpv_set_property/mpv_set_option for n:
// scalars are passed directly, arrays, maps and byte arrays as MPV_FORMAT_NODE.
static inline int vmpv_node_arg_format(const mpv_node *n) {
    switch (n->format) {
    case MPV_FORMAT_NONE:
    case MPV_FORMAT_STRING:
    case MPV_FORMAT_FLAG:
    case MPV_FORMAT_INT64:
    case MPV_FORMAT_DOUBLE:
        return n->format;
    default:
        return MPV_FORMAT_NODE;
    }
}

static inline void *vmpv_node_arg_data(mpv_node *n) {
    switch (n->format) {
    case MPV_FORMAT_NONE:
        return NULL;
    case MPV_FORMAT_STRING:
    case MPV_FORMAT_FLAG:
    case MPV_FORMAT_INT64:
    case MPV_FORMAT_DOUBLE:
        return &n->u;
    default:
        return n;
    }
}

// --- render API ---

static inline int vmpv_render_create_sw(mpv_render_context **ctx, mpv_handle *mpv) {
    mpv_render_param params[] = {
        {MPV_RENDER_PARAM_API_TYPE, (void *)MPV_RENDER_API_TYPE_SW},
        {0},
    };
    return mpv_render_context_create(ctx, mpv, params);
}

static inline int vmpv_render_sw(mpv_render_context *ctx, int w, int h, const char *format,
                                 size_t stride, void *ptr) {
    int size[2] = {w, h};
    mpv_render_param params[] = {
        {MPV_RENDER_PARAM_SW_SIZE, &size[0]},
        {MPV_RENDER_PARAM_SW_FORMAT, (void *)format},
        {MPV_RENDER_PARAM_SW_STRIDE, &stride},
        {MPV_RENDER_PARAM_SW_POINTER, ptr},
        {0},
    };
    return mpv_render_context_render(ctx, params);
}

typedef void *(*vmpv_get_proc_address_fn)(void *ctx, const char *name);

static inline int vmpv_render_create_gl(mpv_render_context **ctx, mpv_handle *mpv,
                                        vmpv_get_proc_address_fn get_proc_address, void *cb_ctx) {
    mpv_opengl_init_params gl = {
        .get_proc_address = get_proc_address,
        .get_proc_address_ctx = cb_ctx,
    };
    mpv_render_param params[] = {
        {MPV_RENDER_PARAM_API_TYPE, (void *)MPV_RENDER_API_TYPE_OPENGL},
        {MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, &gl},
        {0},
    };
    return mpv_render_context_create(ctx, mpv, params);
}

static inline int vmpv_render_gl(mpv_render_context *ctx, int fbo, int w, int h, int flip_y) {
    mpv_opengl_fbo gl_fbo = {.fbo = fbo, .w = w, .h = h};
    mpv_render_param params[] = {
        {MPV_RENDER_PARAM_OPENGL_FBO, &gl_fbo},
        {MPV_RENDER_PARAM_FLIP_Y, &flip_y},
        {0},
    };
    return mpv_render_context_render(ctx, params);
}

#endif
