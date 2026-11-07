module main

import mpv

fn test_decode() {
	n :=
		json_decode('{"command": ["seek", 12.5, "absolute"], "request_id": 7, "async": false, "x": null}')!
	assert n == mpv.Node({
		'command':    mpv.Node([mpv.Node('seek'), mpv.Node(12.5), mpv.Node('absolute')])
		'request_id': mpv.Node(i64(7))
		'async':      mpv.Node(false)
		'x':          mpv.Node(mpv.NodeNone{})
	})
	assert json_decode(' [ ] ')! == mpv.Node([]mpv.Node{})
	assert json_decode('{}')! == mpv.Node(map[string]mpv.Node{})
	assert json_decode('-3')! == mpv.Node(i64(-3))
	assert json_decode('1e3')! == mpv.Node(1000.0)
}

fn test_decode_strings() {
	assert json_decode('"a\\"b\\\\c\\n"')! == mpv.Node('a"b\\c\n')
	assert json_decode('"\\u00e9\\u4e2d"')! == mpv.Node('é中')
	assert json_decode('"\\ud83d\\ude00"')! == mpv.Node('😀')
	assert json_decode('"C:\\\\Videos\\\\film.mkv"')! == mpv.Node('C:\\Videos\\film.mkv')
	assert json_decode('"raw é"')! == mpv.Node('raw é')
}

fn test_decode_errors() {
	for bad in ['', '{', '[1,', '{"a" 1}', '"open', 'nul', '{"a":1} x', '[1 2]'] {
		if _ := json_decode(bad) {
			assert false, 'accepted ${bad}'
		}
	}
}

fn test_encode() {
	assert json_encode(mpv.Node({
		'event': mpv.Node('property-change')
	})) == '{"event":"property-change"}'
	assert json_encode(mpv.Node([mpv.Node(i64(1)), mpv.Node(2.5), mpv.Node(true),
		mpv.Node(mpv.NodeNone{})])) == '[1,2.5,true,null]'
	assert json_encode(mpv.Node('q"\\\n\x01é')) == '"q\\"\\\\\\n\\u0001é"'
}

fn test_round_trip() {
	src := mpv.Node({
		'list': mpv.Node([mpv.Node('a'), mpv.Node(i64(-2)), mpv.Node(0.125)])
		'map':  mpv.Node({
			'k': mpv.Node(false)
		})
	})
	assert json_decode(json_encode(src))! == src
}
