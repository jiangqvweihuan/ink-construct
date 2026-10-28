extends Node2D

## 动画查看器：一个场景看遍 art/characters 下所有骨架的所有动画，不用再逐个开编辑器。
## 操作：← / → 切换骨架，↑ / ↓ 切换动画，空格 重播，L 开关循环。

const ROOT := "res://art/characters"
const ORIGIN := Vector2(640.0, 630.0)
const VIEW_SCALE := 0.42

var _sets: Array = [] # [{path, data, anims:[{name, dur}]}]
var _si := 0
var _ai := 0
var _loop := true
var _sprite
var _state
var _info: Label
var _hint: Label


func _ready() -> void:
	var files := _find_data_files(ROOT)
	files.sort()
	for f in files:
		var data = load(f)
		if data == null or not data.call("is_skeleton_data_loaded"):
			print("[AV] 跳过（加载失败）: ", f)
			continue
		var anims: Array = []
		for a in data.call("get_animations"):
			anims.append({"name": str(a.call("get_name")), "dur": float(a.call("get_duration"))})
		_sets.append({"path": f, "data": data, "anims": anims})
	print("[AV] 骨架 %d 个" % _sets.size())

	var bg := ColorRect.new()
	bg.color = Color(0.949, 0.918, 0.847)
	bg.size = Vector2(1280, 720)
	bg.z_index = -10
	add_child(bg)

	_info = Label.new()
	_info.position = Vector2(24, 18)
	_info.add_theme_font_size_override("font_size", 20)
	add_child(_info)

	_hint = Label.new()
	_hint.position = Vector2(24, 680)
	_hint.add_theme_font_size_override("font_size", 16)
	_hint.text = "← → 切骨架    ↑ ↓ 切动画    空格 重播    L 循环"
	add_child(_hint)

	_show(0, 0)
	# 命令行加 `-- --shot` 时自动截一张图并退出，方便回归验证本工具能正常渲染
	if "--shot" in OS.get_cmdline_user_args():
		await get_tree().create_timer(1.0).timeout
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/out"))
		var err := get_viewport().get_texture().get_image().save_png("res://tests/out/anim_viewer.png")
		print("[AV] shot err=", err)
		get_tree().quit()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_right"):
		_show(_si + 1, 0)
	elif e.is_action_pressed("ui_left"):
		_show(_si - 1, 0)
	elif e.is_action_pressed("ui_down"):
		_show(_si, _ai + 1)
	elif e.is_action_pressed("ui_up"):
		_show(_si, _ai - 1)
	elif e.is_action_pressed("ui_accept"):
		_play_current()
	elif e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_L:
		_loop = not _loop
		_play_current()
		_update_info()


func _show(si: int, ai: int) -> void:
	if _sets.is_empty():
		return
	_si = wrapi(si, 0, _sets.size())
	var set: Dictionary = _sets[_si]
	var anims: Array = set["anims"]
	if anims.is_empty():
		_update_info()
		return
	_ai = wrapi(ai, 0, anims.size())
	if _sprite != null and is_instance_valid(_sprite):
		_sprite.queue_free()
	_sprite = ClassDB.instantiate("SpineSprite")
	add_child(_sprite)
	_sprite.set("skeleton_data_res", set["data"])
	_sprite.position = ORIGIN
	_sprite.scale = Vector2(VIEW_SCALE, VIEW_SCALE)
	_state = _sprite.call("get_animation_state")
	_play_current()
	_update_info()


func _play_current() -> void:
	if _state == null or _sets.is_empty():
		return
	var anims: Array = _sets[_si]["anims"]
	if anims.is_empty():
		return
	_state.call("set_animation", str(anims[_ai]["name"]), _loop, 0)


func _update_info() -> void:
	if _sets.is_empty():
		_info.text = "没找到任何骨架"
		return
	var set: Dictionary = _sets[_si]
	var anims: Array = set["anims"]
	var path := str(set["path"])
	var lines: Array[String] = []
	lines.append("骨架 %d/%d   %s" % [_si + 1, _sets.size(), path.trim_prefix("res://art/characters/")])
	if anims.is_empty():
		lines.append("（该骨架没有动画）")
	else:
		var a: Dictionary = anims[_ai]
		lines.append("动画 %d/%d   %s   %.3fs   %s" % [
			_ai + 1, anims.size(), str(a["name"]), float(a["dur"]), "循环" if _loop else "单次"])
	_info.text = "\n".join(lines)


func _find_data_files(dir: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for sub in d.get_directories():
		out += _find_data_files(dir.path_join(sub))
	for f in d.get_files():
		if f.ends_with("_data.tres"):
			out.append(dir.path_join(f))
	return out
