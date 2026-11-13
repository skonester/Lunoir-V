module py_flet_lunoir

import os

// TODO(py2v): no V equivalent for import win32com.shell
// Provide one in python_to_v_import (types.v) or port the module.

// TODO(py2v): 1 except handler(s) need a V Result equivalent:
//   except Exception (1 stmt)

const sub_font_fallback = 'Microsoft YaHei'
const ytdl_format = {
	'best': 'bestvideo+bestaudio/best'
	'2160': 'bestvideo[height<=?2160]+bestaudio/best[height<=?2160]'
	'1080': 'bestvideo[height<=?1080]+bestaudio/best[height<=?1080]'
	'720':  'bestvideo[height<=?720]+bestaudio/best[height<=?720]'
	'480':  'bestvideo[height<=?480]+bestaudio/best[height<=?480]'
}
const applied = ['deinterlace', 'hwdec', 'audioLang', 'subLang', 'subsDefaultOn', 'autoLoadSubs',
	'subCodepage', 'subFont', 'subFontSize', 'subSpacing', 'subBold', 'subOutline', 'subMarginY',
	'subHdrPeak', 'keepPitch', 'streamQuality', 'useCookies', 'audioPassthrough', 'screenshotDir',
	'screenshotFormat']

pub fn sub_font_chain(font string) string {
	font = (font || '').trim_space()
	if !font || font == 'sans-serif' {
		return 'sans-serif'
	}
	return if font == sub_font_fallback { font } else { '${font},${sub_font_fallback}' }
}

pub fn pictures_folder() Path {
	return shell.SHGetFolderPath(0, shellcon.CSIDL_MYPICTURES, none, 0)
	// except handlers are not translated: see the TODO(py2v) note above
	//   except Exception: 1 statement(s) need an `or { ... }` equivalent
}

pub fn screenshot_dir(settings map[string]Any) string {
	return (settings['screenshotDir'] or { none }) || pictures_folder() / 'Lunoir'
}

// NOTE: Tuple[string, object] — define a struct with named fields
pub fn properties_for(key string, s map[string]Any) [][]Any {
	if key == 'deinterlace' {
		return [['deinterlace', s['deinterlace']]]
	}
	if key == 'hwdec' {
		return [['hwdec', s['hwdec']]]
	}
	if key == 'audioLang' {
		return [['alang', s['audioLang']]]
	}
	if key == 'subLang' {
		return [['slang', s['subLang']]]
	}
	if key == 'subsDefaultOn' {
		return [['sub-visibility', (s['subsDefaultOn'] != 0)]]
	}
	if key == 'autoLoadSubs' {
		return [['sub-auto', if s['autoLoadSubs'] {
			'fuzzy'
		} else {
			'no'
		}]]
	}
	if key == 'subCodepage' {
		return [['sub-codepage', s['subCodepage']]]
	}
	if key == 'subFont' {
		return if s['subFont'] { [['sub-font', sub_font_chain(s['subFont'])]] } else { [] }
	}
	if key == 'subFontSize' {
		return if s['subFontSize'] > 0 { [['sub-font-size', s['subFontSize']]] } else { [] }
	}
	if key == 'subSpacing' {
		return [['sub-spacing', s['subSpacing']]]
	}
	if key == 'subBold' {
		return [['sub-bold', (s['subBold'] != 0)]]
	}
	if key == 'subOutline' {
		return [['sub-outline-size', s['subOutline']]]
	}
	if key == 'subMarginY' {
		return [['sub-margin-y', int(s['subMarginY'])]]
	}
	if key == 'subHdrPeak' {
		return [['sub-hdr-peak', s['subHdrPeak']], ['image-subs-hdr-peak', s['subHdrPeak']]]
	}
	if key == 'keepPitch' {
		return [['audio-pitch-correction', (s['keepPitch'] != 0)]]
	}
	if key == 'streamQuality' {
		return [['ytdl-format', ytdl_format.get(s['streamQuality'], '')]]
	}
	if (key in ['useCookies', 'cookiesBrowser']) {
		return [
			['ytdl-raw-options', if s['useCookies'] {
				'cookies-from-browser=${s['cookiesBrowser']}'
			} else {
				''
			}],
		]
	}
	if (key in ['audioPassthrough', 'passthroughCodecs']) {
		return [
			['audio-spdif', if s['audioPassthrough'] {
				s['passthroughCodecs']
			} else {
				''
			}],
		]
	}
	if key == 'screenshotDir' {
		return [['screenshot-directory', screenshot_dir(s)]]
	}
	if key == 'screenshotFormat' {
		mut result := [['screenshot-format', s['screenshotFormat']]]
		if s['screenshotFormat'] == 'jpg' {
			result << ['screenshot-jpeg-quality', 95]
		}
		return result
	}
	return []
}

// NOTE: Tuple[string, object] — define a struct with named fields
pub fn startup_properties(s map[string]Any) [][]Any {
	mut result := []
	for key in applied {
		result << properties_for(key, s)
	}
	if s['rememberVolume'] or { none } {
		result << ['volume', s['volume']]
	}
	return result
}
