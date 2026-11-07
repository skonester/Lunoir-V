module mpv

// Values mirror client.h; enums_test.v checks them against the C constants.

// Format is the data format of options, properties and nodes (mpv_format).
pub enum Format {
	none       = 0
	string     = 1
	osd_string = 2
	flag       = 3
	int64      = 4
	double     = 5
	node       = 6
	node_array = 7
	node_map   = 8
	byte_array = 9
}

// EventId identifies an event returned by Mpv.wait_event (mpv_event_id).
pub enum EventId {
	none               = 0
	shutdown           = 1
	log_message        = 2
	get_property_reply = 3
	set_property_reply = 4
	command_reply      = 5
	start_file         = 6
	end_file           = 7
	file_loaded        = 8
	idle               = 11 // deprecated, but still sent; use the idle-active property
	tick               = 14 // deprecated and off by default; use playback-time
	client_message     = 16
	video_reconfig     = 17
	audio_reconfig     = 18
	seek               = 20
	playback_restart   = 21
	property_change    = 22
	queue_overflow     = 24
	hook               = 25
}

// name returns mpv's name for the event, e.g. "property-change".
pub fn (id EventId) name() string {
	return cstr(C.mpv_event_name(int(id)))
}

// EndFileReason says why playback of a file ended (mpv_end_file_reason).
pub enum EndFileReason {
	eof      = 0
	stop     = 2
	quit     = 3
	error    = 4
	redirect = 5
}

// LogLevel is the level of a log message (mpv_log_level).
pub enum LogLevel {
	none  = 0
	fatal = 10
	error = 20
	warn  = 30
	info  = 40
	v     = 50
	debug = 60
	trace = 70
}

// Flag set in RenderContext.update when a new video frame should be rendered.
pub const render_update_frame = u64(1)
