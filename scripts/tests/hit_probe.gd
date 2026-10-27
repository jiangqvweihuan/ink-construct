extends Node2D

## 高精度战斗动画探针：0.05s 间隔逐帧截图

const OUT_DIR := "res://tests/out2/"

# [角色, 骨架路径, 动画名, 时长]
const ANIMS := [
	["c016", "res://art/characters/enemies/c016/c016_data.tres", "skill01", 2.167],
	["c016", "res://art/characters/enemies/c016/c016_data.tres", "skill02", 1.750],
	["c016", "res://art/characters/enemies/c016/c016_data.tres", "skill03", 1.767],
	["c016", "res://art/characters/enemies/c016/c016_data.tres", "skill04", 1.283],
	["c016", "res://art/characters/enemies/c016/c016_data.tres", "skill05", 2.083],
	["c021", "res://art/characters/player/c021_data.tres", "skill01", 1.567],
	["c021", "res://art/characters/player/c021_data.tres", "skill03", 2.433],
	["c021", "res://art/characters/player/c021_data.tres", "skill04", 3.400],
	["c021", "res://art/characters/player/c021_data.tres", "atk01", 0.483],
	["c021", "res://art/characters/player/c021_data.tres", "atk02", 0.433],
	["c021", "res://art/characters/player/c021_data.tres", "atk03", 1.150],
]

const INTERVAL := 0.05

var _idx = 0
var _t = 0.0
var _shot_t = 0.0
var _shot_i = 0
var _dur = 0.0
var _sprite = null
var _a_state = null
var _char = ""
var _anim_name = ""
var _loaded = false
var _dir_path = ""

func _ready() -> void:
	_dir_path = ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(_dir_path)
	get_window().size = Vector2i(800, 600)
	_load(_idx)

func _load(i: int) -> void:
	if i >= ANIMS.size():
		print("[X] ALL DONE")
		get_tree().quit()
		return
	var e = ANIMS[i]
	var data = load(e[1])
	if _sprite:
		_sprite.queue_free()
	_sprite = ClassDB.instantiate("SpineSprite")
	add_child(_sprite)
	_sprite.set("skeleton_data_res", data)
	_sprite.scale = Vector2(0.35, 0.35)
	_sprite.position = Vector2(400, 450)
	_a_state = _sprite.call("get_animation_state")
	_a_state.call("set_animation", e[2], false, 0)
	_char = e[0]
	_anim_name = e[2]
	_dur = e[3]
	_t = 0.0
	_shot_t = 0.0
	_shot_i = 0
	_loaded = true
	print("[X] play %s / %s  dur=%.3fs" % [_char, _anim_name, _dur])

func _process(delta: float) -> void:
	if not _loaded:
		return
	_t += delta
	_shot_t += delta
	if _shot_t >= INTERVAL:
		_shot_t = 0.0
		_shot_i += 1
		_shot_now()
	if _t >= _dur + 0.25:
		_loaded = false
		_idx += 1
		call_deferred("_load", _idx)

func _shot_now() -> void:
	var img = get_viewport().get_texture().get_image()
	img.save_png(_dir_path + "%s_%s_%04d_t%.3f.png" % [_char, _anim_name, _shot_i, _t])
