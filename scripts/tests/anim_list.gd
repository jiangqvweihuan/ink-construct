extends Node2D

## 枚举 art/characters 下全部骨架的动画名 + 时长，写入 tests/anim_list.log
## 自动扫描所有 *_data.tres，不用再手写 DATA_PATHS。
## 想直接看动作本身用 anim_viewer.tscn（左右切骨架、上下切动画）。

const ROOT := "res://art/characters"

var _log


func p(msg: String) -> void:
	print("[A] ", msg)
	if _log:
		_log.store_line("[A] " + msg)
		_log.flush()


func _ready() -> void:
	_log = FileAccess.open("res://tests/anim_list.log", FileAccess.WRITE)
	var paths := _find(ROOT)
	paths.sort()
	p("skeletons=%d" % paths.size())
	for path in paths:
		p("##### " + path)
		var data = load(path)
		if data == null or not data.call("is_skeleton_data_loaded"):
			p("FAIL: skeleton data not loaded")
			continue
		var all: Array = data.call("get_animations")
		p("total=%d" % all.size())
		for a in all:
			p("ANIM %-28s dur=%.3f" % [str(a.call("get_name")), a.call("get_duration")])
	p("done")
	get_tree().quit()


func _find(dir: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for sub in d.get_directories():
		out += _find(dir.path_join(sub))
	for f in d.get_files():
		if f.ends_with("_data.tres"):
			out.append(dir.path_join(f))
	return out
