module main

import math
import x.json2

fn pack_number(mut out []u8, value u64, width int) {
	for i := width - 1; i >= 0; i-- {
		out << u8(value >> (i * 8))
	}
}

fn pack_length(mut out []u8, size int, short u8, medium u8, long u8, threshold int) {
	if size < threshold {
		out << short | u8(size)
	} else if medium != 0 && size <= 255 {
		out << medium
		pack_number(mut out, u64(size), 1)
	} else if size <= 65535 {
		out << long
		pack_number(mut out, u64(size), 2)
	} else {
		out << long + 1
		pack_number(mut out, u64(size), 4)
	}
}

fn msgpack_pack(value json2.Any) []u8 {
	mut out := []u8{}
	pack_value(mut out, value)
	return out
}

fn pack_value(mut out []u8, value json2.Any) {
	match value {
		json2.Null {
			out << u8(0xc0)
		}
		bool {
			out << if value { u8(0xc3) } else { u8(0xc2) }
		}
		string {
			pack_length(mut out, value.len, 0xa0, 0xd9, 0xda, 32)
			out << value.bytes()
		}
		[]json2.Any {
			pack_length(mut out, value.len, 0x90, 0, 0xdc, 16)
			for item in value {
				pack_value(mut out, item)
			}
		}
		map[string]json2.Any {
			pack_length(mut out, value.len, 0x80, 0, 0xde, 16)
			for key, item in value {
				pack_value(mut out, key)
				pack_value(mut out, item)
			}
		}
		f64 {
			out << u8(0xcb)
			pack_number(mut out, math.f64_bits(value), 8)
		}
		f32 {
			out << u8(0xca)
			pack_number(mut out, u64(math.f32_bits(value)), 4)
		}
		else {
			n := value.i64()
			if n >= 0 && n < 128 {
				out << u8(n)
			} else if n < 0 && n >= -32 {
				out << u8(n)
			} else {
				out << u8(0xd3)
				pack_number(mut out, u64(n), 8)
			}
		}
	}
}

struct PackReader {
	data []u8
mut:
	pos int
}

fn (mut r PackReader) integer(width int) !u64 {
	if width < 0 || r.pos + width > r.data.len { return error('Truncated MessagePack integer') }
	mut value := u64(0)
	for _ in 0 .. width {
		value = (value << 8) | r.data[r.pos]
		r.pos++
	}
	return value
}

fn (mut r PackReader) bytes(length int) !string {
	if length < 0 || r.pos + length > r.data.len { return error('Truncated MessagePack string') }
	result := r.data[r.pos..r.pos + length].bytestr()
	r.pos += length
	return result
}

fn (mut r PackReader) list(length int, depth int) !json2.Any {
	if length < 0 || length > 1000000 { return error('MessagePack collection is too large') }
	mut result := []json2.Any{cap: length}
	for _ in 0 .. length {
		result << r.value(depth + 1)!
	}
	return result
}

fn (mut r PackReader) dictionary(length int, depth int) !json2.Any {
	if length < 0 || length > 1000000 { return error('MessagePack collection is too large') }
	mut result := map[string]json2.Any{}
	for _ in 0 .. length {
		key := r.value(depth + 1)!
		if key !is string { return error('Flet property names must be strings') }
		result[key as string] = r.value(depth + 1)!
	}
	return result
}

fn (mut r PackReader) value(depth int) !json2.Any {
	if depth > 128 || r.pos >= r.data.len {
		return error('Invalid MessagePack nesting or empty frame')
	}
	tag := r.data[r.pos]
	r.pos++
	if tag <= 0x7f { return int(tag) }
	if tag >= 0xe0 { return int(i8(tag)) }
	if tag & 0xe0 == 0xa0 { return r.bytes(int(tag & 0x1f))! }
	if tag & 0xf0 == 0x90 { return r.list(int(tag & 0x0f), depth)! }
	if tag & 0xf0 == 0x80 { return r.dictionary(int(tag & 0x0f), depth)! }
	match tag {
		0xc0 {
			return json2.Null{}
		}
		0xc2 {
			return false
		}
		0xc3 {
			return true
		}
		0xca {
			return f64(math.f32_from_bits(u32(r.integer(4)!)))
		}
		0xcb {
			return math.f64_from_bits(r.integer(8)!)
		}
		0xcc, 0xcd, 0xce, 0xcf {
			return i64(r.integer(1 << int(tag - 0xcc))!)
		}
		0xd0 {
			return int(i8(r.integer(1)!))
		}
		0xd1 {
			return int(i16(r.integer(2)!))
		}
		0xd2 {
			return i64(i32(r.integer(4)!))
		}
		0xd3 {
			return i64(r.integer(8)!)
		}
		0xd9, 0xda, 0xdb {
			size := int(r.integer(1 << int(tag - 0xd9))!)
			return r.bytes(size)!
		}
		0xc4, 0xc5, 0xc6 {
			size := int(r.integer(1 << int(tag - 0xc4))!)
			return r.bytes(size)!
		}
		0xdc, 0xdd {
			size := int(r.integer(if tag == 0xdc { 2 } else { 4 })!)
			return r.list(size, depth)!
		}
		0xde, 0xdf {
			size := int(r.integer(if tag == 0xde { 2 } else { 4 })!)
			return r.dictionary(size, depth)!
		}
		0xd4, 0xd5, 0xd6, 0xd7, 0xd8, 0xc7, 0xc8, 0xc9 {
			size := if tag >= 0xd4 {
				1 << int(tag - 0xd4)
			} else {
				int(r.integer(1 << int(tag - 0xc7))!)
			}
			kind := int(r.integer(1)!)
			data := r.bytes(size)!
			if kind == 4 { return data }
			// Dates and durations can occur in client state; retain their payload.
			return data
		}
		else {
			return error('Unsupported MessagePack tag ${tag}')
		}
	}
}

fn msgpack_unpack(data []u8) !json2.Any {
	mut reader := PackReader{
		data: data
	}
	value := reader.value(0)!
	if reader.pos != data.len { return error('Trailing data in MessagePack frame') }
	return value
}
