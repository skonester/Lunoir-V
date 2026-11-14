module main

import math
import time
import x.json2

const picture_scalers = ['bilinear', 'lanczos', 'spline36', 'ewa_lanczossharp']

fn picture_defaults() map[string]json2.Any {
	return {
		'pictureBrightness':    json2.Any(0)
		'pictureContrast':      0
		'pictureSaturation':    0
		'pictureGamma':         0
		'pictureDeband':        false
		'pictureInterpolation': false
		'pictureScaler':        'lanczos'
	}
}

fn preset_defaults() map[string]json2.Any {
	mut values := picture_defaults()
	values['hwdec'] = 'auto'
	values['deinterlace'] = 'no'
	values['keepPitch'] = true
	values['streamQuality'] = 'best'
	return values
}

fn normalize_preset(value json2.Any) !map[string]json2.Any {
	if value !is map[string]json2.Any { return error('Invalid preset') }
	mut result := preset_defaults()
	for key, item in object(value) {
		if key !in result { return error('Unknown preset setting: ${key}') }
		if key in ['pictureBrightness', 'pictureContrast', 'pictureSaturation', 'pictureGamma'] {
			if item !is int && item !is i64 && item !is f64 { return error('Invalid picture value') }
			n := item.f64()
			if math.is_nan(n) || math.is_inf(n, 0) || n < -100 || n > 100 {
				return error('Invalid picture range')
			}
			result[key] = int(math.round_to_even(n))
		} else if key in ['pictureDeband', 'pictureInterpolation', 'keepPitch'] {
			if item !is bool { return error('Invalid preset switch') }
			result[key] = item
		} else {
			if item !is string { return error('Invalid preset choice') }
			choices := match key {
				'pictureScaler' { picture_scalers }
				'hwdec' { ['auto', 'auto-copy', 'no'] }
				'deinterlace' { ['auto', 'yes', 'no'] }
				else { ['best', '2160', '1080', '720', '480'] }
			}

			if text_value(item) !in choices { return error('Invalid preset choice: ${item}') }
			result[key] = item
		}
	}
	return result
}

fn preset_snapshot(settings map[string]json2.Any) map[string]json2.Any {
	mut result := preset_defaults()
	for key in result.keys() {
		if key in settings {
			if value := normalize_preset({
				key: get(settings, key)
			})
			{
				result[key] = get(value, key)
			}
		}
	}
	return result
}

fn picture_snapshot(settings map[string]json2.Any) map[string]json2.Any {
	values := preset_snapshot(settings)
	mut result := picture_defaults()
	for key in result.keys() {
		result[key] = get(values, key)
	}
	return result
}

fn picture_properties(key string, value json2.Any) []Property {
	if key == 'pictureInterpolation' {
		return [
			Property{'video-sync', if truth(value) { 'display-resample' } else { 'audio' }},
			Property{'interpolation', value},
		]
	}
	names := {
		'pictureBrightness': 'brightness'
		'pictureContrast':   'contrast'
		'pictureSaturation': 'saturation'
		'pictureGamma':      'gamma'
		'pictureDeband':     'deband'
		'pictureScaler':     'scale'
	}
	if name := names[key] { return [Property{name, value}] }
	return []Property{}
}

struct PictureChange {
	token       u64
	values      map[string]json2.Any
	previous    map[string]json2.Any
	preset_name string
mut:
	remaining int
	failures  []string
}

fn (a &App) playback_settings() map[string]json2.Any {
	mut settings := a.profile.settings.clone()
	for key, value in a.picture_change.values {
		settings[key] = value
	}
	return settings
}

fn (mut a App) apply_picture_changes(changes map[string]json2.Any, preset_name string) {
	if a.picture_change.remaining > 0 {
		a.notify(a.t.tr('preset.wait'))
		return
	}
	mut candidate := preset_snapshot(a.profile.settings)
	for key, value in changes {
		candidate[key] = value
	}
	normalized := normalize_preset(candidate) or {
		a.notify(a.t.tr('preset.invalid'))
		return
	}
	mut values := map[string]json2.Any{}
	mut properties := []Property{}
	for key in changes.keys() {
		values[key] = get(normalized, key)
		properties << properties_for(key, normalized)
	}
	a.picture_serial++
	a.picture_change = PictureChange{
		token:       a.picture_serial
		values:      values
		previous:    preset_snapshot(a.profile.settings)
		preset_name: preset_name
	}
	for property in properties {
		id := a.backend.set_property_tracked(property.name, property.value) or {
			a.picture_change.failures << err.msg()
			continue
		}
		a.picture_change.remaining++
		a.playback_actions[id] = PlaybackAction{
			kind:  'picture-write'
			token: a.picture_serial
		}
	}
	if a.picture_change.remaining == 0 {
		a.finish_picture_change()
	} else if a.panel_mode == 'settings' {
		a.fill_panel()
	}
}

fn (mut a App) picture_reply(token u64, failure string) {
	if token != a.picture_change.token || a.picture_change.remaining == 0 { return }
	if failure != '' { a.picture_change.failures << failure }
	a.picture_change.remaining--
	if a.picture_change.remaining == 0 { a.finish_picture_change() }
}

fn (mut a App) finish_picture_change() {
	change := a.picture_change
	a.picture_change = PictureChange{}
	mut failure := change.failures.join('; ')
	if failure == '' {
		mut settings := a.profile.settings.clone()
		for key, value in change.values {
			settings[key] = value
		}
		settings['picturePreset'] = change.preset_name
		a.profile.stage_settings(settings, time.now().unix_milli())
	}
	if failure != '' {
		// A multi-option preset can partially succeed. Restore the previous
		// values on the core, and keep the accepted profile unchanged.
		for key in change.values.keys() {
			for property in properties_for(key, change.previous) {
				a.try_set(property.name, property.value)
			}
		}
		log_native('Picture settings rejected: ${failure}')
		a.notify(a.t.tr('preset.failed') + ': ' + failure)
	} else if change.preset_name != '' {
		a.notify(a.t.format('preset.applied', {
			'name': change.preset_name
		}))
	}
	if a.panel_mode == 'settings' { a.fill_panel() }
}

fn valid_preset_name(name string) bool {
	return name == name.trim_space() && name.runes().len > 0 && name.runes().len <= 64
		&& !name.bytes().any(it < 32 || it == 127)
}

fn (mut p Profile) save_preset(name string, values json2.Any) ! {
	if !valid_preset_name(name) { return error('Invalid preset name') }
	normalized := normalize_preset(values)!
	previous := p.presets.clone()
	p.presets[name] = normalized
	p.write('presets.json', p.presets) or {
		p.presets = previous.clone()
		return err
	}
}

fn (mut p Profile) delete_preset(name string) ! {
	previous := p.presets.clone()
	p.presets.delete(name)
	p.write('presets.json', p.presets) or {
		p.presets = previous.clone()
		return err
	}
}

fn (mut a App) preset_dialog() {
	if a.picture_change.remaining > 0 {
		a.notify(a.t.tr('preset.wait'))
		return
	}
	field := a.ui.create('TextField', {
		'label':      json2.Any(a.t.tr('preset.name'))
		'width':      360
		'autofocus':  true
		'max_length': 64
	})
	a.ui.names['preset_name'] = get(object(field), '_i').int()
	a.ui.bind(field, 'submit', 'preset_save', []json2.Any{})
	a.show_dialog(a.t.tr('preset.save'), field, [
		a.button(a.t.tr('common.close'), 'dialog_close', []json2.Any{}),
		a.button(a.t.tr('preset.save'), 'preset_save', []json2.Any{}),
	])
}

fn (mut a App) save_named_preset() {
	name := text_value(a.ui.prop('preset_name', 'value')).trim_space()
	if a.picture_change.remaining > 0 {
		a.notify(a.t.tr('preset.wait'))
		return
	}
	if !valid_preset_name(name) {
		a.notify(a.t.tr('preset.invalidName'))
		return
	}
	a.profile.save_preset(name, preset_snapshot(a.profile.settings)) or {
		a.notify(err.msg())
		return
	}
	a.dismiss_dialog()
	a.notify(a.t.format('preset.saved', {
		'name': name
	}))
	a.fill_panel()
}

fn (mut a App) apply_named_preset(name string) {
	values := a.profile.presets[name] or {
		a.notify(a.t.tr('preset.invalid'))
		return
	}
	normalized := normalize_preset(values) or {
		a.notify(a.t.tr('preset.invalid'))
		return
	}
	a.apply_picture_changes(normalized, name)
}

fn (mut a App) delete_named_preset(name string) {
	if a.picture_change.remaining > 0 {
		a.notify(a.t.tr('preset.wait'))
		return
	}
	a.profile.delete_preset(name) or {
		a.notify(err.msg())
		return
	}
	if text_value(get(a.profile.settings, 'picturePreset')) == name {
		a.queue_setting('picturePreset', '')
	}
	a.fill_panel()
}

fn (mut a App) picture_panel() []json2.Any {
	mut values := preset_snapshot(a.profile.settings)
	for key, value in a.picture_change.values {
		values[key] = value
	}
	busy := a.picture_change.remaining > 0
	mut body := [a.section(a.t.tr('picture.color'))]
	for key, label in {
		'pictureBrightness': 'brightness'
		'pictureContrast':   'contrast'
		'pictureSaturation': 'saturation'
		'pictureGamma':      'gamma'
	} {
		value := number(get(values, key))
		caption := a.text('${value:.0f}', 12, '#92929C')
		slider := a.ui.create('Slider', {
			'value':     json2.Any(value)
			'min':       -100
			'max':       100
			'divisions': 200
			'expand':    true
			'disabled':  busy
		})
		a.ui.bind(slider, 'change', 'setting_moving', [json2.Any(0), get(object(caption), '_i')])
		a.ui.bind(slider, 'change_end', 'setting_number', [json2.Any(key), 0])
		body << a.text(a.t.tr('picture.' + label), 13, '#EEEEF0')
		body << a.row([slider, caption])
	}
	body << a.section(a.t.tr('set.sec.enhance'))
	for key, label in {
		'pictureDeband':        'deband'
		'pictureInterpolation': 'interpolation'
	} {
		control := a.ui.create('Switch', {
			'label':    json2.Any(a.t.tr('picture.' + label))
			'value':    truth(get(values, key))
			'disabled': busy
		})
		a.ui.bind(control, 'change', 'setting_bool', [json2.Any(key)])
		body << control
	}
	body << a.text(a.t.tr('picture.interpolationHint'), 11, '#92929C')
	mut choices := []json2.Any{}
	for scaler in picture_scalers {
		choices << a.ui.create('DropdownOption', {
			'key':  json2.Any(scaler)
			'text': scaler
		})
	}
	scale := a.ui.create('Dropdown', {
		'label':     json2.Any(a.t.tr('picture.scaler'))
		'value':     get(values, 'pictureScaler')
		'options':   choices
		'dense':     true
		'text_size': 12
		'width':     260
		'disabled':  busy
	})
	a.ui.bind(scale, 'select', 'setting_select', [json2.Any('pictureScaler')])
	body << scale
	reset := a.button(a.t.tr('picture.reset'), 'picture_reset', []json2.Any{})
	a.ui.set_id(get(object(reset), '_i').int(), 'disabled', busy)
	body << reset
	body << a.section(a.t.tr('preset.title'))
	body << a.text(a.t.tr('preset.hint'), 11, '#92929C')
	name := text_value(get(a.profile.settings, 'picturePreset'))
	if name != '' && name in a.profile.presets { body << a.text(name, 13, '#EEEEF0') }
	save := a.button(a.t.tr('preset.save'), 'preset_save_dialog', []json2.Any{})
	a.ui.set_id(get(object(save), '_i').int(), 'disabled', busy)
	body << save
	mut names := a.profile.presets.keys()
	names.sort()
	if names.len == 0 { body << a.text(a.t.tr('preset.empty'), 12, '#92929C') }
	for saved in names {
		apply := a.button(a.t.tr('preset.apply'), 'preset_apply', [json2.Any(saved)])
		remove := a.button(a.t.tr('preset.delete'), 'preset_delete', [json2.Any(saved)])
		a.ui.set_id(get(object(apply), '_i').int(), 'disabled', busy)
		a.ui.set_id(get(object(remove), '_i').int(), 'disabled', busy)
		body << a.text(saved, 13, '#EEEEF0')
		body << a.wrap_row([apply, remove])
	}
	return body
}
