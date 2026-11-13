module main

import math
import os
import x.json2

fn object(value json2.Any) map[string]json2.Any {
	if value is map[string]json2.Any { return value }
	return map[string]json2.Any{}
}

fn list_value(value json2.Any) []json2.Any {
	if value is []json2.Any { return value }
	return []json2.Any{}
}

fn get(data map[string]json2.Any, key string) json2.Any {
	return data[key] or { json2.Any(json2.Null{}) }
}

fn text_value(value json2.Any) string {
	if value is json2.Null { return '' }
	return value.str()
}

fn number(value json2.Any) f64 {
	n := value.f64()
	return if math.is_nan(n) || math.is_inf(n, 0) { 0.0 } else { n }
}

fn truth(value json2.Any) bool {
	return match value {
		json2.Null { false }
		bool { value }
		string { value.len > 0 }
		[]json2.Any { value.len > 0 }
		map[string]json2.Any { value.len > 0 }
		else { number(value) != 0 }
	}
}

fn strings(value json2.Any) []string {
	return list_value(value).map(text_value(it))
}

fn json_read(path string, fallback json2.Any) json2.Any {
	content := os.read_file(path) or { return fallback }
	value := json_decode(content) or { return fallback }
	if fallback is map[string]json2.Any && value is map[string]json2.Any { return value }
	if fallback is []json2.Any && value is []json2.Any { return value }
	return fallback
}

fn clamp(value f64, low f64, high f64) f64 {
	return math.max(low, math.min(high, value))
}
