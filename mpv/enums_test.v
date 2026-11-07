module mpv

// The V enums hard-code libmpv's values; these checks compare them with the
// headers the module is compiled against, so a changed value fails here.

fn test_format_values() {
	assert int(Format.none) == C.MPV_FORMAT_NONE
	assert int(Format.string) == C.MPV_FORMAT_STRING
	assert int(Format.osd_string) == C.MPV_FORMAT_OSD_STRING
	assert int(Format.flag) == C.MPV_FORMAT_FLAG
	assert int(Format.int64) == C.MPV_FORMAT_INT64
	assert int(Format.double) == C.MPV_FORMAT_DOUBLE
	assert int(Format.node) == C.MPV_FORMAT_NODE
	assert int(Format.node_array) == C.MPV_FORMAT_NODE_ARRAY
	assert int(Format.node_map) == C.MPV_FORMAT_NODE_MAP
	assert int(Format.byte_array) == C.MPV_FORMAT_BYTE_ARRAY
}

fn test_event_id_values() {
	assert int(EventId.none) == C.MPV_EVENT_NONE
	assert int(EventId.shutdown) == C.MPV_EVENT_SHUTDOWN
	assert int(EventId.log_message) == C.MPV_EVENT_LOG_MESSAGE
	assert int(EventId.get_property_reply) == C.MPV_EVENT_GET_PROPERTY_REPLY
	assert int(EventId.set_property_reply) == C.MPV_EVENT_SET_PROPERTY_REPLY
	assert int(EventId.command_reply) == C.MPV_EVENT_COMMAND_REPLY
	assert int(EventId.start_file) == C.MPV_EVENT_START_FILE
	assert int(EventId.end_file) == C.MPV_EVENT_END_FILE
	assert int(EventId.file_loaded) == C.MPV_EVENT_FILE_LOADED
	assert int(EventId.idle) == C.MPV_EVENT_IDLE
	assert int(EventId.tick) == C.MPV_EVENT_TICK
	assert int(EventId.client_message) == C.MPV_EVENT_CLIENT_MESSAGE
	assert int(EventId.video_reconfig) == C.MPV_EVENT_VIDEO_RECONFIG
	assert int(EventId.audio_reconfig) == C.MPV_EVENT_AUDIO_RECONFIG
	assert int(EventId.seek) == C.MPV_EVENT_SEEK
	assert int(EventId.playback_restart) == C.MPV_EVENT_PLAYBACK_RESTART
	assert int(EventId.property_change) == C.MPV_EVENT_PROPERTY_CHANGE
	assert int(EventId.queue_overflow) == C.MPV_EVENT_QUEUE_OVERFLOW
	assert int(EventId.hook) == C.MPV_EVENT_HOOK
	assert EventId.property_change.name() == 'property-change'
}

fn test_end_file_reason_values() {
	assert int(EndFileReason.eof) == C.MPV_END_FILE_REASON_EOF
	assert int(EndFileReason.stop) == C.MPV_END_FILE_REASON_STOP
	assert int(EndFileReason.quit) == C.MPV_END_FILE_REASON_QUIT
	assert int(EndFileReason.error) == C.MPV_END_FILE_REASON_ERROR
	assert int(EndFileReason.redirect) == C.MPV_END_FILE_REASON_REDIRECT
}

fn test_log_level_values() {
	assert int(LogLevel.none) == C.MPV_LOG_LEVEL_NONE
	assert int(LogLevel.fatal) == C.MPV_LOG_LEVEL_FATAL
	assert int(LogLevel.error) == C.MPV_LOG_LEVEL_ERROR
	assert int(LogLevel.warn) == C.MPV_LOG_LEVEL_WARN
	assert int(LogLevel.info) == C.MPV_LOG_LEVEL_INFO
	assert int(LogLevel.v) == C.MPV_LOG_LEVEL_V
	assert int(LogLevel.debug) == C.MPV_LOG_LEVEL_DEBUG
	assert int(LogLevel.trace) == C.MPV_LOG_LEVEL_TRACE
}

fn test_error_code_values() {
	assert int(ErrorCode.success) == C.MPV_ERROR_SUCCESS
	assert int(ErrorCode.event_queue_full) == C.MPV_ERROR_EVENT_QUEUE_FULL
	assert int(ErrorCode.nomem) == C.MPV_ERROR_NOMEM
	assert int(ErrorCode.uninitialized) == C.MPV_ERROR_UNINITIALIZED
	assert int(ErrorCode.invalid_parameter) == C.MPV_ERROR_INVALID_PARAMETER
	assert int(ErrorCode.option_not_found) == C.MPV_ERROR_OPTION_NOT_FOUND
	assert int(ErrorCode.option_format) == C.MPV_ERROR_OPTION_FORMAT
	assert int(ErrorCode.option_error) == C.MPV_ERROR_OPTION_ERROR
	assert int(ErrorCode.property_not_found) == C.MPV_ERROR_PROPERTY_NOT_FOUND
	assert int(ErrorCode.property_format) == C.MPV_ERROR_PROPERTY_FORMAT
	assert int(ErrorCode.property_unavailable) == C.MPV_ERROR_PROPERTY_UNAVAILABLE
	assert int(ErrorCode.property_error) == C.MPV_ERROR_PROPERTY_ERROR
	assert int(ErrorCode.command) == C.MPV_ERROR_COMMAND
	assert int(ErrorCode.loading_failed) == C.MPV_ERROR_LOADING_FAILED
	assert int(ErrorCode.ao_init_failed) == C.MPV_ERROR_AO_INIT_FAILED
	assert int(ErrorCode.vo_init_failed) == C.MPV_ERROR_VO_INIT_FAILED
	assert int(ErrorCode.nothing_to_play) == C.MPV_ERROR_NOTHING_TO_PLAY
	assert int(ErrorCode.unknown_format) == C.MPV_ERROR_UNKNOWN_FORMAT
	assert int(ErrorCode.unsupported) == C.MPV_ERROR_UNSUPPORTED
	assert int(ErrorCode.not_implemented) == C.MPV_ERROR_NOT_IMPLEMENTED
	assert int(ErrorCode.generic) == C.MPV_ERROR_GENERIC
}

fn test_render_update_frame_value() {
	assert render_update_frame == u64(C.MPV_RENDER_UPDATE_FRAME)
}
