@[translated]

module py_flet_lunoir

import json
import log
import os

// TODO(py2v): no V equivalent for import asyncio, uuid, win32api, win32con, win32job
// Provide one in python_to_v_import (types.v) or port the module.

// TODO(py2v): no V mapping for asyncio.Queue, win32api.CloseHandle, win32api.OpenProcess, win32job.AssignProcessToJobObject, win32job.CreateJobObject, win32job.QueryInformationJobObject, win32job.SetInformationJobObject
// Each site below is stubbed with a zero value.

// TODO(py2v): 1 except handler(s) need a V Result equivalent:
//   except Exception (1 stmt)

const root = os.abs_path(file___).parent.parent
const log = log :=
const observed = ['pause', 'time-pos', 'duration', 'volume', 'mute', 'speed', 'filename', 'media-title', 'metadata/by-key/uploader', 'eof-reached', 'ab-loop-a', 'ab-loop-b', 'seekable', 'path', 'chapter', 'chapter-list', 'video-params/aspect', 'track-list', 'aid', 'sid', 'audio-delay', 'sub-delay', 'sub-pos', 'sub-scale', 'container-fps', 'estimated-frame-count', 'estimated-frame-number', 'video-params/gamma', 'video-params/w', 'video-params/h', 'audio-codec-name', 'audio-params/channel-count']
const job_ = none

pub struct MpvError {
}

pub struct MpvController {
pub mut:
	log_directory Any
	process ?subprocess.Popen
	writer ?asyncio.StreamWriter
	reader_task ?asyncio.Task
	pending map[int]asyncio.Future
	events asyncio.Queue[dict]
	request_id Any
	closing Any
	log Any
}

pub fn (mut self MpvController) init(log_directory ?Path) {
	self.log_directory = log_directory
	self.process = none
	self.writer = none
	self.reader_task = none
	self.pending = map[string]Any{}
	self.events = Any(0)
	self.request_id = 0
	self.closing = false
	self.log = none
}

pub fn tie_to_this_process(pid int)  {
	// global _job: prefer mut parameter or struct field over __global

	if job_ == none {
		job := Any(0)
		mut info := Any(0)
		info['BasicLimitInformation']['LimitFlags'] |= win32job.JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
		_ = Any(0)
		job_ := job
	}
	handle := Any(0)
	defer {
		_ = Any(0)
	}
	_ = Any(0)
	// except handlers are not translated: see the TODO(py2v) note above
	//   except Exception: 1 statement(s) need an `or { ... }` equivalent
}
