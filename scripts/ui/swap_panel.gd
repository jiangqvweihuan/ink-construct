extends CanvasLayer

## 化身选择面板：按 Q 呼出，时间暂停，从全部形态里挑一个化过去（花墨骨）。
## 再按 Q / Esc 取消，不扣墨骨。按钮灰掉 = 当前形态或墨骨不够。

signal chosen(id: String)

const InkTex = preload("res://scripts/ui/ink_tex.gd")
const Skulls = preload("res://scripts/player/skulls.gd")

const SFX_SWAP := preload("res://audio/sfx/swap_draw.wav")
const SFX_GOLD := preload("res://audio/sfx/gold.wav")
const SFX_CLICK := preload("res://audio/sfx/click.wav")

const INK := Color(0.05, 0.05, 0.05)
const PAPER := Color(0.949, 0.918, 0.847)
const DIM := Color(0.82, 0.79, 0.72)
const RED := Color(0.66, 0.2, 0.16)

var _player


## 必须在 add_child 之前调用：_ready 里就要读玩家当前形态与费用
func setup(p) -> void:
	_player = p


func _ready() -> void:
	layer = 9
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var win := TextureRect.new()
	win.texture = InkTex.load("res://art/ui/menu/window_large.png")
	win.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	win.stretch_mode = TextureRect.STRETCH_SCALE
	win.size = Vector2(1100, 360)
	win.position = Vector2(90, 180)
	win.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(win)

	_make_label("化  身", 210, 34, PAPER)
	_make_label("选择化成的形态（Q / Esc 取消）  墨骨 %d" % Score.bones, 262, 18, DIM)

	var ids := Skulls.ids()
	var cost: int = _player.swap_cost if is_instance_valid(_player) else 8
	for i in ids.size():
		var id := str(ids[i])
		_make_card(id, i, cost)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("swap_skull") or event.is_action_pressed("ui_cancel"):
		_cancel()
		get_viewport().set_input_as_handled()


## 选中一个形态：扣墨骨、换头、关面板。未解锁 / 墨骨不够 / 已是该形态则无反应
func select(id: String) -> void:
	if not is_instance_valid(_player):
		_cancel()
		return
	if id == _player.skull_id or not Meta.is_unlocked(id):
		return
	var cost: int = 0 if bool(Meta.mods(id)["free"]) else int(_player.swap_cost) # 契合 Lv3 免费化身
	if not Score.spend_bones(cost):
		return
	# 抽签音效 + 扣费音效（抽签先响，扣费略延迟）
	var s := AudioStreamPlayer.new()
	add_child(s)
	s.stream = SFX_SWAP
	s.play()
	_player.swap_skull(id)
	chosen.emit(id)
	await get_tree().create_timer(0.18).timeout
	var s2 := AudioStreamPlayer.new()
	add_child(s2)
	s2.stream = SFX_GOLD
	s2.play()
	_close()


func _cancel() -> void:
	_close()


func _close() -> void:
	get_tree().paused = false
	queue_free()


func _make_label(text: String, y: float, font_size: int, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.size = Vector2(1100, 44)
	l.position = Vector2(90, y)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)


func _make_card(id: String, i: int, cost: int) -> void:
	var is_current: bool = is_instance_valid(_player) and id == _player.skull_id
	var unlocked := Meta.is_unlocked(id)
	var lv := Meta.mastery_level(id)
	var free := unlocked and bool(Meta.mods(id)["free"]) # 契合 Lv3：化身免费
	var price := 0 if free else cost
	var affordable: bool = Score.bones >= price

	var b := TextureButton.new()
	b.texture_normal = InkTex.load("res://art/ui/menu/btn_normal.png")
	b.texture_pressed = InkTex.load("res://art/ui/menu/btn_clicked.png")
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.size = Vector2(190, 150)
	b.position = Vector2(140 + i * 205, 310)
	if is_current or not unlocked or not affordable:
		b.modulate = Color(1, 1, 1, 0.4)
		b.disabled = true
	else:
		b.pressed.connect(func():
			var s := AudioStreamPlayer.new()
			add_child(s)
			s.stream = SFX_CLICK
			s.play()
			select(id))

	var name_l := Label.new()
	name_l.text = str(Skulls.get_profile(id)["label"]) if unlocked else "？？？"
	name_l.size = Vector2(190, 40)
	name_l.position = Vector2(0, 18)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.add_theme_color_override("font_color", PAPER)
	name_l.add_theme_font_size_override("font_size", 28)
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(name_l)

	# 真实姓名（未解锁不剧透）
	if unlocked:
		var real := Label.new()
		real.text = str(Skulls.get_profile(id).get("name", ""))
		real.size = Vector2(190, 26)
		real.position = Vector2(0, 60)
		real.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		real.add_theme_color_override("font_color", DIM)
		real.add_theme_font_size_override("font_size", 16)
		real.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(real)

	var sub := Label.new()
	if is_current:
		sub.text = "当前形态"
	elif not unlocked:
		sub.text = Meta.unlock_hint(id)
	elif free:
		sub.text = "契合Lv%d · 免费" % lv
	else:
		sub.text = "契合Lv%d · %d 墨骨" % [lv, price]
	sub.size = Vector2(190, 30)
	sub.position = Vector2(0, 92)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", DIM if (is_current or not unlocked) else RED)
	sub.add_theme_font_size_override("font_size", 18)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(sub)

	add_child(b)
