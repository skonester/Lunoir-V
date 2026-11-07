module mpv

// GetProcAddressFn resolves an OpenGL function by name, e.g. wglGetProcAddress
// wrapped with a fallback to opengl32.dll. ctx is the value passed to
// new_render_context_gl.
pub type GetProcAddressFn = fn (ctx voidptr, name &char) voidptr

// RenderUpdateFn is called on an mpv thread when a new frame may be ready;
// see RenderContext.set_update_callback.
pub type RenderUpdateFn = fn (data voidptr)

// RenderContext is the video output of an Mpv instance whose vo option is
// "libmpv". Free it before calling terminate_destroy on the instance.
@[heap]
pub struct RenderContext {
mut:
	ctx &C.mpv_render_context = unsafe { nil }
}

// new_render_context_sw creates a software (CPU) render context.
pub fn (m &Mpv) new_render_context_sw() !&RenderContext {
	mut rc := &RenderContext{}
	check(C.vmpv_render_create_sw(&rc.ctx, m.handle))!
	return rc
}

// new_render_context_gl creates an OpenGL render context. The GL context must be
// current on the calling thread, here and for every later render_gl call.
pub fn (m &Mpv) new_render_context_gl(get_proc_address GetProcAddressFn, ctx voidptr) !&RenderContext {
	mut rc := &RenderContext{}
	check(C.vmpv_render_create_gl(&rc.ctx, m.handle, get_proc_address, ctx))!
	return rc
}

// render_sw renders the current frame into buf, which must hold stride*height
// bytes. format is one of rgb0, bgr0, 0bgr, 0rgb (4 bytes per pixel) or rgb24.
pub fn (rc &RenderContext) render_sw(width int, height int, stride int, format string, mut buf []u8) ! {
	if stride < 0 || buf.len < stride * height {
		return MpvError{
			code: int(ErrorCode.invalid_parameter)
		}
	}
	check(C.vmpv_render_sw(rc.ctx, width, height, &char(format.str), usize(stride), buf.data))!
}

// render_gl renders the current frame into an OpenGL framebuffer object
// (0 for the default framebuffer). Set flip_y when rendering to the screen.
pub fn (rc &RenderContext) render_gl(fbo int, width int, height int, flip_y bool) ! {
	check(C.vmpv_render_gl(rc.ctx, fbo, width, height, if flip_y { 1 } else { 0 }))!
}

// set_update_callback makes mpv call cb(data) when update should be called.
// cb runs on an mpv thread: it must not call mpv functions or allocate,
// only signal the render thread. Pass nil to remove it.
pub fn (rc &RenderContext) set_update_callback(cb RenderUpdateFn, data voidptr) {
	C.mpv_render_context_set_update_callback(rc.ctx, cb, data)
}

// update returns flags for the render thread; render a frame when
// `rc.update() & mpv.render_update_frame != 0`.
pub fn (rc &RenderContext) update() u64 {
	return C.mpv_render_context_update(rc.ctx)
}

// report_swap tells mpv a frame was presented (after a buffer swap).
pub fn (rc &RenderContext) report_swap() {
	C.mpv_render_context_report_swap(rc.ctx)
}

// free destroys the render context. Calling it again does nothing.
pub fn (mut rc RenderContext) free() {
	if !isnil(rc.ctx) {
		C.mpv_render_context_free(rc.ctx)
		rc.ctx = unsafe { nil }
	}
}
