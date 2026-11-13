module main

import math

fn finite(value f64) f64 {
	return if math.is_nan(value) || math.is_inf(value, 0) { 0.0 } else { value }
}

fn clock(seconds f64) string {
	total := i64(math.max(0.0, finite(seconds)))
	hours := total / 3600
	minutes, secs := total / 60 % 60, total % 60
	return if hours > 0 { '${hours}:${minutes:02}:${secs:02}' } else { '${minutes:02}:${secs:02}' }
}

fn duration_text(seconds f64) string {
	total := i64(math.max(0.0, finite(seconds)))
	return if total >= 3600 { clock(seconds) } else { '${total / 60}:${total % 60:02}' }
}

fn current_frame(frame_number f64, position f64, fps f64) i64 {
	if finite(frame_number) > 0 { return i64(math.round_to_even(frame_number)) }
	if finite(fps) > 0 && finite(position) > 0 { return i64(math.floor(position * fps)) }
	return 0
}

fn timecode(frame_index i64, fps f64) string {
	mut rate := i64(math.round_to_even(finite(fps)))
	if rate == 0 { rate = 24 }
	if rate < 1 { rate = 1 }
	frame := if frame_index < 0 { i64(0) } else { frame_index }
	secs := frame / rate
	return '${secs / 3600:02}:${secs / 60 % 60:02}:${secs % 60:02}:${frame % rate:02}'
}

fn channel_layout(channels f64) string {
	count := int(finite(channels))
	if count >= 8 { return '7.1' }
	return {
		7: '6.1'
		6: '5.1'
		3: '2.1'
		2: '2.0'
		1: 'Mono'
	}[count] or { '' }
}

fn audio_badge(codec string, channels f64) string {
	if codec == '' { return '' }
	lower := codec.to_lower()
	names := {
		'truehd': 'TrueHD'
		'eac3':   'DD+'
		'ac3':    'DD'
		'dts':    'DTS'
		'aac':    'AAC'
		'flac':   'FLAC'
		'alac':   'ALAC'
		'opus':   'Opus'
		'vorbis': 'Vorbis'
		'mp3':    'MP3'
	}
	name := names[lower] or {
		if lower.starts_with('pcm') { 'PCM' } else { codec.to_upper() }
	}
	layout := channel_layout(channels)
	return if layout == '' { name } else { '${name} ${layout}' }
}

fn hdr_label(gamma string) string {
	return if gamma.to_lower() in ['pq', 'st2084', 'hlg'] { 'HDR' } else { '' }
}

fn resolution_tier(width f64, height f64) int {
	tier := int(math.max(finite(height), math.round_to_even(finite(width) * 9 / 16)))
	mut best := 0
	for standard in [4320, 2160, 1440, 1080, 720, 576, 540, 480, 360, 240] {
		if f64(math.abs(tier - standard)) <= f64(standard) * 0.06
			&& (best == 0 || math.abs(tier - standard) < math.abs(tier - best)) {
			best = standard
		}
	}
	return if best != 0 { best } else { tier }
}

fn total_channels(channels f64) string {
	count := int(finite(channels))
	return {
		1:  '1.0'
		2:  '2.0'
		3:  '2.1'
		4:  '4.0'
		5:  '4.1'
		6:  '5.1'
		7:  '6.1'
		8:  '7.1'
		10: '9.1'
		12: '11.1'
	}[count] or { '${count} ch' }
}

fn bitrate(value f64) string {
	n := finite(value)
	if n >= 1000000 { return '${n / 1000000:.1f} Mbps' }
	if n >= 1000 { return '${n / 1000:.0f} kbps' }
	return '${n:.0f} bps'
}

fn file_size(value f64) string {
	n := finite(value)
	if n >= 1073741824 { return '${n / 1073741824:.2f} GB' }
	if n >= 1048576 { return '${n / 1048576:.1f} MB' }
	if n >= 1024 { return '${n / 1024:.0f} KB' }
	return '${n:.0f} B'
}

fn clean_base_name(file_name string) string {
	mut name := file_name
	if dot := name.last_index('.') { name = name[..dot] }
	mut cut := -1
	for i, ch in name.bytes() {
		if ch !in [u8(32), 9, 10, 13, `.`, `_`, `-`] { continue
		 }
		suffix := name[i + 1..].to_lower()
		if technical_tag(suffix) {
			cut = i
			break
		}
	}
	if cut > 0 { name = name[..cut] }
	name = name.trim_right('. \t\r\n_-')
	runes := name.runes()
	if runes.len > 50 { name = runes[..50].string().trim_right('. \t\r\n_-') }
	return name.replace('%', '')
}

fn screenshot_template(file_name string, position f64) string {
	seconds := i64(math.max(0.0, finite(position)))
	mut base := clean_base_name(file_name)
	if base == '' { base = '%F' }
	return '${base}_${seconds / 3600:02}-${seconds / 60 % 60:02}-${seconds % 60:02}_%ty%tm%td_%tH%tM%tS'
}

fn technical_tag(suffix string) bool {
	for tag in ['4k', 'webdl', 'web-dl', 'webrip', 'web-rip', 'bluray', 'blu-ray', 'bdrip', 'bd-rip',
		'brrip', 'br-rip', 'hdtv', 'remux', 'dvdrip', 'x264', 'x265', 'h264', 'h265', 'h.264',
		'h.265', 'hevc', 'avc', 'xvid', 'aac', 'ac3', 'ac-3', 'eac3', 'e-ac3', 'eac-3', 'e-ac-3',
		'dd', 'dts', 'truehd', 'atmos', 'flac', 'opus', 'hdr', 'dv', 'hi10', 'repack', 'proper',
		'internal'] {
		if suffix.starts_with(tag) { return true }
	}
	mut n := 0
	for n < suffix.len && suffix[n].is_digit() {
		n++
	}
	if n == 0 { return false }
	tail := suffix[n..]
	return (n >= 3 && n <= 4 && tail.starts_with('p'))
		|| (n <= 2 && tail.starts_with('bit')) || tail.starts_with('audio')
}
