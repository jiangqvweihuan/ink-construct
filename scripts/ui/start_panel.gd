extends CanvasLayer

## 开始游戏 · 行旅卷：择路（模式）→ 问境（五档难度）→ 化身（选人、预览、补给、启程）。
## 角色卡只负责选中，右侧显示真实 Spine 待机；最后点「启程」才开新一局。

const InkTex = preload("res://scripts/ui/ink_tex.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")
const Skulls = preload("res://scripts/player/skulls.gd")
const PvpPool = preload("res://scripts/pvp/pvp_pool.gd")
const SFX_CLICK := preload("res://audio/sfx/click.wav")
const SFX_RUN_EMBARK := preload("res://audio/sfx/run_embark.wav")
const SFX_BACK := preload("res://audio/sfx/ui_back.wav")

const PAPER := Color(0.949, 0.918, 0.847)
const DIM := Color(0.82, 0.79, 0.72)
const RED := Color(0.66, 0.2, 0.16)
const GOLD := Color(0.9, 0.75, 0.3)

const MODES := {
	"adventure": {"label": "冒 险 模 式", "desc": "三关问道 · 讨伐守关者"},
	"endless": {"label": "无 尽 模 式", "desc": "层层深入 · 问道无止"},
}

var _mode := ""
var _difficulty := 1 # 默认落笔，保持此前的战斗体验
var _char := ""
var _char2 := "" # 本机双人：P2 单独选择的化身
var _pick_slot := 0 # 化身页当前正在为谁选人（0 = P1 / 1 = P2）
var _step := 0 # 0 择路 / 1 问境 / 2 化身
var _supply := ""
## 本机双人：由启动的模式选择界面置 true，启程时把双人标记写进 Run
var local_coop := false
## 本机对战：复用同一套双人槽位选角，但启程后进入 PVP 竞技场
var pvp_local := false
var _sfx: AudioStreamPlayer
var _start_button: TextureButton
var _starting := false
var _portrait: TextureRect = null


func _ready() -> void:
	layer = 10
	_supply = Meta.selected_supply
	# 本机对战跳过择路/问境，直接进入双人化身页
	if pvp_local:
		_mode = Run.MODE_PVP
		_step = 2
		_ensure_char_for(0)
		_ensure_char_for(1)
	_sfx = AudioStreamPlayer.new()
	_sfx.bus = "SFX"
	_sfx.stream = SFX_CLICK
	add_child(_sfx)
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	_play_sfx(SFX_BACK)
	if pvp_local:
		queue_free()
		return
	if _step > 0:
		_step -= 1
		_refresh()
		return
	queue_free()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	UiKit.fit_layer(self, [dim])

	var win := TextureRect.new()
	win.texture = InkTex.load("res://art/ui/menu/window_large.png")
	win.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	win.stretch_mode = TextureRect.STRETCH_SCALE
	win.size = Vector2(1160, 600)
	win.position = Vector2(60, 60)
	win.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(win)

	var titles := ["择  路", "问  境", "化  身"]
	var subtitles := ["", "只改敌众与敌锋", "选化身与开局补给"]
	if pvp_local:
		subtitles[2] = "双方各选一名化身 · 仅限已解锁"
	_label("行 旅 卷 · 本 机 对 战" if pvp_local else ("行 旅 卷 · 本 机 双 人" if local_coop else "行 旅 卷"), 72, 16, RED)
	if _two_slots():
		_text("P2：方向键 + 小键盘 1~8", Vector2(760, 72), Vector2(460, 26), 13, GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	_label(titles[_step], 98, 38, PAPER)
	_label(subtitles[_step], 146, 16, DIM)
	var steps := ["壹 · 择路", "贰 · 问境", "叁 · 化身"]
	for i in 3:
		_text(steps[i], Vector2(374 + i * 180, 180), Vector2(170, 26), 15, PAPER if i == _step else DIM)
	_rule(Vector2(180, 213), Vector2(920, 1))

	match _step:
		0:
			var modes := MODES.keys()
			for i in modes.size():
				_mode_card(str(modes[i]), i)
			_button("返  回", 530, 585, _close, SFX_BACK)
		1:
			for i in Run.DIFFICULTIES.size():
				_difficulty_card(i)
			_button("上 一 步", 100, 585, _back, SFX_BACK)
		2:
			if _two_slots():
				_slot_tabs()
			_character_step()
			_button("返  回" if pvp_local else "上 一 步", 100, 590, _back, SFX_BACK)
			_start_button = _button("启  程", 930, 590, _start_run, null)


func _refresh() -> void:
	for c in get_children():
		if c == _sfx:
			continue
		remove_child(c)
		c.queue_free()
	_portrait = null
	_start_button = null
	_build()


func _back() -> void:
	if pvp_local:
		_close()
		return
	_step = maxi(0, _step - 1)
	_refresh()


## 是否有两个本地槽位：本机双人 / 本机对战
func _two_slots() -> bool:
	return local_coop or pvp_local


func _close() -> void:
	queue_free()


func _pick_mode(id: String) -> void:
	_click_sfx()
	_mode = id
	_step = 1
	_refresh()


func _pick_difficulty(index: int) -> void:
	_click_sfx()
	_difficulty = index
	_step = 2
	_ensure_char()
	_refresh()


func _pick_char(id: String) -> void:
	_set_char(0, id)


## 为指定槽位选人：P1/P2 各存一份，互不覆盖
func _set_char(slot: int, id: String) -> void:
	if not Meta.is_unlocked(id):
		return
	_click_sfx()
	if slot == 0:
		_char = id
	else:
		_char2 = id
	_refresh()


## 化身页的 P1/P2 切换
func _switch_pick(slot: int) -> void:
	if slot == _pick_slot:
		return
	_click_sfx()
	_pick_slot = 1 if slot == 1 else 0
	_ensure_char_for(_pick_slot)
	_refresh()


func _slot_char(slot: int) -> String:
	return _char if slot == 0 else _char2


func _ensure_char() -> void:
	_ensure_char_for(0)


## 某槽位没有可用化身时补一个默认值；P2 优先选与 P1 不同的角色，便于一眼看出双人差异。
func _ensure_char_for(slot: int) -> void:
	var cur := _slot_char(slot)
	if cur != "" and Meta.is_unlocked(cur):
		return
	var pick := ""
	var fallback := ""
	# 本机对战：两个槽位都从同一套本机已解锁池里取人
	var ids: Array = PvpPool.unlocked_ids() if pvp_local else Skulls.ids()
	for id in ids:
		if not Meta.is_unlocked(str(id)):
			continue
		if fallback == "":
			fallback = str(id)
		if slot == 1 and str(id) == _char:
			continue
		pick = str(id)
		break
	if pick == "":
		pick = fallback
	if slot == 0:
		_char = pick
	else:
		_char2 = pick


func _start_run() -> void:
	if _starting:
		return
	if _mode == "" or _char == "" or not Meta.is_unlocked(_char):
		return
	if _two_slots():
		_ensure_char_for(1)
		if _char2 == "" or not Meta.is_unlocked(_char2):
			return
	if pvp_local and not (PvpPool.can_pick(_char) and PvpPool.can_pick(_char2)):
		return
	_starting = true
	if is_instance_valid(_start_button):
		_start_button.disabled = true
	_play_sfx(SFX_RUN_EMBARK)
	if pvp_local:
		# 本机对战：两名玩家共用本机已解锁角色池，选角在面板里就已按 Meta 过滤
		Run.start_pvp({0: _char, 1: _char2}, true)
		await LoadVeil.transition_to("res://scenes/pvp/pvp_arena.tscn", "正在入阵")
		return
	Meta.select_supply(_supply)
	Run.start(_mode, _char, _difficulty, local_coop, _char2 if local_coop else "")
	await LoadVeil.transition_to("res://scenes/world/room_01.tscn", "正在入卷")


func _play_sfx(stream: AudioStream) -> void:
	var s := AudioStreamPlayer.new()
	s.bus = "SFX"
	get_tree().root.add_child(s)
	s.stream = stream
	s.play()
	s.finished.connect(s.queue_free, CONNECT_ONE_SHOT)


func _click_sfx() -> void:
	if is_instance_valid(_sfx):
		_sfx.play()


func _label(text: String, y: float, font_size: int, color: Color) -> void:
	_text(text, Vector2(60, y), Vector2(1160, 46), font_size, color)


func _text(text: String, pos: Vector2, size: Vector2, font_size: int, color: Color, alignment := HORIZONTAL_ALIGNMENT_CENTER) -> void:
	UiKit.label(self, text, pos, size, font_size, color, alignment, true)


func _card_text(card: Control, text: String, pos: Vector2, size: Vector2, font_size: int, color: Color) -> void:
	UiKit.label(card, text, pos, size, font_size, color, HORIZONTAL_ALIGNMENT_CENTER, true)


func _rule(pos: Vector2, size: Vector2) -> void:
	UiKit.rule(self, pos, size, Color(0.66, 0.2, 0.16, 0.6))


func _texture_card(pos: Vector2, size: Vector2, selected := false, parent: Node = null) -> TextureButton:
	var b := TextureButton.new()
	b.texture_normal = InkTex.load("res://art/ui/menu/btn_normal.png")
	b.texture_pressed = InkTex.load("res://art/ui/menu/btn_clicked.png")
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.position = pos
	b.size = size
	b.modulate = Color(1.16, 1.09, 0.88) if selected else Color.WHITE
	if parent == null:
		parent = self
	parent.add_child(b)
	return b


func _mode_card(id: String, i: int) -> void:
	var info: Dictionary = MODES[id]
	var b := _texture_card(Vector2(260 + i * 400, 252), Vector2(360, 270))
	_card_text(b, str(info["label"]), Vector2(0, 74), Vector2(360, 48), 30, PAPER)
	_card_text(b, str(info["desc"]), Vector2(20, 146), Vector2(320, 34), 17, DIM)
	b.pressed.connect(_pick_mode.bind(id))


func _difficulty_card(index: int) -> void:
	var info: Dictionary = Run.DIFFICULTIES[index]
	var b := _texture_card(Vector2(110 + index * 214, 246), Vector2(194, 278), index == _difficulty)
	_card_text(b, str(info["seal"]), Vector2(0, 10), Vector2(194, 24), 14, GOLD if index == 4 else RED)
	_card_text(b, str(info["label"]), Vector2(0, 44), Vector2(194, 46), 30, PAPER)
	_card_text(b, str(info["desc"]), Vector2(12, 108), Vector2(170, 52), 15, DIM)
	_card_text(b, "敌众 %d%%" % int(round(float(info["count"]) * 100.0)), Vector2(0, 180), Vector2(194, 26), 15, PAPER)
	var attack := int(info["attack"])
	var attack_text := "敌锋 原值" if attack == 0 else "敌锋 %+d" % attack
	_card_text(b, attack_text, Vector2(0, 208), Vector2(194, 26), 15, PAPER)
	var foot := "双守关者 · 连战" if index == 4 and _mode == Run.MODE_ADVENTURE else ("仅此初始 · 逐层成长" if _mode == Run.MODE_ENDLESS else "单守关者")
	_card_text(b, foot, Vector2(6, 242), Vector2(182, 24), 12, RED if index == 4 else DIM)
	b.pressed.connect(_pick_difficulty.bind(index))


## 本机双人：化身页顶部的 P1 / P2 切换，两个槽位各选各的
func _slot_tabs() -> void:
	_ensure_char_for(0)
	_ensure_char_for(1)
	for slot in 2:
		var active := slot == _pick_slot
		var b := _texture_card(Vector2(82 + slot * 148, 172), Vector2(138, 34), active)
		var who := "P1" if slot == 0 else "P2"
		var pick := _slot_char(slot)
		var name := ""
		if pick != "":
			name = str(Skulls.get_profile(pick).get("label", ""))
		_card_text(b, "%s · %s" % [who, name] if name != "" else "%s · 化身" % who,
			Vector2.ZERO, b.size, 14, PAPER if active else DIM)
		b.pressed.connect(_switch_pick.bind(slot))


func _character_step() -> void:
	_ensure_char_for(_pick_slot)
	if _two_slots():
		_ensure_char_for(0)
		_ensure_char_for(1)
	var ids := Skulls.ids()
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(90, 242)
	scroll.size = Vector2(674, 254)
	scroll.clip_contents = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	var h_scroll := scroll.get_h_scroll_bar()
	h_scroll.custom_minimum_size = Vector2(0, 12)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.05, 0.05, 0.05, 0.55)
	track.set_corner_radius_all(4)
	h_scroll.add_theme_stylebox_override("scroll", track)
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = RED
	grabber.set_corner_radius_all(4)
	h_scroll.add_theme_stylebox_override("grabber", grabber)
	h_scroll.add_theme_stylebox_override("grabber_highlight", grabber)
	h_scroll.add_theme_stylebox_override("grabber_pressed", grabber)
	var cards := Control.new()
	cards.custom_minimum_size = Vector2(ids.size() * 134 - 12, 240)
	cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(cards)
	for i in ids.size():
		_char_card(str(ids[i]), i, cards)
	_rule(Vector2(782, 246), Vector2(1, 270))
	var cur := _slot_char(_pick_slot)
	if cur != "":
		var profile: Dictionary = Skulls.get_profile(cur)
		var head := str(profile["label"])
		if _two_slots():
			head = "%s · %s" % ["P1" if _pick_slot == 0 else "P2", head]
		_text(head, Vector2(812, 240), Vector2(300, 38), 26, GOLD if bool(profile.get("hero", false)) else PAPER, HORIZONTAL_ALIGNMENT_LEFT)
		_text(str(profile.get("name", "")), Vector2(812, 278), Vector2(300, 26), 15, DIM, HORIZONTAL_ALIGNMENT_LEFT)
		var portrait_path := str(profile.get("portrait", ""))
		if portrait_path != "" and ResourceLoader.exists(portrait_path):
			_make_portrait(portrait_path)
			_text("角 色 原 画", Vector2(800, 540), Vector2(360, 22), 12, RED)
		else:
			_text("动 作 预 览", Vector2(800, 326), Vector2(360, 24), 13, RED)
			_rule(Vector2(850, 522), Vector2(260, 2))
			_make_preview()
	if not pvp_local:
		_supply_selector()


func _char_card(id: String, i: int, parent: Control) -> void:
	var unlocked := Meta.is_unlocked(id)
	var profile: Dictionary = Skulls.get_profile(id)
	var card: Control
	if unlocked:
		var b := _texture_card(Vector2(i * 134, 0), Vector2(122, 240), id == _slot_char(_pick_slot), parent)
		b.pressed.connect(_set_char.bind(_pick_slot, id))
		card = b
	else:
		var t := TextureRect.new()
		t.texture = InkTex.load("res://art/ui/menu/btn_normal.png")
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_SCALE
		t.modulate = Color(1, 1, 1, 0.48)
		t.position = Vector2(i * 134, 0)
		t.size = Vector2(122, 240)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(t)
		card = t
	if unlocked:
		if bool(profile.get("hero", false)):
			_card_text(card, "英 雄", Vector2(0, 5), Vector2(122, 18), 11, GOLD)
		_card_text(card, str(profile["label"]), Vector2(2, 32), Vector2(118, 38), 23, PAPER)
		_card_text(card, str(profile.get("name", "")), Vector2(4, 76), Vector2(114, 42), 13, DIM)
		_card_text(card, "契合", Vector2(0, 136), Vector2(122, 22), 12, DIM)
		_card_text(card, Meta.mastery_text(id), Vector2(2, 160), Vector2(118, 24), 13, RED)
		var mark := "选 择"
		var mark_color := DIM
		if _two_slots():
			# 双人：卡片上直接标出被 P1 / P2 选中的情况，切页也不会看漏
			var tags: Array = []
			if id == _char:
				tags.append("P1")
			if id == _char2:
				tags.append("P2")
			if not tags.is_empty():
				mark = "已 选 " + "/".join(tags)
				mark_color = RED
		elif id == _char:
			mark = "已 选"
			mark_color = RED
		_card_text(card, mark, Vector2(0, 202), Vector2(122, 24), 12 if _two_slots() else 13, mark_color)
	else:
		_card_text(card, "？？？", Vector2(0, 34), Vector2(122, 38), 22, PAPER)
		_card_text(card, Meta.unlock_hint(id), Vector2(4, 94), Vector2(114, 76), 12, DIM)
		_card_text(card, "尚未解锁", Vector2(0, 202), Vector2(122, 24), 12, RED)


func _make_portrait(path: String) -> void:
	_portrait = TextureRect.new()
	_portrait.texture = load(path)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.position = Vector2(792, 300)
	_portrait.size = Vector2(368, 238)
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_portrait)


func _make_preview() -> void:
	var profile: Dictionary = Skulls.get_profile(_slot_char(_pick_slot))
	var data = load(str(profile["data"]))
	if data == null or not data.call("is_skeleton_data_loaded"):
		return
	var sprite = ClassDB.instantiate("SpineSprite")
	add_child(sprite)
	sprite.set("skeleton_data_res", data)
	data.call("set_default_mix", 0.2)
	var sc := float(profile["scale"]) * 1.9
	sprite.scale = Vector2(sc, sc)
	sprite.position = Vector2(980, 520)
	var st = sprite.call("get_animation_state")
	st.call("set_animation", str(profile["anim"]["idle"]), true, 0)


func _supply_selector() -> void:
	_text("开局补给 · 启程消耗 1 个", Vector2(90, 500), Vector2(670, 24), 14, DIM)
	var ids := ["", "supply_hp", "supply_revive", "supply_reroll"]
	for i in ids.size():
		var id := str(ids[i])
		var text := "不带补给"
		if id != "":
			text = "%s ×%d" % [Meta.INK_SHOP[id]["label"], Meta.supply_count(id)]
		var b := _texture_card(Vector2(90 + i * 169, 532), Vector2(158, 42), id == _supply)
		b.disabled = id != "" and Meta.supply_count(id) <= 0
		_card_text(b, text, Vector2.ZERO, b.size, 14, PAPER if not b.disabled else DIM)
		b.pressed.connect(func():
			_supply = id
			_click_sfx()
			_refresh())


func _button(text: String, x: float, y: float, cb: Callable, sfx: AudioStream = SFX_CLICK) -> TextureButton:
	var b := _texture_card(Vector2(x, y), Vector2(220, 52))
	_card_text(b, text, Vector2.ZERO, b.size, 22, PAPER)
	b.pressed.connect(func():
		if sfx != null:
			_play_sfx(sfx)
		cb.call())
	return b
