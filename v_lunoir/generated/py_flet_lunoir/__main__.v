module py_flet_lunoir

import log
import os

// TODO(py2v): no V equivalent for import flet
// Provide one in python_to_v_import (types.v) or port the module.

const runtime = ROOT / 'flet_lunoir/runtime/flet/flet/flet.exe'
// TODO(py2v): module-level if statement has no place in a V module; move it into a function and call it explicitly.
const log_dir = os.join_path(os.environ.get('LOCALAPPDATA', ROOT), 'Lunoir V')
// TODO(py2v): module-level expression has no place in a V module; move it into a function and call it explicitly.
const startup = targets(os.args[1..])
const instance = Instance{
	mutex_name: Profile.default_directory()
}
// TODO(py2v): module-level if statement has no place in a V module; move it into a function and call it explicitly.
// TODO(py2v): module-level expression has no place in a V module; move it into a function and call it explicitly.

type Any = bool | int | i64 | f64 | string | []u8

pub fn start(page Any) {
	main(page, startup, instance)
}
