module main

import os
import strconv

const locales = ['en', 'zh-CN', 'fr', 'de', 'es', 'pt', 'ru', 'ja', 'ko']

struct Translator {
mut:
	locale   string
	strings  map[string]string
	fallback map[string]string
	root     string
}

fn unescape_ts(text string) string {
	mut result := []u8{}
	mut i := 0
	for i < text.len {
		if text[i] != `\\` || i + 1 >= text.len {
			result << text[i]
			i++
			continue
		}
		i++
		code := text[i]
		i++
		if code in [`u`, `x`] {
			mut end := i + if code == `u` { 4 } else { 2 }
			mut start := i
			if i < text.len && text[i] == `{` {
				start = i + 1
				end = start
				for end < text.len && text[end] != `}` {
					end++
				}
			}
			if end <= text.len {
				value := strconv.parse_uint(text[start..end], 16, 32) or { 0xfffd }
				result << rune(value).str().bytes()
				i = end + if start != i { 1 } else { 0 }
			}
		} else {
			result << match code {
				`n` { u8(10) }
				`r` { u8(13) }
				`t` { u8(9) }
				`b` { u8(8) }
				`f` { u8(12) }
				`v` { u8(11) }
				`0` { u8(0) }
				else { code }
			}
		}
	}
	return result.bytestr()
}

fn parse_locale(source string) map[string]string {
	mut result := map[string]string{}
	lines := source.split_into_lines()
	for n, raw in lines {
		line := raw.trim_space()
		if !line.starts_with("'") { continue
		 }
		end := line[1..].index("'") or { continue }
		key := line[1..end + 1]
		mut rest := line[end + 2..].trim_space()
		if !rest.starts_with(':') { continue
		 }
		rest = rest[1..].trim_space()
		if rest == '' && n + 1 < lines.len { rest = lines[n + 1].trim_space() }
		if rest.len < 2 || rest[0] !in [`'`, `"`] { continue
		 }
		quote := rest[0]
		mut i := 1
		for i < rest.len {
			if rest[i] == `\\` {
				i += 2
				continue
			}
			if rest[i] == quote { break
			 }
			i++
		}
		if i < rest.len { result[key] = unescape_ts(rest[1..i]) }
	}
	return result
}

fn resolve_system_locale(raw string) string {
	tag := raw.replace('_', '-').to_lower()
	if tag in ['zh', 'zh-cn', 'zh-sg', 'zh-hans', 'zhhans', 'zhcn', 'zhsg']
		|| tag.starts_with('zh-hans') {
		return 'zh-CN'
	}
	base := if tag.len >= 2 { tag[..2] } else { tag }
	return if base in ['fr', 'de', 'es', 'pt', 'ru', 'ja', 'ko'] { base } else { 'en' }
}

fn new_translator(root string, setting string) Translator {
	mut t := Translator{
		root: root
	}
	t.set_language(setting)
	return t
}

fn (mut t Translator) set_language(setting string) {
	t.locale = if setting in locales { setting } else { resolve_system_locale(system_locale()) }
	directory := os.join_path(t.root, 'lunoir', 'src', 'shared', 'i18n')
	t.strings = parse_locale(os.read_file(os.join_path(directory, t.locale + '.ts')) or { '' })
	t.fallback = parse_locale(os.read_file(os.join_path(directory, 'en.ts')) or { '' })
}

fn (t &Translator) tr(key string) string {
	return t.strings[key] or { t.fallback[key] or { key } }
}

fn (t &Translator) format(key string, values map[string]string) string {
	mut result := t.tr(key)
	for name, value in values {
		result = result.replace('{${name}}', value)
	}
	return result
}
