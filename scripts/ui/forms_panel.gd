extends CanvasLayer

## 化身谱：滚动角色总览 -> 单角色修炼页。
## 修炼页顶部始终是解锁（条件解锁或墨锭买断），下方为三分支各三阶的永久修炼。
## 已购末节点可点击全额退款；整角色重置返还该角色全部修炼投入。

const InkTex = preload("res://scripts/ui/ink_tex.gd")
const Skulls = preload("res://scripts/player/skulls.gd")
const SFX_CLICK := preload("res://audio/sfx/click.wav")

const INK := Color(0.05, 0.05, 0.05)
const PAPER := Color(0.949, 0.918, 0.847)
const DIM := Color(0.82, 0.79, 0.72)
const RED := Color(0.66, 0.2, 0.16)
const GOLD := Color(0.9, 0.75, 0.3)
const TIER_NAMES := ["初", "续", "极"]

var _form_id := ""
var _sfx: AudioStreamPlayer


func _ready() -> void:
	layer = 9
	_sfx = AudioStreamPlayer.new()
	_sfx.stream = SFX_CLICK
	add_child(_sfx)
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var win := TextureRect.new()
	win.texture = InkTex.load("res://art/ui/menu/window_large.png")
	win.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	win.stretch_mode = TextureRect.STRETCH_SCALE
	win.size = Vector2(1200, 640)
	win.position = Vector2(40, 40)
	win.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(win)
	if _form_id == "":
		_build_overview()
	else:
		_build_form_detail()


func _build_overview() -> void:
	_text(self, "化 身 谱", Vector2(250, 48), Vector2(780, 58), 44, PAPER)
	_text(self, "墨锭 %d" % Meta.ink, Vector2(250, 108), Vector2(780, 30), 23, RED)
	_text(self, "累计击杀 %d ｜ 通关 %d" % [Meta.kills, Meta.clears], Vector2(250, 140), Vector2(780, 26), 15, DIM)
	_button(self, "返  回", Vector2(70, 66), Vector2(140, 48), _close)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(80, 185)
	scroll.size = Vector2(1120, 405)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var list := VBoxContainer.new()
	list.custom_minimum_size = Vector2(1080, 0)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)
	for id in Skulls.ids():
		_form_row(list, str(id))
	_text(self, "点击角色进入专属修炼页 ｜ 鼠标滚轮浏览", Vector2(280, 615), Vector2(720, 28), 16, DIM)


func _form_row(parent: Control, id: String) -> void:
	var unlocked := Meta.is_unlocked(id)
	var profile: Dictionary = Skulls.get_profile(id)
	var b := TextureButton.new()
	b.texture_normal = InkTex.load("res://art/ui/menu/btn_normal.png")
	b.texture_pressed = InkTex.load("res://art/ui/menu/btn_clicked.png")
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.custom_minimum_size = Vector2(1040, 108)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if not unlocked:
		b.modulate = Color(1, 1, 1, 0.68)
	parent.add_child(b)
	_text(b, str(profile["label"]) if unlocked else "？？？", Vector2(22, 12), Vector2(170, 42), 28, PAPER, HORIZONTAL_ALIGNMENT_LEFT)
	_text(b, str(profile.get("name", "")) if unlocked else "尚未解锁", Vector2(22, 57), Vector2(190, 26), 16, DIM, HORIZONTAL_ALIGNMENT_LEFT)
	var status := "契合  " + Meta.mastery_text(id) if unlocked else Meta.unlock_hint(id).replace("\n", " ")
	_text(b, status, Vector2(245, 15), Vector2(410, 32), 18, RED if unlocked else DIM, HORIZONTAL_ALIGNMENT_LEFT)
	var progress := "永久修炼  %d / 9" % Meta.form_node_count(id) if unlocked else Meta.unlock_progress(id).replace(" · ", " ｜ ")
	_text(b, progress, Vector2(245, 57), Vector2(450, 28), 16, DIM, HORIZONTAL_ALIGNMENT_LEFT)
	_text(b, "进入修炼  →", Vector2(790, 35), Vector2(210, 34), 19, GOLD if unlocked else DIM)
	b.pressed.connect(func():
		_click()
		_form_id = id
		call_deferred("_refresh"))


func _build_form_detail() -> void:
	var profile: Dictionary = Skulls.get_profile(_form_id)
	var unlocked := Meta.is_unlocked(_form_id)
	_text(self, "%s · %s" % [profile["label"], profile.get("name", "")], Vector2(240, 48), Vector2(800, 54), 38, PAPER)
	_text(self, "墨锭 %d ｜ 契合 %s" % [Meta.ink, Meta.mastery_text(_form_id)], Vector2(240, 105), Vector2(800, 28), 19, RED)
	_button(self, "返回总览", Vector2(65, 62), Vector2(155, 46), _back)
	if Meta.form_spent(_form_id) > 0:
		_button(self, "重置修炼", Vector2(1020, 65), Vector2(165, 46), _reset_form)

	# 解锁永远位于修炼页最上方，未解锁时三分支只读。
	var plate := _plate(Vector2(80, 145), Vector2(1120, 100), unlocked)
	_text(plate, "化 身 解 锁", Vector2(22, 12), Vector2(220, 32), 21, GOLD if unlocked else PAPER, HORIZONTAL_ALIGNMENT_LEFT)
	if unlocked:
		_text(plate, "已解锁 ｜ 可继续修炼下方永久分支", Vector2(22, 52), Vector2(720, 28), 17, DIM, HORIZONTAL_ALIGNMENT_LEFT)
	else:
		_text(plate, Meta.unlock_hint(_form_id).replace("\n", " "), Vector2(22, 48), Vector2(640, 30), 17, DIM, HORIZONTAL_ALIGNMENT_LEFT)
		_text(plate, Meta.unlock_progress(_form_id).replace(" · ", " ｜ "), Vector2(660, 48), Vector2(250, 30), 16, RED)
		var key := "buyout_" + _form_id
		if Meta.INK_SHOP.has(key):
			var cost := Meta.shop_cost(key)
			var b := _button(plate, "%d 墨锭买断" % cost, Vector2(920, 27), Vector2(175, 48), _buyout)
			b.disabled = not Meta.can_buy(key)

	var paths: Array = []
	for id in Meta.FORM_NODES:
		var info: Dictionary = Meta.FORM_NODES[id]
		if str(info["form"]) == _form_id and not paths.has(str(info["path"])):
			paths.append(str(info["path"]))
	for col in paths.size():
		var x := 85.0 + col * 380.0
		_text(self, paths[col], Vector2(x, 264), Vector2(340, 34), 24, [RED, Color(0.42, 0.64, 0.66), GOLD][col])
		for tier in 3:
			var node_id := _node_id(_form_id, str(paths[col]), tier + 1)
			_node_card(node_id, Vector2(x, 310 + tier * 110), unlocked)
	_text(self, "分支可自由混点 ｜ 同分支顺序修炼 ｜ 点击最末已修节点全额退款", Vector2(210, 642), Vector2(860, 24), 14, DIM)


func _node_id(form_id: String, path: String, tier: int) -> String:
	for id in Meta.FORM_NODES:
		var info: Dictionary = Meta.FORM_NODES[id]
		if str(info["form"]) == form_id and str(info["path"]) == path and int(info["tier"]) == tier:
			return str(id)
	return ""


func _node_card(id: String, pos: Vector2, unlocked: bool) -> void:
	var info: Dictionary = Meta.FORM_NODES[id]
	var owned := Meta.has_form_node(id)
	var b := TextureButton.new()
	b.texture_normal = InkTex.load("res://art/ui/menu/btn_normal.png")
	b.texture_pressed = InkTex.load("res://art/ui/menu/btn_clicked.png")
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.position = pos
	b.size = Vector2(340, 100)
	b.disabled = not Meta.can_learn(id) and not Meta.can_refund(id)
	if b.disabled and not owned:
		b.modulate = Color(1, 1, 1, 0.55)
	add_child(b)
	_text(b, "%s · %s" % [info["path"], TIER_NAMES[int(info["tier"]) - 1]], Vector2(12, 5), Vector2(316, 25), 18, RED if owned else PAPER)
	_text(b, str(info["desc"]), Vector2(14, 31), Vector2(312, 40), 14, DIM)
	var status := ""
	if owned:
		status = "已修炼 · 点击退 %d 墨锭" % Meta.node_cost(id) if Meta.can_refund(id) else "已修炼（先退后继）"
	elif not unlocked:
		status = "先解锁化身"
	else:
		var req := str(info.get("req", ""))
		if req != "" and not Meta.has_form_node(req):
			status = "需先修炼上一阶"
		else:
			status = "%d 墨锭 · %s" % [Meta.node_cost(id), "点击修炼" if Meta.can_learn(id) else "墨锭不足"]
	_text(b, status, Vector2(12, 73), Vector2(316, 22), 14, GOLD if Meta.can_refund(id) or Meta.can_learn(id) else DIM)
	b.pressed.connect(func():
		_click()
		if owned:
			Meta.refund_node(id)
		else:
			Meta.learn_node(id)
		call_deferred("_refresh"))


func _buyout() -> void:
	Meta.buy("buyout_" + _form_id)
	call_deferred("_refresh")


func _reset_form() -> void:
	Meta.reset_form(_form_id)
	call_deferred("_refresh")


func _back() -> void:
	if _form_id != "":
		_form_id = ""
		_refresh()
	else:
		_close()


func _refresh() -> void:
	for c in get_children():
		if c == _sfx:
			continue
		remove_child(c)
		c.queue_free()
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_back()
		get_viewport().set_input_as_handled()


func _close() -> void:
	queue_free()


func _click() -> void:
	if is_instance_valid(_sfx):
		_sfx.play()


func _plate(pos: Vector2, size: Vector2, bright := false) -> TextureRect:
	var r := TextureRect.new()
	r.texture = InkTex.load("res://art/ui/menu/btn_normal.png")
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.position = pos
	r.size = size
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not bright:
		r.modulate = Color(1, 1, 1, 0.68)
	add_child(r)
	return r


func _button(parent: Node, text: String, pos: Vector2, size: Vector2, cb: Callable) -> TextureButton:
	var b := TextureButton.new()
	b.texture_normal = InkTex.load("res://art/ui/menu/btn_normal.png")
	b.texture_pressed = InkTex.load("res://art/ui/menu/btn_clicked.png")
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.position = pos
	b.size = size
	parent.add_child(b)
	_text(b, text, Vector2.ZERO, size, 18, INK)
	b.pressed.connect(func():
		_click()
		cb.call())
	return b


func _text(parent: Node, text: String, pos: Vector2, size: Vector2, font_size: int, color: Color, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = size
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l
