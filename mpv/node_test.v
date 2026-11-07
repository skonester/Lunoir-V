module mpv

fn round_trip(v Node) Node {
	n := node_to_c(v)
	defer {
		C.vmpv_node_free(n)
	}
	return node_to_v(n)
}

fn test_node_round_trip() {
	cases := [
		Node(NodeNone{}),
		Node('hello'),
		Node('héllo'),
		Node(''),
		Node(true),
		Node(false),
		Node(i64(42)),
		Node(i64(-7)),
		Node(3.14),
		Node([u8(1), 2, 3, 0, 255]),
		Node([]u8{}),
		Node([]Node{}),
		Node([Node('a'), Node(i64(1)), Node(true), Node(2.5)]),
		Node(map[string]Node{}),
		Node({
			'k1': Node('v1')
			'k2': Node(i64(7))
		}),
		Node([Node([Node(i64(1)), Node(i64(2))]), Node({
			'nested': Node('yes')
		})]),
	]
	for c in cases {
		got := round_trip(c)
		assert got == c, 'round trip of ${c}'
	}
}

// Node strings are copied by length, so they do not rely on the V string
// being NUL-terminated (substr_unsafe and tos results need not be).
fn test_node_string_slice() {
	s := 'abcdef'
	assert round_trip(Node(s[1..3])) == Node('bc')
}
