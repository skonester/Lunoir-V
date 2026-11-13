module main

import os

const locales = ['en', 'zh-CN', 'fr', 'de', 'es', 'pt', 'ru', 'ja', 'ko']

struct Translator {
mut:
	locale   string
	strings  map[string]string
	fallback map[string]string
	root     string
}

fn parse_locale(source string) map[string]string {
	mut result := map[string]string{}
	data := json_decode(source) or { return result }
	for key, value in object(data) {
		if value is string { result[key] = value }
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
	directory := os.join_path(t.root, 'lunoir', 'i18n')
	t.strings = parse_locale(os.read_file(os.join_path(directory, t.locale + '.json')) or { '' })
	t.fallback = parse_locale(os.read_file(os.join_path(directory, 'en.json')) or { '' })
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
