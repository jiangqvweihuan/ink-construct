extends CanvasLayer

const InkTex = preload("res://scripts/ui/ink_tex.gd")
const Skulls = preload("res://scripts/player/skulls.gd")
const SFX_SETTLE := preload("res://audio/sfx/settle.wav")
const SFX_WIN := preload("res://audio/sfx/win.wav")
const SFX_LOSE := preload("res://audio/sfx/lose.wav")
const SFX_CLICK := preload("res://audio/sfx/click.wav")

## 结算面板：通关 / 阵亡共用。展示本局收获（契合增量/新解锁/墨锭沉淀），再来一局 / 回主菜单。

const INK := Color(0.05, 0.05, 0.05)
const PAPER := Color(0.949, 0.918, 0.847)
const DIM := Color(0.82, 0.79, 0.72)
const RED := Color(0.66, 0.2, 0.16)

var _title := "结  算"
var _cleared := false


func setup(title_text: String, cleared := false) -> void:
	_title = title_text
	_cleared = cleared


func _ready() -> void:
	layer = 8
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true # 通关/阵亡后时间停住，战场不再动弹
	# 结算音效：面板展开 + 胜负判定
	var sfx := AudioStreamPlayer.new()
	add_child(sfx)
	sfx.stream = SFX_SETTLE
	sfx.play()
	await get_tree().create_timer(0.35).timeout
	sfx.stream = SFX_WIN if _cleared else SFX_LOSE
	sfx.play()

	# 本局收获：对比 Run 开局时的 Meta 快照；剩余墨骨沉淀为局外货币墨锭
	var diff: Dictionary = {"mastery": {}, "unlocks": []}
	if not Run.meta_snapshot.is_empty():
		diff = Meta.diff_since(Run.meta_snapshot)
	var ink_gain := Meta.deposit_ink(Score.bones, _cleared)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var win := TextureRect.new()
	win.texture = InkTex.load("res://art/ui/menu/window_large.png")
	win.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	win.stretch_mode = TextureRect.STRETCH_SCALE
	win.size = Vector2(560, 520)
	win.position = Vector2(360, 110)
	win.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(win)

	var title := Label.new()
	title.text = _title
	title.size = Vector2(560, 70)
	title.position = Vector2(360, 150)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", PAPER)
	title.add_theme_font_size_override("font_size", 46)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)

	# 收获明细：契合增量 / 新解锁 / 墨锭沉淀，逐行居中列出
	var lines: Array = []
	for id in diff["mastery"]:
		lines.append({
			"text": "%s  契合 +%d（%s）" % [str(Skulls.get_profile(id)["label"]), int(diff["mastery"][id]), Meta.mastery_text(id)],
			"color": PAPER,
		})
	for id in diff["unlocks"]:
		lines.append({"text": "新化身解锁：%s" % str(Skulls.get_profile(id)["label"]), "color": RED})
	if ink_gain > 0:
		lines.append({"text": "墨锭 +%d（总 %d）" % [ink_gain, Meta.ink], "color": PAPER})
	if lines.is_empty():
		lines.append({"text": "本局无收获", "color": DIM})
	for i in mini(lines.size(), 6):
		var l := Label.new()
		l.text = str(lines[i]["text"])
		l.size = Vector2(560, 32)
		l.position = Vector2(360, 232 + i * 34)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_color_override("font_color", lines[i]["color"])
		l.add_theme_font_size_override("font_size", 22)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(l)

	_make_button("再来一局", 490, _restart)
	_make_button("回主菜单", 565, _to_menu)


func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _make_button(text: String, y: float, cb: Callable) -> void:
	var b := TextureButton.new()
	b.texture_normal = InkTex.load("res://art/ui/menu/btn_normal.png")
	b.texture_pressed = InkTex.load("res://art/ui/menu/btn_clicked.png")
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.size = Vector2(220, 56)
	b.position = Vector2(530, y) # 相对 560 宽窗口居中
	var l := Label.new()
	l.text = text
	l.size = b.size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", INK)
	l.add_theme_font_size_override("font_size", 22)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(l)
	b.pressed.connect(func():
		var s := AudioStreamPlayer.new()
		add_child(s)
		s.stream = SFX_CLICK
		s.play()
		cb.call())
	add_child(b)
