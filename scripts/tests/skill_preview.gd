extends Node2D

## 逐个播放 skill01-05，每个动画每隔 ~0.15s 截一帧，看技能视觉表现。
## 截图到 tests/out/skill_<名>_<序号>.png

const OUT_DIR := "res://tests/out/"
const SKILLS := ["skill01", "skill05"] # 只看有失踪段的大招
const SHOT_INTERVAL := 0.1
const PREVIEW_SCALE := 0.15 # 缩小显示，让 root 位移全程留在画面里

var _sprite: Node2D
var _anim_state
var _idx := 0
var _elapsed := 0.0
var _shot_elapsed := 0.0
var _shot_idx := 0
var _dur := 0.0

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	get_window().size = Vector2i(1280, 720)
	# 地面参考线
	var line := ColorRect.new()
	line.position = Vector2(0, 620)
	line.size = Vector2(1280, 2)
	line.color = Color.RED
	add_child(line)

	var data = load("res://art/characters/player/c021_data.tres")
	if data == null or not data.call("is_skeleton_data_loaded"):
		print("[S] FAIL load")
		get_tree().quit()
		return
	_sprite = ClassDB.instantiate("SpineSprite")
	add_child(_sprite)
	_sprite.set("skeleton_data_res", data)
	_sprite.scale = Vector2(PREVIEW_SCALE, PREVIEW_SCALE)
	_sprite.position = Vector2(300, 500)
	_anim_state = _sprite.call("get_animation_state")
	_start(_idx)

func _start(i: int) -> void:
	var n: String = SKILLS[i]
	var a = _sprite.get("skeleton_data_res").call("find_animation", n)
	_dur = a.call("get_duration")
	_elapsed = 0.0
	_shot_elapsed = 0.0
	_shot_idx = 0
	_anim_state.call("set_animation", n, false, 0)
	print("[S] play ", n, " dur=", _dur)

func _process(delta: float) -> void:
	if _idx >= SKILLS.size():
		return
	_elapsed += delta
	_shot_elapsed += delta
	if _shot_elapsed >= SHOT_INTERVAL:
		_shot_elapsed = 0.0
		_shot_idx += 1
		_shot("zoom_%s_%02d" % [SKILLS[_idx], _shot_idx])
	if _elapsed >= _dur + 0.1:
		_idx += 1
		if _idx >= SKILLS.size():
			print("[S] ALL DONE")
			get_tree().quit()
		else:
			_start(_idx)

func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img = get_viewport().get_texture().get_image()
	img.save_png(OUT_DIR + "skill_" + tag + ".png")
