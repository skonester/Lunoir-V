module py_flet_lunoir

import regex
import os

// TODO(py2v): no V equivalent for import ctypes, locale
// Provide one in python_to_v_import (types.v) or port the module.

// TODO(py2v): no V mapping for ctypes.create_unicode_buffer
// Each site below is stubbed with a zero value.

// TODO(py2v): 2 except handler(s) need a V Result equivalent:
//   except AttributeError | OSError (1 stmt)
//   except OSError (1 stmt)

const i18n_dir = ROOT / 'lunoir/src/shared/i18n'
const locales = ['en', 'zh-CN', 'fr', 'de', 'es', 'pt', 'ru', 'ja', 'ko']
const lang_options = [
	['system', 'System'],
	['en', 'English'],
	['zh-CN', '简体中文'],
	['fr', 'Français'],
	['de', 'Deutsch'],
	['es', 'Español'],
	['pt', 'Português'],
	['ru', 'Русский'],
	['ja', '日本語'],
	['ko', '한국어'],
]
const entry_ = regex.regex_opt('^\\s*\'([^\']+)\'\\s*:\\s*(\'(?:[^\'\\\\\\n]|\\\\.)*\'|"(?:[^"\\\\\\n]|\\\\.)*")') or {
	panic(err)
}
const escape_ = regex.regex_opt('\\\\(u\\{[0-9a-fA-F]+\\}|u[0-9a-fA-F]{4}|x[0-9a-fA-F]{2}|.)') or {
	panic(err)
}
const simple_ = {
	'n': '\n'
	't': '\t'
	'r': '\r'
	'b': '\x08'
	'f': '\x0c'
	'v': '\x0b'
	'0': '\x00'
}
// TODO(py2v): module-level statement has no place in a V module; move it into a function and call it explicitly.

pub struct Translator {
pub mut:
	system_tag Any
	strings    Any
	fallback   Any
	locale     Any
}

pub fn (mut self Translator) init(setting string, system_tag ?string) {
	self.system_tag = system_tag
	self.set_language(setting)
}

pub fn (mut self Translator) set_language(setting string) {
	if (setting in locales) {
		self.locale = setting
	} else {
		self.locale = resolve_system_locale(self.system_tag || system_locale_tag())
	}
	self.strings = dictionary(self.locale)
	self.fallback = dictionary('en')
}

pub fn (self Translator) call____(key string, values map[string]Any) string {
	mut text := self.strings.get(key) || self.fallback.get(key) || key
	if values {
		text = (regex.regex_opt('\\{(\\w+)\\}') or { panic(err) }).replace(text, fn (m string) string {
			return values.get(m.group(1), m.group(0))
		})
	}
	return text
}

pub fn replace(@match Match) string {
	code := @match.group(1)
	if 'ux'.contains(code[0]) && code.len > 1 {
		return rune(int(code[1..].trim_space()))
	}
	return simple_.get(code, code)
}

pub fn unescape_(body string) string {
	return escape_.sub(replace, body)
}

pub fn parse_locale(text string) map[string]string {
	return fn () map[string]string {
		mut result := map[string]string{}
		for [key, value] in entry_.findall(text) {
			result[key] = unescape_(value[1..value.len - 1])
		}
		return result
	}()
}

pub fn resolve_system_locale(tag string) string {
	tag = tag.replace('_', '-')
	if (regex.regex_opt('^zh(-)?(hans|cn|sg)?$') or { panic(err) }).match_string(tag) || (regex.regex_opt('^zh-hans') or {
		panic(err)
	}).match_string(tag) {
		return 'zh-CN'
	}
	base := tag[..2].to_lower()
	return if (base in ['fr', 'de', 'es', 'pt', 'ru', 'ja', 'ko']) { base } else { 'en' }
}

pub fn system_locale_tag() string {
	kernel := ctypes.windll.kernel32
	buffer := Any(0)
	if kernel.LCIDToLocaleName(kernel.GetUserDefaultUILanguage(), buffer, 85, 0) {
		return buffer.value
	}
	// except handlers are not translated: see the TODO(py2v) note above
	//   except AttributeError | OSError: 1 statement(s) need an `or { ... }` equivalent
	return pylocale.getlocale()[0] || 'en'
}

pub fn dictionary(code string) map[string]string {
	if (code !in cache_) {
		cache_[code] = parse_locale(os.read_file((i18n_dir / '${code}.ts')) or { '' })
		// except handlers are not translated: see the TODO(py2v) note above
		//   except OSError: 1 statement(s) need an `or { ... }` equivalent
	}
	return cache_[code]
}
