module mpv

// NodeNone is the empty node (MPV_FORMAT_NONE).
pub struct NodeNone {}

// Node is a V copy of an mpv_node tree: the value of a property in
// Format.node, a command result, or the arguments of command_node.
// Integers must be i64 and floats f64, e.g. `mpv.Node(i64(3))`.
pub type Node = NodeNone | []Node | []u8 | bool | f64 | i64 | map[string]Node | string

// node_to_v deep-copies the C node at n into V memory. It does not free n.
fn node_to_v(n &C.mpv_node) Node {
	match unsafe { Format(n.format) } {
		.string {
			return cstr(C.vmpv_node_string(n))
		}
		.flag {
			return C.vmpv_node_flag(n) != 0
		}
		.int64 {
			return C.vmpv_node_int64(n)
		}
		.double {
			return C.vmpv_node_double(n)
		}
		.node_array {
			l := C.vmpv_node_list(n)
			if isnil(l) {
				return []Node{}
			}
			mut out := []Node{cap: l.num}
			for i in 0 .. l.num {
				out << node_to_v(C.vmpv_node_list_at(l, i))
			}
			return out
		}
		.node_map {
			l := C.vmpv_node_list(n)
			mut out := map[string]Node{}
			if isnil(l) {
				return out
			}
			for i in 0 .. l.num {
				out[cstr(C.vmpv_node_list_key(l, i))] = node_to_v(C.vmpv_node_list_at(l, i))
			}
			return out
		}
		.byte_array {
			ba := C.vmpv_node_ba(n)
			if isnil(ba) || isnil(ba.data) || ba.size == 0 {
				return []u8{}
			}
			return unsafe { (&u8(ba.data)).vbytes(int(ba.size)) }.clone()
		}
		else {
			return NodeNone{}
		}
	}
}

// node_to_c builds v as a C-heap mpv_node tree. Free it with C.vmpv_node_free,
// never with mpv_free_node_contents.
fn node_to_c(v Node) &C.mpv_node {
	n := C.vmpv_node_new()
	fill_node(n, v)
	return n
}

fn fill_node(n &C.mpv_node, v Node) {
	match v {
		NodeNone {
			C.vmpv_node_set_none(n)
		}
		string {
			C.vmpv_node_set_string(n, &char(v.str), usize(v.len))
		}
		bool {
			C.vmpv_node_set_flag(n, if v { 1 } else { 0 })
		}
		i64 {
			C.vmpv_node_set_int64(n, v)
		}
		f64 {
			C.vmpv_node_set_double(n, v)
		}
		[]u8 {
			C.vmpv_node_set_bytes(n, v.data, usize(v.len))
		}
		[]Node {
			l := C.vmpv_node_set_list(n, v.len, 0)
			// Out of memory: leave an empty list rather than write past it.
			if isnil(l) || l.num != v.len {
				return
			}
			for i, item in v {
				fill_node(C.vmpv_node_list_at(l, i), item)
			}
		}
		map[string]Node {
			l := C.vmpv_node_set_list(n, v.len, 1)
			if isnil(l) || l.num != v.len {
				return
			}
			mut i := 0
			for key, item in v {
				C.vmpv_node_list_set_key(l, i, &char(key.str), usize(key.len))
				fill_node(C.vmpv_node_list_at(l, i), item)
				i++
			}
		}
	}
}
