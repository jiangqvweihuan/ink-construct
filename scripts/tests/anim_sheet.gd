extends Node2D

## 临时工具：把指定骨架的多条动画按固定间隔逐帧截图，供人工确认招式视觉。
## 用法：写 tests/out/sheet_params.json（骨架路径 / 动画列表 / 输出前缀）后运行 anim_sheet.tscn。
## 输出 tests/out/sheet/<输出前缀>_<动画名>_<序号>.png

const OUT_DIR := "res://tests/out/sheet/"
const PARAM_FILE := "res://tests/out/sheet_params.json"
const INTERVAL := 0.09

var _anims: Array = []
var _out_name := "sheet"
var _skull_dir := ""
var _idx := 0
var _t := 0.0
var _shot_t := 0.0
var _shot_i := 0
var _dur := 0.0
var _sprite: Node2D
var _a_state
var _loaded := false
var _dir_path := ""


func _ready() -> void:
	_dir_path = ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(_dir_path)
	get_window().size = Vector2i(760, 560)

	var bg := ColorRect.new()
	bg.color = Color(0.949, 0.918, 0.847)
	bg.size = Vector2(760, 560)
	bg.z_index = -10
	add_child(bg)

	# 参数从 tests/out/sheet_params.json 读：{"skull":骨架路径,"anims":[...],"out":"输出名前缀"}
	var raw := ""
	if FileAccess.file_exists(PARAM_FILE):
		raw = FileAccess.get_file_as_string(PARAM_FILE)
	var cfg = JSON.parse_string(raw) if raw != "" else null
	if typeof(cfg) != TYPE_DICTIONARY:
		print("[SHEET] FAIL params ", PARAM_FILE)
		get_tree().quit()
		return
	_skull_dir = str(cfg.get("skull", ""))
	_out_name = str(cfg.get("out", "sheet"))
	for n in Array(cfg.get("anims", [])):
		_anims.append(str(n))
	print("[SHEET] start ", _out_name, " anims=", _anims)
	_load(0)


func _load(i: int) -> void:
	if i >= _anims.size():
		print("[SHEET] ALL DONE")
		get_tree().quit()
		return
	var data = load(_skull_dir)
	print("[SHEET] load -> ", str(data), " type=", typeof(data), " exists=", ResourceLoader.exists(_skull_dir))
	if data != null:
		print("[SHEET] loaded_flag=", data.call("is_skeleton_data_loaded"))
	if data == null or not data.call("is_skeleton_data_loaded"):
		print("[SHEET] FAIL load ", _skull_dir)
		get_tree().quit()
		return
	if _sprite:
		_sprite.queue_free()
	_sprite = ClassDB.instantiate("SpineSprite")
	add_child(_sprite)
	_sprite.set("skeleton_data_res", data)
	_sprite.scale = Vector2(1.0, 1.0)
	_sprite.position = Vector2(330, 480)
	_a_state = _sprite.call("get_animation_state")
	var n := str(_anims[i])
	var a = data.call("find_animation", n)
	if a == null:
		print("[SHEET] missing ", n)
		call_deferred("_load", i + 1)
		return
	_dur = a.call("get_duration")
	_a_state.call("set_animation", n, false, 0)
	_t = 0.0
	_shot_t = 0.0
	_shot_i = 0
	_loaded = true
	print("[SHEET] play ", n, " dur=", _dur)


func _process(delta: float) -> void:
	if not _loaded:
		return
	_t += delta
	_shot_t += delta
	if _shot_t >= INTERVAL:
		_shot_t = 0.0
		_shot_i += 1
		var img := get_viewport().get_texture().get_image()
		img.save_png(_dir_path + "%s_%s_%02d.png" % [_out_name, str(_anims[_idx]), _shot_i])
	if _t >= _dur + 0.1:
		_loaded = false
		_idx += 1
		call_deferred("_load", _idx)
