module main

import os
import net
import time
import crypto.sha256

fn download_fixture(mut listener net.TcpListener, mode string, payload string, requests int) {
	base := 'http://${listener.addr() or { return }}'
	for _ in 0 .. requests {
		mut conn := listener.accept() or { return }
		mut input := []u8{len: 8192}
		count := conn.read(mut input) or {
			conn.close() or {}
			return
		}
		path := input[..count].bytestr().all_after('GET ').all_before(' ')
		mut body := 'release fixture'
		mut status, mut headers := '200 OK', ''
		if path == '/latest' {
			if mode == 'unreachable' {
				status = '500 Internal Server Error'
			} else {
				status = '302 Found'
				headers = 'Location: ${base}/tag/2030.01.02\r\n'
			}
		} else if path.ends_with('SHA2-256SUMS') {
			digest := if mode == 'mismatch' {
				'0'.repeat(64)
			} else {
				sha256.sum(payload.bytes()).hex()
			}
			body = '${digest}  yt-dlp.exe\n'
		} else if path.ends_with('yt-dlp.exe') {
			body = payload
		}
		length := body.len
		if mode == 'truncated' && path.ends_with('yt-dlp.exe') { body = body[..body.len / 2] }
		conn.write_string('HTTP/1.1 ${status}\r\n${headers}Content-Length: ${length}\r\nConnection: close\r\n\r\n${body}') or {}
		conn.close() or {}
	}
}

fn test_native_ytdl_download_checks_integrity_and_preserves_old_copy() {
	directory := os.join_path(os.temp_dir(), 'lunoir-native-download-${time.now().unix_micro()}')
	os.mkdir_all(directory)!
	defer { os.rmdir_all(directory) or {} }
	exe := os.join_path(directory, 'yt-dlp.exe')
	for mode in ['valid', 'mismatch', 'truncated', 'unreachable'] {
		os.write_file(exe, 'old executable fixture')!
		mut listener := net.listen_tcp(.ip, '127.0.0.1:0')!
		listener.set_accept_timeout(5 * time.second)
		base := 'http://${listener.addr()!}'
		worker := spawn download_fixture(mut listener, mode, 'new executable fixture', if mode == 'unreachable' {
			1
		} else {
			4
		})
		mut succeeded := false
		if result := update_ytdl_from(exe, base) {
			succeeded = true
			assert text_value(get(object(result), 'version')) == '2030.01.02'
		}
		worker.wait()
		listener.close()!
		assert succeeded == (mode == 'valid'), mode
		assert os.read_file(exe)! == if mode == 'valid' {
			'new executable fixture'
		} else {
			'old executable fixture'
		}
		assert !os.exists(exe + '.part')
	}
}

fn test_native_text_decoder_and_ytdl_routing() {
	assert decode_source_text([u8(0xc4), 0xe3, 0xba, 0xc3].bytestr(), 'text/plain; charset=gbk') == '你好'
	assert decode_source_text([u8(0xe9)].bytestr(), 'text/plain; charset=windows-1252') == 'é'
	assert needs_ytdl('https://www.youtube.com/watch?v=abc')
	assert !needs_ytdl('https://example.test/video.MP4?token=1')
	assert !needs_ytdl('https://example.test/live.m3u8')
	assert is_playlist_url('https://www.youtube.com/playlist?list=123')
	assert ytdl_playlist_key('https://x/playlist?x=1&list=123&extra=2') == 'list:123'
	assert ytdl_error_text('ERROR: members only; please report this issue on GitHub') == 'members only'
	assert valid_ytdl_tag('2030.01.02.1') && !valid_ytdl_tag('1234567890')
}
