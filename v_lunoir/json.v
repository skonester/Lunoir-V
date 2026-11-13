module main

import math
import x.json2
import strconv
import strings

// The existing host JSON parser, reused for settings and Flet data.
// Integers stay i64; JSON null remains explicit.

struct JsonParser {
	s string
mut:
	pos int
}

fn json_decode(s string) !json2.Any {
	mut p := JsonParser{
		s: s
	}
	v := p.value()!
	p.skip_ws()
	if p.pos != s.len {
		return error('trailing data at ${p.pos}')
	}
	return v
}

fn (mut p JsonParser) skip_ws() {
	for p.pos < p.s.len && p.s[p.pos] in [` `, `\t`, `\n`, `\r`] {
		p.pos++
	}
}

fn (mut p JsonParser) value() !json2.Any {
	p.skip_ws()
	if p.pos >= p.s.len {
		return error('unexpected end')
	}
	c := p.s[p.pos]
	match c {
		`{` {
			return p.object()
		}
		`[` {
			return p.array()
		}
		`"` {
			return p.string_lit()!
		}
		`t` {
			p.literal('true')!
			return true
		}
		`f` {
			p.literal('false')!
			return false
		}
		`n` {
			p.literal('null')!
			return json2.Null{}
		}
		else {
			if c == `-` || c.is_digit() {
				return p.number()
			}
			return error('unexpected `${c.ascii_str()}` at ${p.pos}')
		}
	}
}

fn (mut p JsonParser) literal(word string) ! {
	if !p.s[p.pos..].starts_with(word) {
		return error('bad literal at ${p.pos}')
	}
	p.pos += word.len
}

fn (mut p JsonParser) expect(c u8) ! {
	p.skip_ws()
	if p.pos >= p.s.len || p.s[p.pos] != c {
		return error('expected `${c.ascii_str()}` at ${p.pos}')
	}
	p.pos++
}

fn (mut p JsonParser) object() !json2.Any {
	p.pos++
	mut out := map[string]json2.Any{}
	p.skip_ws()
	if p.pos < p.s.len && p.s[p.pos] == `}` {
		p.pos++
		return out
	}
	for {
		p.skip_ws()
		if p.pos >= p.s.len || p.s[p.pos] != `"` {
			return error('expected key at ${p.pos}')
		}
		key := p.string_lit()!
		p.expect(`:`)!
		out[key] = p.value()!
		p.skip_ws()
		if p.pos < p.s.len && p.s[p.pos] == `,` {
			p.pos++
			continue
		}
		p.expect(`}`)!
		return out
	}
	return out
}

fn (mut p JsonParser) array() !json2.Any {
	p.pos++
	mut out := []json2.Any{}
	p.skip_ws()
	if p.pos < p.s.len && p.s[p.pos] == `]` {
		p.pos++
		return out
	}
	for {
		out << p.value()!
		p.skip_ws()
		if p.pos < p.s.len && p.s[p.pos] == `,` {
			p.pos++
			continue
		}
		p.expect(`]`)!
		return out
	}
	return out
}

fn (mut p JsonParser) string_lit() !string {
	p.pos++
	mut sb := strings.new_builder(16)
	for p.pos < p.s.len {
		c := p.s[p.pos]
		p.pos++
		if c == `"` {
			return sb.str()
		}
		if c != `\\` {
			sb.write_u8(c)
			continue
		}
		if p.pos >= p.s.len {
			break
		}
		e := p.s[p.pos]
		p.pos++
		match e {
			`"`, `\\`, `/` { sb.write_u8(e) }
			`b` { sb.write_u8(8) }
			`f` { sb.write_u8(12) }
			`n` { sb.write_u8(`\n`) }
			`r` { sb.write_u8(`\r`) }
			`t` { sb.write_u8(`\t`) }
			`u` { sb.write_string(p.unicode_escape()!) }
			else { return error('bad escape at ${p.pos}') }
		}
	}
	return error('unterminated string')
}

fn (mut p JsonParser) hex4() !u32 {
	if p.pos + 4 > p.s.len {
		return error('short \\u escape')
	}
	v := strconv.parse_uint(p.s[p.pos..p.pos + 4], 16, 32) or {
		return error('bad \\u escape at ${p.pos}')
	}
	p.pos += 4
	return u32(v)
}

fn (mut p JsonParser) unicode_escape() !string {
	mut cp := p.hex4()!
	// A high surrogate followed by \uDC00-\uDFFF encodes one code point.
	if cp >= 0xD800 && cp < 0xDC00 && p.s[p.pos..].starts_with('\\u') {
		save := p.pos
		p.pos += 2
		lo := p.hex4()!
		if lo >= 0xDC00 && lo < 0xE000 {
			cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00)
		} else {
			p.pos = save
		}
	}
	return utf32_to_str(cp)
}

fn (mut p JsonParser) number() !json2.Any {
	start := p.pos
	mut is_float := false
	for p.pos < p.s.len {
		c := p.s[p.pos]
		if c.is_digit() || c == `-` || c == `+` {
			p.pos++
		} else if c in [`.`, `e`, `E`] {
			is_float = true
			p.pos++
		} else {
			break
		}
	}
	text := p.s[start..p.pos]
	if !is_float {
		if v := strconv.parse_int(text, 10, 64) {
			return v
		}
	}
	return strconv.atof64(text) or { return error('bad number `${text}`') }
}

fn json_encode(n json2.Any) string {
	mut sb := strings.new_builder(64)
	write_json(mut sb, n)
	return sb.str()
}

fn write_json(mut sb strings.Builder, n json2.Any) {
	match n {
		json2.Null {
			sb.write_string('null')
		}
		string {
			write_json_string(mut sb, n)
		}
		bool {
			sb.write_string(if n { 'true' } else { 'false' })
		}
		i64 {
			sb.write_string(n.str())
		}
		f64 {
			// JSON has no NaN or infinity.
			if math.is_nan(n) || math.is_inf(n, 0) {
				sb.write_string('null')
			} else {
				sb.write_string(strconv.f64_to_str_l(n))
			}
		}
		[]json2.Any {
			sb.write_u8(`[`)
			for i, item in n {
				if i > 0 {
					sb.write_u8(`,`)
				}
				write_json(mut sb, item)
			}
			sb.write_u8(`]`)
		}
		map[string]json2.Any {
			sb.write_u8(`{`)
			mut first := true
			for k, v in n {
				if !first {
					sb.write_u8(`,`)
				}
				first = false
				write_json_string(mut sb, k)
				sb.write_u8(`:`)
				write_json(mut sb, v)
			}
			sb.write_u8(`}`)
		}
		else {
			sb.write_string(n.str())
		}
	}
}

fn write_json_string(mut sb strings.Builder, s string) {
	sb.write_u8(`"`)
	for c in s {
		match c {
			`"` {
				sb.write_string('\\"')
			}
			`\\` {
				sb.write_string('\\\\')
			}
			`\n` {
				sb.write_string('\\n')
			}
			`\r` {
				sb.write_string('\\r')
			}
			`\t` {
				sb.write_string('\\t')
			}
			else {
				if c < 0x20 {
					sb.write_string('\\u${c:04x}')
				} else {
					sb.write_u8(c)
				}
			}
		}
	}
	sb.write_u8(`"`)
}
