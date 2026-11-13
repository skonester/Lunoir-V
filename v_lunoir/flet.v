module main

import net
import x.json2

struct Action {
	name string
	args []json2.Any
}

struct FletUi {
mut:
	conn       &net.TcpConn = unsafe { nil }
	next_id    int          = 1000
	controls   map[int]map[string]json2.Any
	names      map[string]int
	events     map[string]Action
	icons      map[string]json2.Any
	templates  map[string]json2.Any
	pending    map[int][]json2.Any
	registered bool
	debug      bool
}

fn new_flet(t &Translator) FletUi {
	template := object(json_decode($embed_file('shell.json').to_string()) or { panic(err) })
	mut ui := FletUi{
		icons:     object(json_decode($embed_file('icons.json').to_string()) or { panic(err) })
		templates: object(json_decode($embed_file('ui_templates.json').to_string()) or {
			panic(err)
		})
	}
	for name, id in object(get(template, 'ids')) {
		ui.names[name] = id.int()
	}
	for event, descriptor in object(get(template, 'events')) {
		a := object(descriptor)
		ui.events[event] = Action{text_value(get(a, 'name')), list_value(get(a, 'args'))}
	}
	ui.index(localize(get(template, 'page'), t))
	return ui
}

fn localize(value json2.Any, t &Translator) json2.Any {
	match value {
		string {
			if value == '@app_about' { return app_about_text() }
			if value.contains('\n') {
				return value.split('\n').map(text_value(localize(json2.Any(it), t))).join('\n')
			}
			if !value.starts_with('@tr:') { return value }
			parts := value[4..].split('|')
			mut values := map[string]string{}
			for part in parts[1..] {
				key, item := part.split_once('=') or { continue }
				values[key] = item
			}
			return t.format(parts[0], values)
		}
		[]json2.Any {
			return value.map(localize(it, t))
		}
		map[string]json2.Any {
			mut result := map[string]json2.Any{}
			for key, item in value {
				result[key] = if key in ['_c', '_i', '_internals'] {
					item
				} else {
					localize(item, t)
				}
			}
			return result
		}
		else {
			return value
		}
	}
}

fn (mut ui FletUi) index(value json2.Any) {
	match value {
		map[string]json2.Any {
			if '_i' in value && '_c' in value { ui.controls[get(value, '_i').int()] = value.clone() }
			for _, child in value {
				ui.index(child)
			}
		}
		[]json2.Any {
			for child in value {
				ui.index(child)
			}
		}
		else {}
	}
}

fn (ui &FletUi) expand(value json2.Any) json2.Any {
	match value {
		map[string]json2.Any {
			if '_i' in value && '_c' in value { return ui.tree(get(value, '_i').int()) }
			mut result := map[string]json2.Any{}
			for key, child in value {
				result[key] = ui.expand(child)
			}
			return result
		}
		[]json2.Any {
			return value.map(ui.expand(it))
		}
		else {
			return value
		}
	}
}

fn (ui &FletUi) tree(id int) json2.Any {
	mut result := map[string]json2.Any{}
	props := (ui.controls[id] or { return json2.Null{} }).clone()
	for key, value in props {
		result[key] = ui.expand(value)
	}
	return result
}

fn (mut ui FletUi) create(kind string, props map[string]json2.Any) json2.Any {
	id := ui.next_id
	ui.next_id++
	mut control := props.clone()
	if '_internals' !in control {
		for _, example in ui.controls {
			if text_value(get(example, '_c')) == kind {
				internals := object(get(example, '_internals'))
				if 'skip_properties' in internals {
					control['_internals'] = json2.Any({
						'skip_properties': get(internals, 'skip_properties')
					})
					break
				}
			}
		}
	}
	control['_i'] = id
	control['_c'] = kind
	ui.controls[id] = control.clone()
	return {
		'_i': json2.Any(id)
		'_c': kind
	}
}

fn collect_ids(value json2.Any, mut ids map[int]int, initial int) int {
	mut next := initial
	match value {
		map[string]json2.Any {
			if '_i' in value && '_c' in value {
				id := get(value, '_i').int()
				if id !in ids {
					ids[id] = next
					next++
				}
			}
			for _, child in value {
				next = collect_ids(child, mut ids, next)
			}
		}
		[]json2.Any {
			for child in value {
				next = collect_ids(child, mut ids, next)
			}
		}
		else {}
	}

	return next
}

fn remap_ids(value json2.Any, ids map[int]int, directory string) json2.Any {
	match value {
		map[string]json2.Any {
			mut result := map[string]json2.Any{}
			for key, child in value {
				result[key] = if key == '_i' {
					json2.Any(ids[child.int()] or { child.int() })
				} else {
					remap_ids(child, ids, directory)
				}
			}
			return result
		}
		[]json2.Any {
			return value.map(remap_ids(it, ids, directory))
		}
		string {
			if value.starts_with('@control:') { return ids[value[9..].int()] or { 0 } }
			return value.replace('@shot_directory', directory)
		}
		else {
			return value
		}
	}
}

fn (mut ui FletUi) instantiate(name string, t &Translator, settings map[string]json2.Any) []json2.Any {
	template := object(ui.templates[name] or { return []json2.Any{} })
	mut ids := map[int]int{}
	ui.next_id = collect_ids(get(template, 'controls'), mut ids, ui.next_id)
	controls := list_value(remap_ids(localize(get(template, 'controls'), t), ids,
		screenshot_dir(settings)))
	for control in controls {
		ui.index(control)
	}
	for event, record in object(get(template, 'events')) {
		old, kind := event.split_once(':') or { continue }
		description := object(record)
		ui.events['${ids[old.int()]}:${kind}'] = Action{text_value(get(description, 'name')), list_value(remap_ids(get(description,
			'args'), ids, ''))}
	}
	for raw, record in object(get(template, 'bindings')) {
		binding := object(record)
		key := text_value(get(binding, 'key'))
		if key == '' { continue
		 }
		id := ids[raw.int()]
		mut props := (ui.controls[id] or { continue }).clone()
		mut value := get(settings, key)
		match text_value(get(binding, 'kind')) {
			'bool' {
				value = truth(value)
			}
			'select' {
				value = text_value(value)
			}
			'number' {
				value = clamp(number(value), number(get(props, 'min')), number(get(props, 'max')))
				reading_id := ids[get(binding, 'reading').int()] or { 0 }
				if reading_id > 0 {
					mut reading := (ui.controls[reading_id] or {
						map[string]json2.Any{}
					}).clone()
					reading['value'] = if get(binding, 'digits').int() == 0 {
						'${number(value):.0f}'
					} else {
						'${number(value):.1f}'
					}
					ui.controls[reading_id] = reading.clone()
				}
			}
			else {}
		}

		props['value'] = value
		ui.controls[id] = props.clone()
	}
	for control_name, old in object(get(template, 'ids')) {
		ui.names[control_name] = ids[old.int()]
	}
	return controls
}

fn (ui &FletUi) reachable(value json2.Any, mut found map[int]bool) {
	match value {
		map[string]json2.Any {
			if '_i' in value && '_c' in value {
				id := get(value, '_i').int()
				if found[id] { return }
				found[id] = true
				for _, child in (ui.controls[id] or {
					map[string]json2.Any{}
				}) {
					ui.reachable(child, mut found)
				}
			} else {
				for _, child in value {
					ui.reachable(child, mut found)
				}
			}
		}
		[]json2.Any {
			for child in value {
				ui.reachable(child, mut found)
			}
		}
		else {}
	}
}

fn (mut ui FletUi) prune() {
	mut found := map[int]bool{}
	ui.reachable(json2.Any({
		'_i': json2.Any(1)
		'_c': 'Page'
	}), mut found)
	for id in ui.controls.keys() {
		if !found[id] {
			ui.controls.delete(id)
			ui.pending.delete(id)
		}
	}
	for event in ui.events.keys() {
		if !found[event.all_before(':').int()] { ui.events.delete(event) }
	}
}

fn (mut ui FletUi) bind(control json2.Any, event string, action string, args []json2.Any) {
	id := get(object(control), '_i').int()
	ui.events['${id}:${event}'] = Action{action, args}
	mut props := (ui.controls[id] or { return }).clone()
	props['on_' + event] = true
	ui.controls[id] = props.clone()
}

fn (ui &FletUi) id(name string) int {
	return ui.names[name] or { 0 }
}

fn (ui &FletUi) prop(name string, key string) json2.Any {
	return get(ui.controls[ui.id(name)] or {
		map[string]json2.Any{}
	}, key)
}

fn (mut ui FletUi) set(name string, key string, value json2.Any) {
	ui.set_id(ui.id(name), key, value)
}

fn (mut ui FletUi) set_id(id int, key string, value json2.Any) {
	mut props := (ui.controls[id] or { return }).clone()
	if get(props, key) == value { return }
	op := if key in props { 0 } else { 1 }
	props[key] = value
	ui.controls[id] = props.clone()
	mut operations := (ui.pending[id] or { []json2.Any{} }).clone()
	operations << json2.Any([json2.Any(op), 0, key, value])
	ui.pending[id] = operations
}

fn (mut ui FletUi) receive_props(id int, values map[string]json2.Any) {
	mut props := (ui.controls[id] or { return }).clone()
	for key, value in values {
		props[key] = value
	}
	ui.controls[id] = props.clone()
}

fn (mut ui FletUi) send(action int, body json2.Any) ! {
	if isnil(ui.conn) { return error('Flet desktop is disconnected') }
	payload := msgpack_pack([json2.Any(action), body])
	length := payload.len + 1
	mut frame := [u8(length), u8(length >> 8), u8(length >> 16), u8(length >> 24), u8(0)]
	frame << payload
	mut offset := 0
	for offset < frame.len {
		count := ui.conn.write(frame[offset..])!
		if count == 0 { return error('Flet connection closed during write') }
		offset += count
	}
}

fn (mut ui FletUi) flush() ! {
	if !ui.registered { return }
	for id, operations in ui.pending {
		mut patch := [json2.Any([json2.Any(0)])]
		for operation in operations {
			patch << ui.expand(operation)
		}
		ui.send(2, {
			'id':    json2.Any(id)
			'patch': patch
		})!
	}
	ui.pending.clear()
}

fn (mut ui FletUi) invoke(id int, name string, args map[string]json2.Any, call_id string) ! {
	ui.send(5, {
		'control_id': json2.Any(id)
		'call_id':    call_id
		'name':       name
		'args':       args
	})!
}

fn read_exact(conn &net.TcpConn, count int) ![]u8 {
	mut result := []u8{len: count}
	mut offset := 0
	for offset < count {
		read := conn.read(mut result[offset..])!
		if read == 0 { return error('Flet desktop disconnected') }
		offset += read
	}
	return result
}

fn read_flet(conn &net.TcpConn, incoming chan json2.Any) {
	for {
		header := read_exact(conn, 4) or { break }
		size := int(u32(header[0]) | (u32(header[1]) << 8) | (u32(header[2]) << 16) | (u32(header[3]) << 24))
		if size <= 0 || size > 32 * 1024 * 1024 { break
		 }
		payload := read_exact(conn, size) or { break }
		if payload[0] != 0 { continue
		 }
		message := msgpack_unpack(payload[1..]) or { break }
		incoming <- message
	}
	incoming <- json2.Any([json2.Any(0), 'disconnected'])
}
