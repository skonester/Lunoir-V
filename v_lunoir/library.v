module main

import os
import x.json2

fn (a &App) collection_key() string {
	return if a.source_type == 'iptv' {
		a.open_target
	} else if a.queue.len > 0 {
		queue_key(a.queue.map(it.path))
	} else {
		''
	}
}

fn (mut a App) favourite_target(target string, notify bool) {
	if target == '' { return }
	if a.profile.is_favourite(target) {
		if notify { a.notify(a.t.tr('toast.alreadyFav')) }
		return
	}
	mut kind := if is_channel_list(target) { 'list' } else { target_kind(target) }
	mut name := media_name(target)
	mut extra := map[string]json2.Any{}
	if target == a.open_target {
		kind = a.open_kind
		if kind == 'list' && a.source_type == 'iptv' {
			extra['channels'] = a.queue.map(json2.Any({
				'name':  json2.Any(it.title)
				'url':   it.path
				'group': it.group
			}))
		} else if kind == 'list' {
			kind = 'url'
		}
		if a.source_ua != '' { extra['userAgent'] = a.source_ua }
		name = if kind == 'list' { media_name(target) } else { a.window_title() }
	} else {
		for entry in a.profile.recents {
			if text_value(get(object(entry), 'target')) == target {
				name = text_value(get(object(entry), 'name'))
				break
			}
		}
	}
	a.profile.toggle_favourite(target, name, kind, extra) or {
		a.notify(err.msg())
		return
	}
	if notify { a.notify(a.t.tr('toast.favourited')) }
	a.fill_panel()
}

fn (mut a App) save_collection() {
	key := a.collection_key()
	if key == '' { return }
	mut saved := false
	if a.profile.is_favourite(key) {
		a.profile.toggle_favourite(key, '', '', map[string]json2.Any{}) or {}
	} else if a.source_type == 'iptv' {
		a.favourite_target(key, false)
		saved = true
	} else {
		first := a.queue[0]
		folder := if is_url(first.path) { '' } else { os.file_name(os.dir(first.path)) }
		name := if a.queue.len > 1 && folder != '' {
			folder
		} else if first.title != '' {
			first.title
		} else {
			media_name(first.path)
		}
		saved = a.profile.toggle_favourite(key, name, 'playlist', {
			'items': json2.Any(a.queue.map(json2.Any({
				'path': json2.Any(it.path)
				'name': if it.title == '' { media_name(it.path) } else { it.title }
			})))
		}) or { false }
	}
	a.notify(a.t.tr(if saved { 'toast.favourited' } else { 'toast.unfavourited' }))
	a.fill_panel()
}

fn (mut a App) open_saved(entry map[string]json2.Any) {
	items := list_value(get(entry, 'items'))
	if text_value(get(entry, 'kind')) != 'playlist' || items.len == 0 {
		a.open_target_path(text_value(get(entry, 'target')), text_value(get(entry, 'userAgent')))
		return
	}
	a.persist()
	a.source_type = 'queue'
	a.source_ua = ''
	a.open_target = text_value(get(entry, 'target'))
	a.open_kind = 'playlist'
	a.playlist_key = a.open_target
	a.set_queue(items.map(Entry{ path: text_value(get(object(it), 'path')), title: text_value(get(object(it),
		'name')) }))
	a.play_index(a.resume_index())
}

fn (mut a App) show_dialog(title string, content json2.Any, buttons []json2.Any) {
	dialog := a.ui.create('AlertDialog', {
		'modal':   json2.Any(true)
		'open':    true
		'title':   a.text(title, 18, '#EEEEF0')
		'content': content
		'actions': buttons
	})
	a.ui.bind(dialog, 'dismiss', 'dialog_dismissed', [get(object(dialog), '_i')])
	a.ui.set_id(5, 'controls', [dialog])
	a.dialog_open = true
	a.layout()
}

fn (mut a App) dismiss_dialog() {
	controls := list_value(get(a.ui.controls[5] or {
		map[string]json2.Any{}
	}, 'controls'))
	if controls.len > 0 { a.ui.set_id(get(object(controls[0]), '_i').int(), 'open', false) }
	a.dialog_open = false
	a.layout()
}

fn (mut a App) dialog_dismissed(id int) {
	controls := list_value(get(a.ui.controls[5] or {
		map[string]json2.Any{}
	}, 'controls'))
	if controls.len > 0 && get(object(controls[0]), '_i').int() == id {
		a.ui.set_id(5, 'controls', []json2.Any{})
		a.dialog_open = false
		a.layout()
	}
}

fn (mut a App) confirm_clear() {
	a.show_dialog(a.t.tr('lib.clearConfirm'), json2.Null{}, [
		a.button(a.t.tr('common.close'), 'dialog_close', []json2.Any{}),
		a.button(a.t.tr('lib.clearRecents'), 'dialog_confirm_clear', []json2.Any{}),
	])
}

fn (mut a App) rename_dialog(entry map[string]json2.Any) {
	field := a.ui.create('TextField', {
		'value':     get(entry, 'name')
		'width':     420
		'autofocus': true
	})
	a.ui.names['rename_field'] = get(object(field), '_i').int()
	target := get(entry, 'target')
	a.ui.bind(field, 'submit', 'dialog_rename_save', [target])
	a.show_dialog(a.t.tr('lib.rename'), field, [
		a.button(a.t.tr('common.close'), 'dialog_close', []json2.Any{}),
		a.button(a.t.tr('lib.rename'), 'dialog_rename_save', [target]),
	])
}

fn (mut a App) url_dialog() {
	field := a.ui.create('TextField', {
		'width':     json2.Any(420)
		'hint_text': a.t.tr('empty.urlPlaceholder')
		'autofocus': true
		'dense':     true
	})
	agent := a.ui.create('TextField', {
		'width': json2.Any(420)
		'label': a.t.tr('url.userAgent')
		'dense': true
	})
	a.ui.names['url_field'] = get(object(field), '_i').int()
	a.ui.names['ua_field'] = get(object(agent), '_i').int()
	a.ui.bind(field, 'submit', 'submit_url', []json2.Any{})
	a.show_dialog(a.t.tr('menu.openUrl'), a.column([field, agent]), [
		a.button(a.t.tr('common.close'), 'dialog_close', []json2.Any{}),
		a.button(a.t.tr('empty.urlPlay'), 'submit_url', []json2.Any{}),
	])
}
