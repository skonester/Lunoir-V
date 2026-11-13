module main

import os
import time
import x.json2

fn test_youtube_hls_retry_formats_and_hosts() {
	assert is_youtube_url('https://www.youtube.com/watch?v=A7kKxad9tWM')
	assert is_youtube_url('https://youtu.be/A7kKxad9tWM')
	assert !is_youtube_url('https://youtube.com.example.test/watch?v=A7kKxad9tWM')
	assert !is_youtube_url('https://example.test/youtube.com')
	assert !youtube_hls_format('best').contains('height')
	assert youtube_hls_format('720').count('[height<=?720]') == 3
	assert youtube_hls_format('720').contains('bestaudio[protocol^=m3u8]')
}

// Exercise end-file arriving before its HTTP log message, without starting mpv
// or opening any media. The disconnected controller keeps this a state-only check.
fn test_youtube_retry_collects_late_http_error_and_is_bounded() {
	temporary := os.join_path(os.temp_dir(), 'lunoir-ytdl-state-${time.now().unix_micro()}')
	previous_logs := os.getenv('LOCALAPPDATA')
	os.setenv('LOCALAPPDATA', temporary, true)
	defer {
		os.setenv('LOCALAPPDATA', previous_logs, true)
		os.rmdir_all(temporary) or {}
	}
	t := new_translator(os.dir(os.dir(@FILE)), 'en')
	mut a := App{
		t:       t
		ui:      new_flet(&t)
		profile: Profile{
			settings: {
				'streamQuality': json2.Any('720')
			}
		}
		current: 'https://www.youtube.com/watch?v=A7kKxad9tWM'
	}
	a.handle_event({
		'event':  json2.Any('end-file')
		'reason': 'error'
	})
	assert a.load_failed_at > 0 && !a.ytdl_hls_retry
	a.handle_event({
		'event':  json2.Any('log-message')
		'prefix': 'ffmpeg'
		'text':   'https: HTTP error 403 Forbidden'
	})
	assert a.ytdl_http_error == 'HTTP 403 Forbidden'
	a.finish_failed_load()
	assert a.ytdl_hls_retry
	a.ytdl_http_error = 'HTTP 403 Forbidden'
	assert !a.retry_youtube_hls()
}
