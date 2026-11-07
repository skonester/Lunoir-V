module mpv

// ErrorCode lists libmpv's error codes (mpv_error).
pub enum ErrorCode {
	success              = 0
	event_queue_full     = -1
	nomem                = -2
	uninitialized        = -3
	invalid_parameter    = -4
	option_not_found     = -5
	option_format        = -6
	option_error         = -7
	property_not_found   = -8
	property_format      = -9
	property_unavailable = -10
	property_error       = -11
	command              = -12
	loading_failed       = -13
	ao_init_failed       = -14
	vo_init_failed       = -15
	nothing_to_play      = -16
	unknown_format       = -17
	unsupported          = -18
	not_implemented      = -19
	generic              = -20
}

// MpvError is the error every failing call in this module returns.
// Match on it with `if err is mpv.MpvError && err.kind() == .property_not_found`.
pub struct MpvError {
	Error
pub:
	code int
}

pub fn (e MpvError) msg() string {
	return error_string(e.code)
}

pub fn (e MpvError) code() int {
	return e.code
}

pub fn (e MpvError) kind() ErrorCode {
	return unsafe { ErrorCode(e.code) }
}

// error_string returns libmpv's description of an error code.
pub fn error_string(code int) string {
	return cstr(C.mpv_error_string(code))
}

// check turns a libmpv return code into an error; codes >= 0 are success.
fn check(rc int) ! {
	if rc < 0 {
		return MpvError{
			code: rc
		}
	}
}

// cstr copies a C string into a V string; nil becomes ''.
fn cstr(p &char) string {
	if isnil(p) {
		return ''
	}
	return unsafe { cstring_to_vstring(p) }
}
