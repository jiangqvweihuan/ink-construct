extends CanvasLayer

const InkTex = preload("res://scripts/ui/ink_tex.gd")
const Skulls = preload("res://scripts/player/skulls.gd")
const BossTypes = preload("res://scripts/enemies/boss_types.gd")
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

	# ---- 内容区：战绩 → Boss 讨伐 → 契合经验条 → 新解锁 / 墨锭，光标逐行往下排 ----
	var cy := 226.0

	# 本局战绩：最高连击 / 击杀 / 剩余墨骨
	_make_line("最高连击 %d ｜ 击杀 %d ｜ 墨骨 %d" % [Score.max_combo, Score.kills, Score.bones], DIM, 20, cy)
	cy += 34.0

	# Boss 讨伐：通关局亮朱砂大字
	if _cleared and BossTypes.BOSSES.has(Run.boss_id):
		_make_line("讨伐 · %s" % str(BossTypes.get_boss(Run.boss_id).get("label", "")), RED, 26, cy)
		cy += 42.0

	# 契合经验：每个有增量的形态一行文字 + 一条从旧值涨到新值的经验条（升级则朱砂高亮）
	var rows := 0
	for id in diff["mastery"]:
		if rows >= 3 or cy > 420.0:
			break
		var old_exp := int(Run.meta_snapshot.get("mastery", {}).get(id, 0))
		_make_mastery_row(id, int(diff["mastery"][id]), old_exp, cy, rows)
		cy += 52.0
		rows += 1

	# 新解锁 / 墨锭沉淀
	for id in diff["unlocks"]:
		if cy > 456.0:
			break
		_make_line("新化身解锁：%s · %s" % [str(Skulls.get_profile(id)["label"]), str(Skulls.get_profile(id).get("name", ""))], RED, 22, cy)
		cy += 34.0
	if ink_gain > 0 and cy <= 456.0:
		_make_line("墨锭 +%d（总 %d）" % [ink_gain, Meta.ink], PAPER, 22, cy)
		cy += 34.0
	if rows == 0 and diff["unlocks"].is_empty() and ink_gain <= 0:
		_make_line("本局无额外收获", DIM, 20, cy)

	_make_button("再来一局", 490, _restart)
	_make_button("回主菜单", 565, _to_menu)


## 居中文本行
func _make_line(text: String, color: Color, font_size: int, y: float) -> void:
	var l := Label.new()
	l.text = text
	l.size = Vector2(560, 32)
	l.position = Vector2(360, y)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)


## 契合经验行：文字 + 经验条（旧值 → 新值缓动填充，暂停中也要播）
func _make_mastery_row(id: String, gain: int, old_exp: int, y: float, row: int) -> void:
	var new_exp := Meta.mastery_exp(id)
	var lv_old := _level_of(old_exp)
	var lv_new := Meta.mastery_level(id)
	var leveled := lv_new > lv_old
	var text := "%s · %s  契合 +%d（%s）" % [str(Skulls.get_profile(id)["label"]), str(Skulls.get_profile(id).get("name", "")), gain, Meta.mastery_text(id)]
	if leveled:
		text = "%s · %s  契合 +%d  Lv%d → Lv%d！" % [str(Skulls.get_profile(id)["label"]), str(Skulls.get_profile(id).get("name", "")), gain, lv_old, lv_new]
	_make_line(text, RED if leveled else PAPER, 20, y)

	# 经验条：320×12，底板暗色，填充朱砂
	var bar_bg := ColorRect.new()
	bar_bg.color = Color(0, 0, 0, 0.55)
	bar_bg.size = Vector2(320, 12)
	bar_bg.position = Vector2(480, y + 30)
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar_bg)
	var fill := ColorRect.new()
	fill.color = RED
	fill.position = Vector2.ZERO
	fill.size = Vector2(_frac_of(old_exp) * 320.0, 12)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_bg.add_child(fill)
	# 暂停中 Tween 默认不走，显式设成始终处理；逐级错开入场
	var tw := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(fill, "size:x", _frac_of(new_exp) * 320.0, 0.7) \
		.set_delay(0.4 + row * 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## 契合等级：与 Meta.mastery_level 同规则，但按传入经验算（对比旧值用）
func _level_of(exp: int) -> int:
	var lv := 0
	for need in Meta.LV_EXP:
		if exp >= int(need):
			lv += 1
	return lv


## 当前等级内的经验进度 0..1（满级恒 1）
func _frac_of(exp: int) -> float:
	var prev := 0
	for need in Meta.LV_EXP:
		var n := int(need)
		if exp < n:
			return float(exp - prev) / float(n - prev)
		prev = n
	return 1.0


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
