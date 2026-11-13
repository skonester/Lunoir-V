module main

import os
import crypto.sha1

@[typedef]
struct C.LunoirInstance {}

fn C.lv_instance_create(&u16, &u16) &C.LunoirInstance
fn C.lv_instance_claimed(&C.LunoirInstance) int
fn C.lv_instance_serve(&C.LunoirInstance, voidptr)
fn C.lv_instance_take(&C.LunoirInstance) &char
fn C.lv_instance_forward(&C.LunoirInstance, &char, int) int
fn C.lv_instance_close(&C.LunoirInstance)

fn new_instance(directory string) &C.LunoirInstance {
	key := sha1.sum(os.abs_path(directory).replace('/', '\\').to_lower().bytes()).hex()[..16]
	return C.lv_instance_create('Local\\LunoirV-${key}'.to_wide(),
		'\\\\.\\pipe\\lunoir-v-instance-${key}'.to_wide())
}

fn instance_requests(instance &C.LunoirInstance) [][]string {
	mut result := [][]string{}
	requests := owned_c_string(C.lv_instance_take(instance))
	for line in requests.split_into_lines() {
		data := json_decode(line) or { continue }
		result << strings(data)
	}
	return result
}
