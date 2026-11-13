module py_flet_lunoir

import os
import regex
import math
import arrays

// TODO(py2v): no V equivalent for import flet
// Provide one in python_to_v_import (types.v) or port the module.

const text = '#EEEEF0'
const dim = '#92929C'
const faint = '#6E6E79'
const line = '#393940'
const active = '#3A3A42'
const speeds = [0.5, 0.75, 1, 1.25, 1.5, 2]
const lang_keys = {
	'eng': 'english'
	'en':  'english'
	'chi': 'chinese'
	'zho': 'chinese'
	'zh':  'chinese'
	'jpn': 'japanese'
	'ja':  'japanese'
	'kor': 'korean'
	'ko':  'korean'
	'fre': 'french'
	'fra': 'french'
	'fr':  'french'
	'ger': 'german'
	'deu': 'german'
	'de':  'german'
	'spa': 'spanish'
	'es':  'spanish'
	'ita': 'italian'
	'it':  'italian'
	'rus': 'russian'
	'ru':  'russian'
	'por': 'portuguese'
	'pt':  'portuguese'
}
const audio_formats = {
	'truehd': 'Dolby TrueHD'
	'eac3':   'Dolby Digital Plus'
	'ac3':    'Dolby Digital'
	'dts':    'DTS'
	'aac':    'AAC'
	'flac':   'FLAC'
	'alac':   'ALAC'
	'opus':   'Opus'
	'vorbis': 'Vorbis'
	'mp3':    'MP3'
}
const sub_formats = {
	'subrip':            'SRT'
	'srt':               'SRT'
	'ass':               'ASS'
	'ssa':               'SSA'
	'webvtt':            'VTT'
	'hdmv_pgs_subtitle': 'PGS'
	'pgssub':            'PGS'
	'dvd_subtitle':      'VobSub'
	'dvdsub':            'VobSub'
	'vobsub':            'VobSub'
	'dvb_subtitle':      'DVB'
	'dvbsub':            'DVB'
	'dvb_teletext':      'Teletext'
	'mov_text':          'TX3G'
}
const sub_fonts = [
	['Microsoft YaHei', '微软雅黑 (Microsoft YaHei)'],
	['Microsoft JhengHei', '微軟正黑體 (JhengHei)'],
	['SimHei', '黑体 (SimHei)'],
	['Source Han Sans SC', '思源黑体 (Source Han Sans)'],
	['Noto Sans CJK SC', 'Noto Sans CJK'],
	['Yu Gothic UI', '游ゴシック (Yu Gothic)'],
	['Segoe UI', 'Segoe UI'],
]
const browsers = [['edge', 'Edge'], ['chrome', 'Chrome'], ['firefox', 'Firefox'],
	['brave', 'Brave'], ['opera', 'Opera']]
const codepages = [
	['utf-8', 'UTF-8'],
	['cp1251', 'Windows-1251'],
	['cp1252', 'Windows-1252'],
	['cp1250', 'Windows-1250'],
	['koi8-r', 'KOI8-R'],
	['cp866', 'CP866'],
	['gb18030', 'GB18030'],
	['big5', 'Big5'],
	['shift_jis', 'Shift_JIS'],
	['cp949', 'Windows-949'],
]
const track_langs = [
	['eng', 'english'],
	['chi,zho', 'chinese'],
	['jpn', 'japanese'],
	['kor', 'korean'],
	['fre', 'french'],
	['ger', 'german'],
	['spa', 'spanish'],
	['ita', 'italian'],
	['rus', 'russian'],
	['por', 'portuguese'],
]
const info_properties = ['file-format', 'duration', 'file-size', 'video-codec', 'video-format',
	'video-params/w', 'video-params/h', 'container-fps', 'video-bitrate', 'video-params/pixelformat',
	'video-params/colormatrix', 'video-params/primaries', 'video-params/gamma', 'track-list']

pub fn section(text string) Control {
	return ft.Container(ft.Text(text.to_upper(), 11, dim, ft.FontWeight.W_600), ft.Padding.only(10,
		2))
}

pub fn empty(text string) Control {
	return ft.Container(ft.Text(text, 13, dim), ft.Padding.symmetric(8))
}

pub fn item(app Any, title string, on_click Any, active Any, leading Any, trailing Any, subtitle Any) Control {
	row := [
		if leading != none { ft.Container(leading, 24, ft.Alignment.CENTER) } else { none },
		ft.Column(([ft.Text(title, 13, text, 2, ft.TextOverflow.ELLIPSIS)]).concat(if subtitle { [
				ft.Text(subtitle, 11, dim, 1, ft.TextOverflow.ELLIPSIS)] } else { [] }), 1, true),
		trailing,
	]
	return ft.Container(ft.Row(row.filter(it != none).map(it), 8),
		if active { active } else { none }, 10, ft.Padding.symmetric(8, 7), on_click, true)
}

pub fn tabs(app Any, choices [][2]string, current string, on_pick Any) Control {
	mut buttons := []
	for value, label in choices {
		selected := value == current
		buttons << ft.Container(ft.Text(label, 13, if selected { text } else { dim }, if selected {
			ft.FontWeight.W_600
		} else {
			ft.FontWeight.NORMAL
		}), ft.Padding.symmetric(9, 6), 8, if selected { active } else { none }, app.callback(on_pick,
			value))
	}
	return ft.Row(buttons, 2, 2, true, true)
}

pub fn header(mut app Any, content Control) {
	app.panel_header.controls = [
		content,
		ft.IconButton(ft.Icons.KEYBOARD_DOUBLE_ARROW_RIGHT_ROUNDED, app.t('common.collapse'), 18,
			dim, app.callback(app.toggle_panel, '')),
	]
}

pub fn title(text string) Control {
	return ft.Text(text, 17, ft.FontWeight.W_600, text, true, 1, ft.TextOverflow.ELLIPSIS)
}

pub fn lang_label(app Any, raw Any) string {
	if !raw {
		return ''
	}
	parts :=
		(regex.regex_opt('[-_,\\s]+') or { panic(err) }).split(raw.to_lower()).filter(it).map(it)
	key := if parts { lang_keys.get(parts[0]) } else { none }
	return if key { app.t('opt.lang.${key}') } else { raw }
}

pub fn looks_like_filename(text string) bool {
	if (regex.regex_opt('\\b(480p|576p|720p|1080p|2160p|bluray|remux|web-?dl|webrip|hdtv|x264|x265|hevc|avc)\\b') or {
		panic(err)
	}).find(text)
	{
		return true
	}
	return text.count('.') >= 3 && !text.contains(' ')
}

pub fn audio_label(app Any, track map[string]Any) string {
	codec := ((track['codec'] or { none }) || '').to_lower()
	name := audio_formats.get(codec)
		|| (if codec.starts_with('pcm') { 'PCM' } else { codec.to_upper() })
	channels := track['demux-channel-count'] or { none }
	layout := channel_layout(channels) || (if channels { '${channels}ch' } else { '' })
	mut main := ([lang_label(app, track['lang'] or { none }), name, layout].filter(it).map(it))
	rate := track['demux-bitrate'] or { none }
	if main && rate {
		main = '${main}   ${math.round(rate / 1000)} kbps'
	}
	raw := (track['title'] or { none }) || ''
	named := if raw && !looks_like_filename(raw) { raw } else { '' }
	if named && main {
		return '${named} · ${main}'
	}
	return main || named || app.t('panel.trackN')
}

pub fn subtitle_label(app Any, track map[string]Any) string {
	mut raw := (track['title'] or { none }) || ''
	raw = if raw && !looks_like_filename(raw) { raw } else { '' }
	named := lang_label(app, track['lang'] or { none })
	if named {
		descriptors := (['SDH', 'Forced', 'CC'].filter((regex.regex_opt('\\b${it}\\b') or {
			panic(err)
		}).find(rait)).map(it))
		return [named, descriptors].filter(it).map(it)
	}
	cleaned := (regex.regex_opt('\\b(subrip|srt|sup|pgs|pgssub|vobsub|ass|ssa|webvtt|dvb)\\b') or {
		panic(err)
	}).replace((regex.regex_opt('[._\\-]+') or { panic(err) }).replace(raw, ' '), ' ')
	return (regex.regex_opt('\\s+') or { panic(err) }).replace(cleaned, ' ').trim_space()
		|| app.t('panel.trackN')
}

pub fn tag(text string) ?Control {
	if !text {
		return none
	}
	return ft.Container(ft.Text(text, 10, dim), ft.Border.all(1, line), 6, ft.Padding.symmetric(6,
		1))
}

pub fn fill(mut app Any) {
	mode := app.panel_mode
	builders := {
		'tracks':   tracks
		'playlist': queue
		'chapters': chapters
		'library':  library
		'settings': settings
		'menu':     menu
		'info':     info
	}
	app.panel_header.controls, app.panel_body.controls = [], []
	if (mode in builders) {
		builders[mode](app)
	}
}

pub fn player_tabs(app Any) {
	t := app.t
	mut choices := [
		['tracks', t('panel.tab.audioSub')],
		['playlist',
			t(if app.source_type == 'iptv' { 'panel.tab.channels' } else { 'panel.tab.playlist' })],
	]
	if app.properties.get('chapter-list') {
		choices << ['chapters', t('panel.tab.chapters')]
	}
	header(mut app, tabs(app, choices, app.panel_mode, app.show_panel))
}

pub fn tracks(app Any) {
	t := app.t
	player_tabs(app)
	mut body := app.panel_body.controls
	all_tracks := app.properties.get('track-list') || []
	audio := all_tracks.filter(it.get('type') == 'audio').map(it)
	subs := all_tracks.filter(it.get('type') == 'sub').map(it)
	body << section(t('panel.sec.audio'))
	if !audio {
		body << empty(t('panel.empty.audio'))
	}
	for track in audio {
		body << item(app, audio_label(app, track), app.callback(app.select_audio, track['id']),
			(track.get('selected') != 0), tag(if track.get('external') { 'EXT' } else { '' }))
	}
	body << ft.TextButton(t('panel.addAudio'), ft.Icons.ADD, app.add_audio)
	body << section(t('panel.sec.subtitles'))
	body << item(app, t('panel.subNone'), app.callback(app.select_subtitle, 'no'),
		!subs.map(it.get('itelected')).any(it))
	for track in subs {
		codec := (track.get('codec') || '').to_lower()
		body << item(app, subtitle_label(app, track),
			app.callback(app.select_subtitle, track['id']), (track.get('selected') != 0), tag(
			sub_formats.get(codec) || codec.to_upper()))
	}
	body << ft.TextButton(t('panel.addSub'), ft.Icons.ADD, app.add_subtitle)
	body << adjustments(app)
}

pub fn stepper(label Any, value_text Any, minus_hint Any, plus_hint Any, minus Any, plus Any) Any {
	return ft.Row([
		ft.Text(label, 12, dim, 72),
		ft.IconButton(ft.Icons.REMOVE_ROUNDED, 16, minus_hint, minus),
		ft.Text(value_text, 12, text, 64, ft.TextAlign.CENTER),
		ft.IconButton(ft.Icons.ADD_ROUNDED, 16, plus_hint, plus),
	].map(Any(it)), 0)
}

pub fn reset(_ Any) {
	for name, value in [['sub-delay', 0], ['sub-pos', 100], ['sub-scale', 1]] {
		app.set_property(name, value)
	}
}

pub fn adjustments(app Any) []Control {
	t, props := app.t, app.properties
	delay := f64(props.get('sub-delay') || 0)
	position := int(props.get('sub-pos') || 100)
	scale := f64(props.get('sub-scale') || 1)
	active := math.abs(delay) > 0.001 || position != 100 || math.abs(scale - 1) > 0.001
	return [
		section(if active { t('adjust.active') } else { t('adjust.label') }),
		stepper(t('adjust.delay'), '${delay}s', t('adjust.earlier'), t('adjust.later'), app.callback(app.command,
			'add', 'sub-delay', -0.1), app.callback(app.command, 'add', 'sub-delay', 0.1)),
		stepper(t('adjust.position'), position, t('adjust.moveUp'), t('adjust.moveDown'), app.callback(app.command,
			'add', 'sub-pos', -1), app.callback(app.command, 'add', 'sub-pos', 1)),
		stepper(t('adjust.size'), '${scale}×', t('adjust.smaller'), t('adjust.larger'), app.callback(app.command,
			'add', 'sub-scale', -0.05), app.callback(app.command, 'add', 'sub-scale', 0.05)),
		ft.TextButton(t('adjust.reset'), ft.Icons.RESTART_ALT_ROUNDED, reset, !active),
	]
}

pub fn search(event Any) {
	app.channel_query = event.control.value || ''
	app.fill_panel()
	app.page.update()
}

pub fn queue(mut app Any) {
	t := app.t
	player_tabs(app)
	mut body := app.panel_body.controls
	body << ft.Row([
		ft.TextButton(t('panel.repeat.${app.repeat}'), app.cycle_repeat),
		ft.TextButton(t(if app.shuffle { 'panel.shuffle.on' } else { 'panel.shuffle.off' }),
			app.toggle_shuffle),
	].map(Any(it)), 0, true)
	mut entries := (fn () [][]Any {
		mut r := [][]Any{}
		for i, v in app.queue {
			r << [Any(i), v]
		}
		return r
	}())
	if app.source_type == 'iptv' {
		// pass
		body << ft.TextField(app.channel_query, t('panel.searchChannels'), true, ft.Icons.SEARCH,
			search, 10)
		query := app.channel_query.casefold().trim_space()
		if query {
			entries =
				entries.filter(query in e.title.casefold() || query in e.group.casefold()).map(it)
			if !entries {
				body << empty(t('panel.noMatches'))
			}
		}
	}
	if !app.queue {
		body << empty(t('panel.empty.queue'))
	}
	mut group := none
	for index, entry in entries[..1500] {
		if app.source_type == 'iptv' && entry.group != group {
			group = entry.group
			body << section(group || t('panel.ungrouped'))
		}
		current := index == app.index
		body << item(app, entry.title || media_name(entry.path),
			app.callback(app.play_index, index), current, if current {
			ft.Icon(ft.Icons.PLAY_ARROW_ROUNDED, 16, text)
		} else {
			ft.Text((index + 1), 11, faint)
		}, ft.IconButton(ft.Icons.CLOSE_ROUNDED, 15, faint, t('lib.remove'), app.callback(app.remove_item,
			index)))
	}
	collection := app.collection_key()
	saved := collection != 0 && app.profile.is_favourite(collection)
	body << ft.Row([
		ft.TextButton(t('panel.addFiles'), ft.Icons.ADD, app.add_files),
		ft.TextButton(t('menu.home'), ft.Icons.HOME_OUTLINED, app.go_home),
		ft.IconButton(if saved { ft.Icons.STAR_ROUNDED } else { ft.Icons.STAR_BORDER_ROUNDED }, 18, if saved {
			text
		} else {
			dim
		}, !collection, app.save_collection, t(if app.source_type == 'iptv' {
			'panel.saveSource'
		} else {
			'panel.savePlaylist'
		})),
	].map(Any(it)), true, 0)
}

pub fn chapters(app Any) {
	t := app.t
	player_tabs(app)
	mut body := app.panel_body.controls
	chapter_list := app.properties.get('chapter-list') || []
	current := app.properties.get('chapter')
	if !chapter_list {
		body << empty(t('panel.empty.chapters'))
	}
	for index, chapter in chapter_list {
		active := index == current
		body << item(app, chapter.get('title') || t('panel.chapterN', index + 1), app.callback(app.set_property,
			'chapter', index), active, if active {
			ft.Icon(ft.Icons.PLAY_ARROW_ROUNDED, 16, text)
		} else {
			ft.Text((index + 1), 11, faint)
		}, ft.Text(clock(chapter.get('time')), 11, dim))
	}
}

pub fn pick(tab Any) {
	app.library_tab = tab
	app.fill_panel()
	app.page.update()
}

pub fn library(mut app Any) {
	t, profile := app.t, app.profile
	header(mut app, tabs(app, [['recent', t('lib.recent')], ['saved', t('lib.favourites')],
		['playlists', t('lib.playlists')], ['live', t('lib.live')]].map(Any(it)), app.library_tab,
		pick))
	mut body := app.panel_body.controls
	icons := {
		'list':     ft.Icons.LIVE_TV_ROUNDED
		'url':      ft.Icons.LINK_ROUNDED
		'playlist': ft.Icons.QUEUE_MUSIC_ROUNDED
	}
	if app.library_tab == 'recent' {
		if !profile.recents {
			body << empty(t('lib.emptyRecent'))
		}
		for entry in profile.recents {
			mut saved := profile.is_favourite(entry['target'])
			body << item(app, entry.get('name') || entry['target'], app.callback(app.open_saved,
				entry), ft.Icon(icons[entry.get('kind')] or { ft.Icons.HISTORY_ROUNDED }, 18, dim),
				entry['target'], ft.Row([
				ft.IconButton(if saved {
					ft.Icons.STAR_ROUNDED
				} else {
					ft.Icons.STAR_BORDER_ROUNDED
				}, 15, if saved { dim } else { faint }, t('lib.addFav'), saved, app.callback(app.favourite_recent,
					entry['target'])),
				ft.IconButton(ft.Icons.CLOSE_ROUNDED, 15, faint, t('lib.remove'), app.callback(remove_recent,
					app, entry['target'])),
			].map(Any(it)), 0, true))
		}
		if profile.recents {
			body << ft.TextButton(t('lib.clearRecents'), ft.Icons.DELETE_SWEEP_OUTLINED,
				app.callback(confirm_clear, app))
		}
		return
	}
	kinds := {
		'saved':     ['file', 'url']
		'playlists': ['playlist']
		'live':      ['list']
	}[app.library_tab]
	entries := profile.favourites.filter((it.get('kind', 'file') in kinds)).map(it)
	if app.library_tab == 'saved' && app.has_media {
		saved = profile.is_favourite(app.open_target_kind[0])
		body << ft.TextButton(t('menu.favourite'), app.favourite_current, if saved {
			ft.Icons.STAR_ROUNDED
		} else {
			ft.Icons.STAR_BORDER_ROUNDED
		})
	}
	if !entries {
		body << empty(t({
			'saved':     'lib.emptyFav'
			'playlists': 'lib.emptyPlaylists'
			'live':      'lib.emptyLive'
		}[app.library_tab]))
	}
	for entry in entries {
		count := (entry.get('channels') || entry.get('items') || []).len
		body << item(app, entry.get('name') || entry['target'],
			app.callback(app.open_saved, entry), ft.Icon(icons[entry.get('kind')] or {
			ft.Icons.MOVIE_OUTLINED
		}, 18, dim), if count { '${count} · ${entry['target']}' } else { entry['target'] }, ft.Row([
			ft.IconButton(ft.Icons.EDIT_OUTLINED, 15, faint, t('lib.rename'), app.callback(rename_favourite,
				app, entry)),
			ft.IconButton(ft.Icons.CLOSE_ROUNDED, 15, faint, t('lib.remove'), app.callback(remove_favourite,
				app, entry)),
		].map(Any(it)), 0, true))
	}
}

pub fn remove_recent(app Any, target string) {
	app.profile.remove_recent(target)
	app.fill_panel()
	app.page.update()
}

pub fn close(_ Any) {
	app.dialog_open = false
	app.page.pop_dialog()
	app.refresh()
}

pub fn clear(_ Any) {
	app.profile.clear_recents()
	close(none)
	app.fill_panel()
	app.page.update()
}

pub fn confirm_clear(mut app Any) {
	app.dialog_open = true
	app.layout()
	app.page.show_dialog(ft.AlertDialog(true, ft.Text(app.t('lib.clearConfirm')), [
		ft.TextButton(app.t('common.close'), close),
		ft.Button(app.t('lib.clearRecents'), clear),
	], close))
}

pub fn remove_favourite(app Any, entry map[string]Any) {
	app.profile.toggle_favourite(entry['target'], entry['name'] or { '' })
	app.fill_panel()
	app.page.update()
}

pub fn close(_ Any) {
	app.dialog_open = false
	app.page.pop_dialog()
	app.refresh()
}

pub fn save(_ Any) {
	app.profile.rename_favourite(entry['target'], field.value || '')
	close(none)
	app.fill_panel()
	app.page.update()
}

pub fn rename_favourite(mut app Any, entry map[string]Any) {
	mut field := ft.TextField(entry['name'] or { '' }, 420, true)
	field.on_submit = save
	app.dialog_open = true
	app.layout()
	app.page.show_dialog(ft.AlertDialog(true, ft.Text(app.t('lib.rename')), field, [
		ft.TextButton(app.t('common.close'), close),
		ft.Button(app.t('lib.rename'), save),
	], close))
}

pub fn pick(tab Any) {
	app.settings_tab = tab
	app.fill_panel()
	app.page.update()
}

pub fn row(label Any, control Any, desc Any) Any {
	mut parts := [
		ft.Row([ft.Text(label, 13, text, true), control].map(Any(it)), ft.CrossAxisAlignment.CENTER),
	]
	if desc {
		parts << ft.Text(desc, 11, dim)
	}
	return ft.Container(ft.Column(parts, 2), ft.Padding.only(8, 6))
}

pub fn change(event Any) {
	app.change_setting(key, (event.control.value != 0))
	if refill {
		app.fill_panel()
		app.page.update()
	}
}

pub fn toggle(key Any, label Any, desc Any, refill Any) Any {
	return row(label, ft.Switch((s.get(key) != 0), change, 0.8), desc)
}

pub fn change(event Any) {
	app.change_setting(key, event.control.value)
	app.fill_panel()
	app.page.update()
}

pub fn select(key Any, label Any, opts Any, desc Any, width Any) Any {
	return row(label, ft.Dropdown((s.get(key)), width, true, 12,
		opts.map(ft.DropdownOption(v_, l)), change), desc)
}

pub fn moving(event Any) {
	reading.value = '${f64(event.control.value)}'
	reading.update()
}

pub fn change(event Any) {
	number := math.round_sig(f64(event.control.value), digits)
	app.change_setting(key, if digits == 0 { int(number) } else { number })
}

pub fn slider(key Any, label Any, low Any, high Any, step Any, desc Any, digits Any) Any {
	value := arrays.min([high, arrays.max([low, f64(s.get(key) || 0)]) or { panic('!') }]) or {
		panic('!')
	}
	mut reading := ft.Text('${value}', 12, dim, 40, ft.TextAlign.RIGHT)
	control := ft.Row([
		ft.Slider(low, high, value, math.round((high - low) / step), 150, moving, change),
		reading,
	].map(Any(it)), 0, true)
	return row(label, control, desc)
}

pub fn browse(_ Any) {
	folder := app.with_dialog(fn () string {
		return ft.FilePicker().get_directory_path(t('dlg.chooseShotDir'), s.get('screenshotDir')
			|| none)
	})
	if folder {
		app.change_setting('screenshotDir', folder)
		app.fill_panel()
		app.page.update()
	}
}

pub fn settings(mut app Any) {
	t, s := app.t, app.settings
	choices := [
		['playback', t('set.tab.playback')],
		['subs', t('set.tab.subs')],
		['interface', t('set.tab.interface')],
		['general', t('set.tab.general')],
	]
	header(mut app, tabs(app, choices, app.settings_tab, pick))
	mut body := app.panel_body.controls
	tab := app.settings_tab
	if tab == 'playback' {
		body += [
			section(t('set.sec.playlist')),
			toggle('scanFolderIntoPlaylist', t('set.scanFolder.label'), t('set.scanFolder.desc'),
				false),
			toggle('resumePlayback', t('set.resume.label'), t('set.resume.desc'), false),
			toggle('resumePlaylistItem', t('set.resumePlaylist.label'),
				t('set.resumePlaylist.desc'), false),
			section(t('set.sec.audio')),
			toggle('keepPitch', t('set.keepPitch.label'), t('set.keepPitch.desc'), false),
			toggle('audioPassthrough', t('set.passthrough.label'), t('set.passthrough.desc'), false),
			@select('audioLang', t('set.audioLang.label'), track_langs(app),
				t('set.audioLang.desc')),
			section(t('set.sec.video')),
			@select('hwdec', t('set.hwdec.label'), [['auto', t('opt.hwdec.auto')],
				['auto-copy', t('opt.hwdec.autoCopy')], ['no', t('opt.hwdec.off')]].map(Any(it)), {
				'auto':      t('set.hwdec.auto')
				'auto-copy': t('set.hwdec.autoCopy')
				'no':        t('set.hwdec.off')
			}[s.get('hwdec')] or { none }),
			@select('deinterlace', t('set.deint.label'), [['auto', t('opt.deint.auto')],
				['yes', t('opt.deint.on')], ['no', t('opt.deint.off')]].map(Any(it)),
				t('set.deint.desc')),
			@select('streamQuality', t('set.quality.label'), [
				['best', t('opt.quality.best')], ['2160', '2160p (4K)'],
				['1080', '1080p'], ['720', '720p'], ['480', '480p']].map(Any(it)),
				t('set.quality.desc')),
			toggle('useCookies', t('set.cookies.label'), t('set.cookies.desc'), false, true),
		]
		if s.get('useCookies') {
			body << @select('cookiesBrowser', t('set.cookiesFrom.label'), browsers)
		}
	} else if tab == 'subs' {
		body += [
			section(t('set.sec.subtitles')),
			@select('subLang', t('set.subLang.label'), track_langs(app), t('set.subLang.desc')),
			toggle('subsDefaultOn', t('set.subsDefault.label'), none, false),
			toggle('autoLoadSubs', t('set.autoLoadSubs.label'), t('set.autoLoadSubs.desc'), false),
			@select('subCodepage', t('set.subCodepage.label'),

				[['auto', t('opt.subCodepage.auto')]] + codepages, t('set.subCodepage.desc')),
			slider('subHdrPeak', t('set.hdrSubPeak.label'), 50, 400, 5, t('set.hdrSubPeak.desc'), 0),
			section(t('set.sec.subAppearance')),
			@select('subFont', t('set.subFont.label'), sub_fonts +
				[['sans-serif', t('opt.subFont.system')]], t('set.subFont.desc'), 190),
			slider('subFontSize', t('set.subSize.label'), 20, 80, 1, none, 0),
			slider('subSpacing', t('set.subSpacing.label'), -3, 10, 0.5, t('set.subSpacing.desc'), 1),
			slider('subOutline', t('set.subOutline.label'), 0, 10, 0.5, t('set.subOutline.desc'), 1),
			toggle('subBold', t('set.subBold.label'), none, false),
			slider('subMarginY', t('set.subMargin.label'), 0, 200, 2, t('set.subMargin.desc'), 0),
		]
	} else if tab == 'interface' {
		body += [
			section(t('set.sec.interface')),
			@select('uiLanguage', t('set.uiLang.label'), LANG_OPTIONS.map([v_, if v_ == 'system' {
				t('opt.uiLang.system')
			} else {
				l
			}]), t('set.uiLang.desc')),
			section(t('set.sec.controls')),
			@select('oscStyle', t('set.oscStyle.label'), [['floating', t('opt.oscStyle.floating')],
				['docked', t('opt.oscStyle.docked')]].map(Any(it)),
				'${t('set.oscStyle.desc1')}\n${t('set.oscStyle.desc2')}'),
			slider('oscHideDelay', t('set.oscDelay.label'), 1, 15, 1,
				'${t('set.oscDelay.desc1')}\n${t('set.oscDelay.desc2')}', 0),
			toggle('seekPreview', t('set.seekPreview.label'), t('set.seekPreview.desc'), false),
			section(t('set.sec.window')),
			toggle('rememberWindow', t('set.rememberWindow.label'), none, false),
			toggle('rememberVolume', t('set.rememberVolume.label'), none, false),
		]
	} else {
		// pass
		body += [
			section(t('set.sec.screenshots')),
			toggle('screenshotSubs', t('set.shotSubs.label'), t('set.shotSubs.desc'), false),
			@select('screenshotFormat', t('set.shotFormat.label'), [
				['png', t('opt.shot.png')],
				['jpg', t('opt.shot.jpg')],
			].map(Any(it)), t('set.shotFormat.desc')),
			row(t('set.shotDir.label'), ft.TextButton(t('set.shotDir.browse'), browse),
				'${s.get('screenshotDir')}\n${t('set.shotDir.desc')}'),
			section(t('set.sec.about')),
			row(t('set.ytdl.label'), ft.TextButton(t('set.ytdl.update'), app.refresh_ytdl,
				app.ytdl_state == 'working'),
				({
				'working': t('set.ytdl.working')
				'done':    t('set.ytdl.done')
				'error':   t('set.ytdl.failed')
			}[app.ytdl_state] or { t('set.ytdl.desc') }) +
				(if app.ytdl.version { '\nyt-dlp ${app.ytdl.version}' } else { '' })),
			ft.Text('Lunoir 0.9.4 by Yao666 (MIT) · Flet front end · V libmpv binding (GPL-3.0-or-later)\ngithub.com/skonester/Lunoir-V',
				11, dim, true),
		]
		app.show_ytdl_version()
	}
}

pub fn track_langs(app Any) [][2]string {
	return [['', app.t('common.default')]] + track_langs.map([code, app.t('opt.lang.${key}')])
}

pub fn action(label Any, handler Any, icon Any, disabled Any, checked Any) Any {
	return ft.Container(ft.Row([
		ft.Icon(icon, 18, if disabled { faint } else { dim }),
		ft.Text(label, 13, if disabled { faint } else { text }, true),
		if checked { ft.Icon(ft.Icons.CHECK_ROUNDED, 16, text) } else { ft.Container() },
	].map(Any(it)), 12), ft.Padding.symmetric(8, 8), 10, if disabled { none } else { handler },
		!disabled)
}

pub fn chips(options_ Any, current Any, handler Any) Any {
	return ft.Row(options_.map(ft.Chip(ft.Text(label, 12), current == value, app.callback(handler,
		value))), true, 6, 6)
}

pub fn menu(app Any) {
	t, props := app.t, app.properties
	header(mut app, title(app.window_title()))
	mut body := app.panel_body.controls
	multi := app.queue.len > 1
	has_chapters := (props.get('chapter-list') != 0)
	paused := (props.get('pause') != 0)
	a, b := props.get('ab-loop-a'), props.get('ab-loop-b')
	a_set, b_set := (a is int || a is float), (b is int || b is float)
	loop_label := if !a_set {
		t('menu.abStart')
	} else {
		if !b_set { t('menu.abEnd') } else { t('menu.abClear') }
	}
	speed := props.get('speed') || 1
	current_speed := next(speeds.filter(math.abs(speed - it) < 0.01).map(it), none)
	body += [
		action(if paused { t('osc.play') } else { t('osc.pause') }, app.callback(app.command,
			'cycle', 'pause'), if paused {
			ft.Icons.PLAY_ARROW_ROUNDED
		} else {
			ft.Icons.PAUSE_ROUNDED
		}, false, false),
		ft.Divider(line, 8),
		action(t('menu.previous'), app.callback(app.advance, -1), ft.Icons.SKIP_PREVIOUS_ROUNDED,
			!multi, false),
		action(t('menu.next'), app.callback(app.advance, 1), ft.Icons.SKIP_NEXT_ROUNDED, !multi,
			false),
		action(t('menu.prevChapter'), app.callback(app.command, 'add', 'chapter', -1),
			ft.Icons.FIRST_PAGE_ROUNDED, !has_chapters, false),
		action(t('menu.nextChapter'), app.callback(app.command, 'add', 'chapter', 1),
			ft.Icons.LAST_PAGE_ROUNDED, !has_chapters, false),
		ft.Divider(line, 8),
		section(t('menu.speed')),
		chips(speeds.map([it, if it == 1 { t('menu.speedNormal') } else { '${it}×' }]),
			current_speed, app.set_speed),
		section(t('menu.aspect')),
		chips([['default', t('common.default')], ['16:9', '16:9'],
			['4:3', '4:3'], ['2.35', '2.35:1'], ['stretch', t('menu.aspectStretch')]].map(Any(it)),
			app.aspect, app.set_aspect),
		ft.Divider(line, 8),
		action(loop_label, app.callback(app.command, 'ab-loop'), ft.Icons.REPEAT_ROUNDED, false,
			false, a_set && b_set),
		action(t('menu.screenshot'), app.screenshot, ft.Icons.PHOTO_CAMERA_OUTLINED, false, false),
		action(t('menu.favourite'), app.favourite_current, ft.Icons.STAR_BORDER_ROUNDED, false,
			false, app.profile.is_favourite(app.open_target_kind[0])),
		action(t('info.title'), app.callback(app.toggle_panel, 'info'),
			ft.Icons.INFO_OUTLINE_ROUNDED, false, false),
		ft.Divider(line, 8),
		action(t('menu.home'), app.go_home, ft.Icons.HOME_OUTLINED, false, false),
		action(t('menu.openFile'), app.open_files, ft.Icons.FOLDER_OPEN_OUTLINED, false, false),
		action(t('appmenu.openFolder'), app.open_folder, ft.Icons.DRIVE_FOLDER_UPLOAD_OUTLINED,
			false, false),
		action(t('menu.openUrl'), app.open_url, ft.Icons.LINK_ROUNDED, false, false),
		ft.Divider(line, 8),
		action(t('menu.fullscreen'), app.fullscreen, ft.Icons.FULLSCREEN_ROUNDED, false, false,
			(app.page.window.full_screen != 0)),
	]
}

pub fn load_info(mut app Any) {
	mut data := map[string]Any{}
	for name in info_properties {
		value := app.try_command('get_property', name)
		if value != none && value != true {
			data[name] = value
		}
	}
	app.info_data = data
}

pub fn line(label Any, value Any) {
	if (value in [none, '', 0]) {
		return
	}
	body << ft.Row([ft.Text(label, 12, dim, 110), ft.Text(value, 12, text, true, true)].map(Any(it)))
}

pub fn info(app Any) {
	t := app.t
	data := app.info_data
	header(mut app, title(t('info.title')))
	mut body := app.panel_body.controls
	if !data {
		body << empty(t('info.noData'))
		return
	}
	duration, size := data.get('duration'), data.get('file-size')
	line(t('info.container'), data.get('file-format'))
	line(t('info.duration'), if duration { duration_text(duration) } else { none })
	line(t('info.fileSize'), if size { file_size(size) } else { none })
	if size && duration {
		line(t('info.overallBitRate'), bitrate(size * 8 / duration))
	}
	width, height := data.get('video-params/w'), data.get('video-params/h')
	if width || height {
		body << section(t('info.video'))
	}
	line(t('info.codec'), data.get('video-codec') || data.get('video-format'))
	line(t('info.resolution'), if width && height { '${width} × ${height}' } else { none })
	fps := data.get('container-fps')
	line(t('info.frameRate'), if fps {
		'${fps}'.trim_right('0').trim_right('.') + ' fps'
	} else {
		none
	})
	line(t('info.bitRate'), if data.get('video-bitrate') {
		bitrate(data['video-bitrate'])
	} else {
		none
	})
	pixel := (data.get('video-params/pixelformat') || '')
	depth := (regex.regex_opt('p(\\d{2})') or { panic(err) }).find(pixel)
	line(t('info.bitDepth'), if pixel { '${if depth { depth.group(1) } else { 8 }}-bit'
	 } else { none
	 })
	space := (['video-params/colormatrix', 'video-params/primaries'].filter(data.get(it)).map((data[it])))
	line(t('info.colorSpace'), space)
	line(t('info.hdr'), hdr_label(data.get('video-params/gamma')))
	audio := (data.get('track-list') || []).filter(it.get('type') == 'audio').map(it)
	if audio {
		body << section(t('info.audio'))
	}
	for track in audio {
		body << ft.Text(audio_label(app, track), 12, if track.get('selected') { text } else { dim })
	}
}
