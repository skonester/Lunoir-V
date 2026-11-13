module py_flet_lunoir

import math
import regex
import arrays

const tech_tag = regex.regex_opt('[.\\s_-](\\d{3,4}p|4k|web-?dl|web-?rip|blu-?ray|bd-?rip|br-?rip|hdtv|remux|dvdrip|x26[45]|h\\.?26[45]|hevc|avc|xvid|aac\\d?|ac-?3|e-?ac-?3|ddp?\\d?|dts(-hd)?|truehd|atmos|flac|opus|\\d{1,2}bits?|hdr\\d*\\+?|dv|hi10p?|repack|proper|internal|\\d+audio)') or { panic(err) }
const time_formats = ['time', 'timecode', 'frame']
const codec_short = {
	'truehd': 'TrueHD',
	'eac3': 'DD+',
	'ac3': 'DD',
	'dts': 'DTS',
	'aac': 'AAC',
	'flac': 'FLAC',
	'alac': 'ALAC',
	'opus': 'Opus',
	'vorbis': 'Vorbis',
	'mp3': 'MP3',
}

pub fn number_(value Any) f64 {
	return if (value is int || value is float) && math.isfinite(value) { f64(value) } else { 0 }
}

pub fn clock(seconds Any) string {
	total := arrays.max([0, int(number_(seconds))]) or { panic('!') }
	py2v_unpack1 := (total / 3600, total % 3600)
	mut hours := py2v_unpack1[0]
	mut rest := py2v_unpack1[1]
	py2v_unpack2 := (rest / 60, rest % 60)
	mut minutes := py2v_unpack2[0]
	mut secs := py2v_unpack2[1]
	return if hours { '${hours}:${minutes}:${secs}' } else { '${minutes}:${secs}' }
}

pub fn duration_text(seconds Any) string {
	total := arrays.max([0, int(number_(seconds))]) or { panic('!') }
	py2v_unpack3 := (total / 3600, total % 3600)
	mut hours := py2v_unpack3[0]
	mut rest := py2v_unpack3[1]
	py2v_unpack4 := (rest / 60, rest % 60)
	mut minutes := py2v_unpack4[0]
	mut secs := py2v_unpack4[1]
	return if hours { '${hours}:${minutes}:${secs}' } else { '${minutes}:${secs}' }
}

pub fn current_frame(frame_number Any, position Any, fps Any) int {
	if number_(frame_number) > 0 {
		return math.round(frame_number)
	}
	if number_(fps) > 0 && number_(position) > 0 {
		return math.floor(position * fps)
	}
	return 0
}

pub fn timecode(frame int, fps Any) string {
	rate := arrays.max([1, math.round(number_(fps)) || 24]) or { panic('!') }
	frame = arrays.max([0, int(frame)]) or { panic('!') }
	secs := math.divide_floored(frame, rate).quot
	return '${math.divide_floored(secs, 3600).quot}:${math.divide_floored(secs, 60).quot % 60}:${secs % 60}:${frame % rate}'
}

pub fn channel_layout(count Any) string {
	count = int(number_(count))
	if count >= 8 {
		return '7.1'
	}
	return {
		7: '6.1',
		6: '5.1',
		3: '2.1',
		2: '2.0',
		1: 'Mono',
	}[count] or { '' }
}

pub fn audio_badge(codec string, channels Any) string {
	if !codec {
		return ''
	}
	lower := codec.to_lower()
	name := codec_short.get(lower) || (if lower.starts_with('pcm') { 'PCM' } else { codec.to_upper() })
	layout := channel_layout(channels)
	return if layout { '${name} ${layout}' } else { name }
}

pub fn hdr_label(gamma Any) string {
	return if ((gamma || '').to_lower() in ['pq', 'st2084', 'hlg']) { 'HDR' } else { '' }
}

pub fn resolution_tier(width Any, height Any) int {
	width, height = int(number_(width)), int(number_(height))
	tier := arrays.max([height, if width > 0 { math.round(width * 9 / 16) } else { 0 }]) or { panic('!') }
	mut best := 0
	for standard in [4320, 2160, 1440, 1080, 720, 576, 540, 480, 360, 240] {
		if math.abs(tier - standard) <= standard * 0.06 && (!best || math.abs(tier - standard) < math.abs(tier - best)) {
			best = standard
		}
	}
	return best || tier
}

pub fn total_channels(count Any) string {
	count = int(number_(count))
	names := {
		1: '1.0',
		2: '2.0',
		3: '2.1',
		4: '4.0',
		5: '4.1',
		6: '5.1',
		7: '6.1',
		8: '7.1',
		10: '9.1',
		12: '11.1',
	}
	return names[count] or { '${count} ch' }
}

pub fn bitrate(bps Any) string {
	bps = number_(bps)
	if bps >= 1000000 {
		return '${bps / f64(1000000)} Mbps'
	}
	if bps >= 1000 {
		return '${bps / f64(1000)} kbps'
	}
	return '${bps} bps'
}

pub fn file_size(size Any) string {
	size = number_(size)
	if size >= 1073741824 {
		return '${size / f64(1073741824)} GB'
	}
	if size >= 1048576 {
		return '${size / f64(1048576)} MB'
	}
	if size >= 1024 {
		return '${size / f64(1024)} KB'
	}
	return '${size} B'
}

pub fn clean_base_name(file_name string) string {
	mut name := (regex.regex_opt('\\.[^.]+$') or { panic(err) }).replace(file_name || '', '')
	@match := tech_tag.search(name)
	if @match && @match.start() {
		name = name[..@match.start()]
	}
	name = (regex.regex_opt('[.\\s_-]+$') or { panic(err) }).replace(name, '')
	if name.len > 50 {
		name = (regex.regex_opt('[.\\s_-]+$') or { panic(err) }).replace(name[..50], '')
	}
	return name.replace('%', '')
}

pub fn screenshot_template(file_name string, position Any) string {
	seconds := arrays.max([0, int(number_(position))]) or { panic('!') }
	where := '${math.divide_floored(seconds, 3600).quot}-${math.divide_floored(seconds, 60).quot % 60}-${seconds % 60}'
	return '${clean_base_name(file_name) || '%F'}_${where}_%ty%tm%td_%tH%tM%tS'
}
