module main

import os
import x.json2

const applied_settings = ['deinterlace', 'hwdec', 'audioLang', 'subLang', 'subsDefaultOn',
	'autoLoadSubs', 'subCodepage', 'subFont', 'subFontSize', 'subSpacing', 'subBold', 'subOutline',
	'subMarginY', 'subHdrPeak', 'keepPitch', 'streamQuality', 'useCookies', 'audioPassthrough',
	'screenshotDir', 'screenshotFormat']

struct Property {
	name  string
	value json2.Any
}

fn sub_font_chain(value string) string {
	font := value.trim_space()
	if font == '' || font == 'sans-serif' { return 'sans-serif' }
	return if font == 'Microsoft YaHei' { font } else { '${font},Microsoft YaHei' }
}

fn screenshot_dir(settings map[string]json2.Any) string {
	directory := text_value(get(settings, 'screenshotDir'))
	return if directory != '' { directory } else { os.join_path(pictures_folder(), 'Lunoir') }
}

fn properties_for(key string, settings map[string]json2.Any) []Property {
	value := get(settings, key)
	direct := {
		'deinterlace': 'deinterlace'
		'hwdec':       'hwdec'
		'audioLang':   'alang'
		'subLang':     'slang'
		'subCodepage': 'sub-codepage'
		'subSpacing':  'sub-spacing'
		'subOutline':  'sub-outline-size'
	}
	if name := direct[key] { return [Property{ name: name, value: value }] }
	match key {
		'subsDefaultOn' {
			return [Property{'sub-visibility', truth(value)}]
		}
		'autoLoadSubs' {
			return [Property{'sub-auto', if truth(value) { 'fuzzy' } else { 'no' }}]
		}
		'subFont' {
			return if truth(value) { [
					Property{'sub-font', sub_font_chain(text_value(value))},
				] } else { []Property{} }
		}
		'subFontSize' {
			return if number(value) > 0 { [Property{'sub-font-size', value}] } else { []Property{} }
		}
		'subBold' {
			return [Property{'sub-bold', truth(value)}]
		}
		'subMarginY' {
			return [Property{'sub-margin-y', int(number(value))}]
		}
		'subHdrPeak' {
			return [Property{'sub-hdr-peak', value}, Property{'image-subs-hdr-peak', value}]
		}
		'keepPitch' {
			return [Property{'audio-pitch-correction', truth(value)}]
		}
		'streamQuality' {
			formats := {
				'best': 'bestvideo+bestaudio/best'
				'2160': 'bestvideo[height<=?2160]+bestaudio/best[height<=?2160]'
				'1080': 'bestvideo[height<=?1080]+bestaudio/best[height<=?1080]'
				'720':  'bestvideo[height<=?720]+bestaudio/best[height<=?720]'
				'480':  'bestvideo[height<=?480]+bestaudio/best[height<=?480]'
			}
			return [Property{'ytdl-format', formats[text_value(value)] or { '' }}]
		}
		'useCookies', 'cookiesBrowser' {
			return [
				Property{'ytdl-raw-options', if truth(get(settings, 'useCookies')) {
					'cookies-from-browser=' + text_value(get(settings, 'cookiesBrowser'))
				} else {
					''
				}},
			]
		}
		'audioPassthrough', 'passthroughCodecs' {
			return [
				Property{'audio-spdif', if truth(get(settings, 'audioPassthrough')) {
					text_value(get(settings, 'passthroughCodecs'))
				} else {
					''
				}},
			]
		}
		'screenshotDir' {
			return [Property{'screenshot-directory', screenshot_dir(settings)}]
		}
		'screenshotFormat' {
			mut result := [Property{'screenshot-format', value}]
			if text_value(value) == 'jpg' { result << Property{'screenshot-jpeg-quality', 95} }
			return result
		}
		else {
			return []Property{}
		}
	}
}

fn startup_properties(settings map[string]json2.Any) []Property {
	mut result := []Property{}
	for key in applied_settings {
		result << properties_for(key, settings)
	}
	if truth(get(settings, 'rememberVolume')) {
		result << Property{'volume', get(settings, 'volume')}
	}
	return result
}
