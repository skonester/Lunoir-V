module main

#include "@VMODROOT/v_lunoir/drop_win.h"

@[typedef]
struct C.LunoirDrop {}

fn C.lv_drop_create(voidptr) &C.LunoirDrop
fn C.lv_drop_take(&C.LunoirDrop) &char
fn C.lv_drop_close(&C.LunoirDrop)

fn drop_requests(drop &C.LunoirDrop) []string {
	return owned_c_string(C.lv_drop_take(drop)).split_into_lines().filter(it != '')
}
