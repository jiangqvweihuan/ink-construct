extends Node2D

## 枚举骨架全部动画名 + 时长，写入 tests/anim_list.log
## 改 DATA_PATHS 可一次枚举多套角色

const DATA_PATHS := [
	"res://art/characters/player/skulls/z000/z000_data.tres",
	"res://art/characters/player/skulls/c012/c012_data.tres",
	"res://art/characters/player/skulls/c013/c013_data.tres",
	"res://art/characters/player/skulls/c023/c023_data.tres",
	"res://art/characters/enemies/z002/z002_data.tres",
	"res://art/characters/enemies/c017/c017_data.tres",
	"res://art/characters/enemies/c035/c035_data.tres",
	"res://art/characters/enemies/c037/c037_data.tres",
	"res://art/characters/enemies/c018/c018_data.tres",
	"res://art/characters/enemies/bosses/c009/c009_data.tres",
	"res://art/characters/enemies/bosses/c015a1/c015a1_data.tres",
	"res://art/characters/enemies/bosses/c001/c001_data.tres",
]

var _log


func p(msg: String) -> void:
	print("[A] ", msg)
	if _log:
		_log.store_line("[A] " + msg)
		_log.flush()


func _ready() -> void:
	_log = FileAccess.open("res://tests/anim_list.log", FileAccess.WRITE)
	for path in DATA_PATHS:
		p("##### " + path)
		var data = load(path)
		if data == null or not data.call("is_skeleton_data_loaded"):
			p("FAIL: skeleton data not loaded")
			continue
		var all: Array = data.call("get_animations")
		p("total=%d" % all.size())
		for a in all:
			p("ANIM %s  dur=%.3f" % [str(a.call("get_name")), a.call("get_duration")])
	p("done")
	get_tree().quit()
