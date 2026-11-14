module main

import x.json2

const diagnostic_properties = ['hwdec-current', 'decoder-frame-drop-count', 'frame-drop-count',
	'avsync', 'demuxer-cache-duration', 'cache-buffering-state', 'paused-for-cache',
	'estimated-vf-fps', 'estimated-display-fps', 'video-bitrate', 'audio-bitrate', 'idle-active']

const diagnostic_fields = ['decoder', 'fps', 'decoderDrops', 'displayDrops', 'avsync', 'cache',
	'bufferFill', 'state', 'videoRate', 'audioRate']

fn (mut a App) request_info() {
	a.info_token++
	a.info_data.clear()
	for name in ['file-format', 'duration', 'file-size', 'video-codec', 'video-format',
		'video-params/w', 'video-params/h', 'container-fps', 'video-bitrate',
		'video-params/pixelformat', 'video-params/colormatrix', 'video-params/primaries',
		'video-params/gamma', 'track-list'] {
		a.read_property_action(name, PlaybackAction{
			kind:     'info'
			revision: a.revision
			token:    a.info_token
			name:     name
		})
	}
}

fn stat_number(data map[string]json2.Any, key string, digits int, unit string) string {
	value := get(data, key)
	if value is json2.Null { return '—' }
	n := number(value)
	return if digits == 0 { '${n:.0f}${unit}' } else { '${n:.1f}${unit}' }
}

fn diagnostic_values(data map[string]json2.Any, playback map[string]json2.Any, has_media bool,
	t &Translator) map[string]string {
	decoder := text_value(get(data, 'hwdec-current'))
	avsync := get(data, 'avsync')
	return {
		'decoder':      if decoder == 'no' {
			t.tr('stats.software')
		} else if decoder == '' {
			'—'
		} else {
			decoder
		}
		'fps':          stat_number(data, 'estimated-vf-fps', 1, ' fps') + ' / ' +
			stat_number(data, 'estimated-display-fps', 1, ' Hz')
		'decoderDrops': stat_number(data, 'decoder-frame-drop-count', 0, '')
		'displayDrops': stat_number(data, 'frame-drop-count', 0, '')
		'avsync':       if avsync is json2.Null {
			'—'
		} else {
			'${number(avsync) * 1000:.1f} ms'
		}
		'cache':        stat_number(data, 'demuxer-cache-duration', 1, ' s')
		'bufferFill':   stat_number(data, 'cache-buffering-state', 0, '%')
		'state':        t.tr(if !has_media || truth(get(data, 'idle-active')) {
			'stats.idle'
		} else if truth(get(data, 'paused-for-cache')) {
			'stats.buffering'
		} else if truth(get(playback, 'pause')) {
			'stats.paused'
		} else {
			'stats.playing'
		})
		'videoRate':    if get(data, 'video-bitrate') is json2.Null {
			'—'
		} else {
			bitrate(number(get(data, 'video-bitrate')))
		}
		'audioRate':    if get(data, 'audio-bitrate') is json2.Null {
			'—'
		} else {
			bitrate(number(get(data, 'audio-bitrate')))
		}
	}
}

fn (mut a App) statistics_panel() []json2.Any {
	a.info_fields.clear()
	values := diagnostic_values(a.statistics, a.properties, a.has_media, &a.t)
	mut body := [a.section(a.t.tr('stats.title'))]
	for key in diagnostic_fields {
		value := a.ui.create('Text', {
			'value':      json2.Any(values[key])
			'size':       12
			'color':      '#EEEEF0'
			'expand':     true
			'selectable': true
		})
		a.info_fields[key] = get(object(value), '_i').int()
		body << a.row([
			a.ui.create('Text', {
				'value': json2.Any(a.t.tr('stats.' + key))
				'width': 122
				'size':  12
				'color': '#92929C'
			}),
			value,
		])
	}
	return body
}

// Update existing text controls at most once per second. Neither a synchronous
// mpv read nor rebuilding the scrollable panel is needed for live statistics.
fn (mut a App) refresh_statistics(now i64) {
	values := diagnostic_values(a.statistics, a.properties, a.has_media, &a.t)
	for key, id in a.info_fields {
		a.ui.set_id(id, 'value', values[key])
	}
	a.info_refresh_at = now + 1000
}
