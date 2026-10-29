extends CanvasLayer

## 图鉴：主菜单入口（开始游戏 / 化身谱 / 图鉴 / 设置 / 退出）。
## 左栏是收录列表，两页：「敌人」只显示击败过的（没打过的占位 ？？？）、「化身」显示已解锁的。
## 右栏是骨架预览 + 背景故事 + 招式 / 技能清单：鼠标悬停某一条，预览立刻循环播该动作。
## 背景故事（LORE 表）与机制文案目前是占位，之后逐条替换即可；数值由形态表自动生成。

const InkTex = preload("res://scripts/ui/ink_tex.gd")
const Skulls = preload("res://scripts/player/skulls.gd")
const EnemyTypes = preload("res://scripts/enemies/enemy_types.gd")
const BossTypes = preload("res://scripts/enemies/boss_types.gd")
const SFX_CLICK := preload("res://audio/sfx/click.wav")

const INK := Color(0.05, 0.05, 0.05)
const PAPER := Color(0.949, 0.918, 0.847)
const DIM := Color(0.82, 0.79, 0.72)
const RED := Color(0.66, 0.2, 0.16)

const TAB_ENEMY := 0
const TAB_FORM := 1

## 敌人收录顺序：杂兵 → 精英 → Boss（Boss 追加在末尾，顺序按 boss_types.ROSTER）
const ENEMY_ORDER := ["c016", "z002", "c017", "c035", "c018", "c012", "c037"]

## 技能键位：与形态表 hud_skills 的顺序一一对应
const KEY_NAMES := ["K", "L", "U", "I", "O"]

## 化身通用动作：图鉴里也能悬停看待机 / 奔跑 / 闪避 / 滞空 / 受击 / 倒地
const ACT_ORDER := ["idle", "run", "dash", "air", "hurt", "dead"]
const ENEMY_ACT_ORDER := ["idle", "patrol", "chase", "hurt", "dead"]
const ACT_LABEL := {
	"idle": "待机", "patrol": "巡逻", "chase": "追击", "run": "奔跑",
	"dash": "闪避", "air": "滞空", "hurt": "受击", "dead": "倒地",
}

## 条目卡：左栏 2 列 × 6 行（当前最多 12 条：7 敌人 + 5 Boss）
const CARD_X := 70.0
const CARD_Y := 136.0
const CARD_W := 190.0
const CARD_H := 62.0
const CARD_STEP_X := 200.0
const CARD_STEP_Y := 70.0
const CARD_COLS := 2
const CARD_MAX := 12

## 右侧预览台：骨架站在台上，脚底贴着台面下沿
const STAGE_X := 490.0
const STAGE_Y := 136.0
const STAGE_W := 390.0
const STAGE_H := 268.0
const SPRITE_X := 685.0
const SPRITE_Y := 392.0

## 右侧文案栏（名称 / 分类 / 背景故事）
const TEXT_X := 900.0
const TEXT_W := 310.0
const LORE_Y := 200.0

## 动作条：4 列网格，最多 16 条（化身最多 3 普攻 + 5 技能 + 6 动作 = 14）
const ACT_ROW_Y := 450.0
const ACT_COLS := 4
const ACT_W := 174.0
const ACT_H := 44.0
const ACT_STEP_X := 182.0
const ACT_STEP_Y := 48.0
const ACT_MAX := 16

const HINT_TEXT := "鼠标悬停下方招式 / 技能，右侧演示对应动作"

## 占位背景故事：之后逐条替换成正式文案（键 = 形态 / 敌人 id）
const LORE := {
	"c016": "山野间最常见的亡命刀客，一柄卷刃长刀便是全部家当。死后连名字都没人记得，只有崖边的乱刀还在等下一场雨。",
	"z002": "黑袍裹身，剑不出鞘便已言明来意。传闻他曾是某位剑仙门下的弃徒，如今只在残卷里磨剑。",
	"c017": "身高逾丈的蛮族力士，巨斧拖地，走一步便有石屑翻飞。他从不追击，只站在原地等你自己撞上来。",
	"c035": "瘦小、沉默、出手极快。没有人见过他的正脸，只见过他离场时扬起的一线沙。",
	"c018": "双镰交错成一轮银月，出手密不透风。旧时是戏班里的双刀伶人，戏散了，刀却没收。",
	"c012": "斗笠压得很低，快剑藏在雨里。他是唯一一个会在危及性命时反而笑出声的人。",
	"c037": "披重甲、执阔剑，一步一顿。剑落之处地面塌陷，轻巧的刀在他身上只留下一道白印。",
	"c009": "巨兽为骑，雷纹在胸口游走。传闻他是墨堂豢养的守门凶神——兽不死，霆不止。",
	"c015a1": "紫焰锁链缠身的巨汉，抬手即成火海。鼎早已焚毁，锁链还绑在他身上。",
	"c001": "双马拖曳的钢铁战车，长枪横扫如墙。它不懂退让，只会掉头再来一次。",
	"c008": "墨甲覆体的巨汉，一拳能碎掉半座山。他与墨霆同出一炉，性子却更沉。",
	"c032": "墨甲钟馗，三度变身三度鸣钟。钟声一响，卷里的墨都要跟着退三寸。",
	"c021": "红缨双匕，面纱长裙。她原是戏班里的舞姬，一场大火之后，把舞步练成了杀招。",
	"c013": "僧人不用禅杖，只用一根狼牙棒。他说心定如山，山不必慈悲。",
	"c023": "白发黑袍，长剑上缠着一枝梅。她走过的地方，雪落得比别人慢一些。",
	"z000": "剑不出鞘而剑气先至。他自称剑仙，其实从未仙过，只是从未败过。",
	"z003": "轻功踏雪无痕，五式剑技收在袖中。名姓取自一句旧诗——将去未还，便永不再回头。",
}

var _tab := TAB_ENEMY
var _sel := "" # 当前选中的条目 id
var _sfx: AudioStreamPlayer
var _preview = null # 右侧演示用的 SpineSprite
var _idle_anim := "" # 悬停结束时回到的动作
var _current_anim := "" # 测试用：当前正在演的动作名
var _desc: Label


func _ready() -> void:
	layer = 9
	# 点击音常驻一份：切换条目 / 切页会整体重建界面，不能连它一起清掉
	_sfx = AudioStreamPlayer.new()
	add_child(_sfx)
	_sfx.stream = SFX_CLICK
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
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

	_make_label("图  鉴", Vector2(70, 44), Vector2(320, 52), 40, PAPER)
	_make_button("敌 人", Vector2(940, 52), Vector2(140, 44), 18, _switch_tab.bind(TAB_ENEMY), _tab == TAB_ENEMY)
	_make_button("化 身", Vector2(1092, 52), Vector2(140, 44), 18, _switch_tab.bind(TAB_FORM), _tab == TAB_FORM)

	# 选中项失效（切页 / 刚收录）时退回第一条
	var entries := _entries()
	var ids: Array = []
	for e in entries:
		ids.append(str(e["id"]))
	if not ids.has(_sel):
		_sel = str(ids[0]) if not ids.is_empty() else ""

	var got := 0
	for e in entries:
		if not bool(e["locked"]):
			got += 1
	_make_label("%s %d / %d ｜ 悬停招式即演示" % ["已收录" if _tab == TAB_ENEMY else "已解锁", got, entries.size()],
		Vector2(70, 104), Vector2(470, 26), 13, DIM)

	# 先搭预览与详情，再铺条目卡：招式动画会甩出预览台，卡片后画才能盖住溢出的部分
	_build_detail()

	for i in mini(entries.size(), CARD_MAX):
		_make_card(entries[i], i)

	_make_button("返  回", Vector2(70, 572), Vector2(130, 44), 20, _close)


## 重建：只留常驻点击音节点（按钮不能在自身信号里销毁自己，故一律延迟调用）
func _refresh() -> void:
	for c in get_children():
		if c == _sfx:
			continue
		remove_child(c)
		c.queue_free()
	_preview = null
	_desc = null
	_current_anim = ""
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


func _close() -> void:
	queue_free()


# ---------- 收录列表 ----------

## 当前页的条目：{id, locked, label, sub}
func _entries() -> Array:
	var out: Array = []
	if _tab == TAB_ENEMY:
		for id in ENEMY_ORDER:
			if not EnemyTypes.TYPES.has(id):
				continue
			var t: Dictionary = EnemyTypes.get_type(id)
			var n := Meta.enemy_kills(id)
			out.append({"id": id, "locked": n <= 0, "label": str(t["label"]),
				"sub": ("已击败 %d 次" % n) if n > 0 else "尚未收录"})
		for id in BossTypes.ROSTER:
			if not BossTypes.BOSSES.has(id):
				continue
			var b: Dictionary = BossTypes.get_boss(id)
			var nb := Meta.enemy_kills(id)
			out.append({"id": id, "locked": nb <= 0, "label": str(b["label"]),
				"sub": ("已讨伐 %d 次" % nb) if nb > 0 else "尚未收录"})
	else:
		for id in Skulls.ids():
			var p: Dictionary = Skulls.get_profile(id)
			var unlocked := Meta.is_unlocked(id)
			out.append({"id": id, "locked": not unlocked, "label": str(p["label"]),
				"sub": str(p.get("name", "")) if unlocked else "未解锁"})
	return out


func _make_card(e: Dictionary, i: int) -> void:
	var id := str(e["id"])
	var locked := bool(e["locked"])

	var card := TextureButton.new()
	card.texture_normal = InkTex.load("res://art/ui/menu/btn_normal.png")
	card.texture_hover = InkTex.load("res://art/ui/menu/btn_clicked.png")
	card.texture_pressed = InkTex.load("res://art/ui/menu/btn_clicked.png")
	card.ignore_texture_size = true
	card.stretch_mode = TextureButton.STRETCH_SCALE
	card.size = Vector2(CARD_W, CARD_H)
	card.position = Vector2(CARD_X + (i % CARD_COLS) * CARD_STEP_X, CARD_Y + int(i / CARD_COLS) * CARD_STEP_Y)
	if locked:
		card.modulate = Color(1, 1, 1, 0.55)
	card.pressed.connect(_select.bind(id))
	add_child(card)

	# 选中：卡片左缘一道朱砂细条，扫一眼就知道当前在看谁
	if id == _sel:
		var bar := ColorRect.new()
		bar.color = RED
		bar.size = Vector2(4, CARD_H)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(bar)

	_entry_label(card, "？？？" if locked else str(e["label"]), 8, 18, PAPER)
	_entry_label(card, str(e["sub"]), 34, 12, DIM)


# ---------- 右侧详情 ----------

func _build_detail() -> void:
	var m := _model(_sel)

	var stage := ColorRect.new()
	stage.color = Color(0, 0, 0, 0.28)
	stage.position = Vector2(STAGE_X, STAGE_Y)
	stage.size = Vector2(STAGE_W, STAGE_H)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)

	# 预览先画：甩出预览台的刀光会被后面的文字 / 卡片盖住，不会糊字
	var data = null
	if not m.is_empty() and not bool(m["locked"]):
		data = load(str(m["data"]))
		if data == null or not data.call("is_skeleton_data_loaded"):
			data = null
		else:
			_make_preview(data, float(m["view_scale"]), str(m["idle"]))

	# 悬停说明行：放在预览台与动作条之间
	_desc = Label.new()
	_desc.text = HINT_TEXT
	_desc.position = Vector2(STAGE_X, STAGE_Y + STAGE_H + 8)
	_desc.size = Vector2(730, 36)
	_desc.add_theme_color_override("font_color", DIM)
	_desc.add_theme_font_size_override("font_size", 13)
	_desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_desc)

	if m.is_empty():
		return

	_make_label(str(m["title"]), Vector2(TEXT_X, 132), Vector2(TEXT_W, 36), 26, PAPER)
	_make_label(str(m["sub"]), Vector2(TEXT_X, 172), Vector2(TEXT_W, 24), 14, DIM)

	# 背景故事：中文没有词边界，用 RichTextLabel 按矩形宽度逐字换行（Label 会被最小宽度顶开）
	var lore := RichTextLabel.new()
	lore.text = str(m["lore"])
	lore.position = Vector2(TEXT_X, LORE_Y)
	lore.size = Vector2(TEXT_W, 200)
	lore.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	lore.scroll_active = false
	lore.add_theme_stylebox_override("normal", StyleBoxEmpty.new()) # 去掉默认内边距，和上方标题左对齐
	lore.add_theme_color_override("default_color", RED if bool(m["locked"]) else DIM)
	lore.add_theme_font_size_override("normal_font_size", 15)
	lore.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lore)

	if bool(m["locked"]):
		_make_label("尚 未 收 录", Vector2(STAGE_X, STAGE_Y + 108), Vector2(STAGE_W, 40), 24, RED)
		return

	if data == null:
		return

	var anims := _anim_names(data)
	var n := 0
	for a in m["actions"]:
		if n >= ACT_MAX:
			break
		if not anims.has(str(a["anim"])):
			continue # 骨架里没有的动作不画，避免点了播不出来
		_make_action_row(a, n)
		n += 1


## 条目详情模型：敌人与化身统一成同一份结构，右栏只认这一份
func _model(id: String) -> Dictionary:
	if id == "":
		return {}
	if _tab == TAB_ENEMY:
		var is_boss := BossTypes.ROSTER.has(id)
		var t: Dictionary = BossTypes.get_boss(id) if is_boss else EnemyTypes.get_type(id)
		var times := Meta.enemy_kills(id)
		if times <= 0:
			return {"id": id, "locked": true, "title": "？？？", "sub": "尚未收录", "data": str(t["data"]),
				"lore": "还没有击败过这只敌人。\n在战斗中击杀它之后，这里会亮出它的来历、招式与数值。",
				"view_scale": 1.0, "idle": "stand", "actions": []}
		var kind := "Boss" if is_boss else ("精英" if bool(t.get("elite", false)) else "杂兵")
		return {
			"id": id, "locked": false, "title": str(t["label"]),
			"sub": "%s · 生命 %d · 已击败 %d 次" % [kind, int(t.get("hp", 0)), times],
			"lore": str(LORE.get(id, "")),
			"data": str(t["data"]),
			"view_scale": _enemy_scale(t, is_boss),
			"idle": str(t["anim"]["idle"]),
			"actions": _enemy_actions(t, is_boss),
		}

	var p: Dictionary = Skulls.get_profile(id)
	if not Meta.is_unlocked(id):
		return {"id": id, "locked": true, "title": "？？？", "sub": Meta.unlock_hint(id), "data": str(p["data"]),
			"lore": "尚未解锁的化身。\n" + Meta.unlock_hint(id) + "（" + Meta.unlock_progress(id) + "）",
			"view_scale": 1.0, "idle": "stand", "actions": []}
	return {
		"id": id, "locked": false, "title": str(p["label"]),
		"sub": "化身 · %s ｜ 契合 %s" % [str(p.get("name", "")), Meta.mastery_text(id)],
		"lore": str(LORE.get(id, "")),
		"data": str(p["data"]),
		"view_scale": float(p["scale"]) * 1.45, # 游戏内 128px 高，图鉴里放大到约 186px
		"idle": str(p["anim"]["idle"]),
		"actions": _form_actions(p),
	}


## 预览缩放：杂兵 / 精英 / Boss 各给一档放大倍率，别让巨物溢出预览台
func _enemy_scale(t: Dictionary, is_boss: bool) -> float:
	var base := float(t["scale"])
	if is_boss:
		return base * 0.5 # Boss 本体最高 447px，缩到 225px 左右仍完整落在预览台内
	if bool(t.get("elite", false)):
		return base * 1.25
	return base * 1.55


# ---------- 动作清单 ----------

func _form_actions(p: Dictionary) -> Array:
	var out: Array = []
	var atks: Array = p.get("attacks", [])
	for i in atks.size():
		var a: Dictionary = atks[i]
		var anim := _first_anim(a)
		out.append({"label": "普攻 %d" % (i + 1), "anim": anim,
			"num": _attack_num(a, anim), "desc": _attack_desc(a)})
	var keys: Array = p.get("hud_skills", [])
	var skills: Dictionary = p.get("skills", {})
	for i in keys.size():
		var key := str(keys[i])
		if not skills.has(key):
			continue
		var cfg: Dictionary = skills[key]
		var pool: Array = cfg.get("pool", [key])
		out.append({
			"label": ("技能 %s" % KEY_NAMES[i]) if i < KEY_NAMES.size() else ("技能 %d" % (i + 1)),
			"anim": str(pool[0]),
			"num": _skill_num(cfg),
			"desc": _skill_desc(cfg),
		})
	var map: Dictionary = p.get("anim", {})
	for act in ACT_ORDER:
		if map.has(act):
			out.append({"label": str(ACT_LABEL.get(act, act)), "anim": str(map[act]), "num": "", "desc": ""})
	return out


func _enemy_actions(t: Dictionary, is_boss: bool) -> Array:
	var out: Array = []
	var names: Array = []
	if is_boss:
		for st in t.get("stages", []):
			for n in st.get("attacks", []):
				if not names.has(str(n)):
					names.append(str(n))
	else:
		for n in t.get("attacks", []):
			names.append(str(n))

	var ranges: Dictionary = t.get("ranges", {})
	var hit_at: Dictionary = t.get("hit_at", {})
	var damage: Dictionary = t.get("damage", {})
	for i in names.size():
		var n := str(names[i])
		var parts: Array = []
		if hit_at.has(n):
			var h = hit_at[n]
			if typeof(h) == TYPE_ARRAY:
				parts.append("%d 段" % (h as Array).size())
			else:
				parts.append("%.2fs" % float(h))
		if ranges.has(n):
			var r = ranges[n]
			if typeof(r) == TYPE_ARRAY:
				parts.append("%dpx" % int((r as Array)[0]))
			else:
				parts.append("%dpx" % int(r))
		parts.append("%d伤" % int(damage.get(n, 1)))
		out.append({"label": "招式 %d" % (i + 1), "anim": n, "num": " ｜ ".join(parts), "desc": "敌人招式：出招时刻即判定命中"})

	var map: Dictionary = t.get("anim", {})
	for act in ENEMY_ACT_ORDER:
		if map.has(act):
			out.append({"label": str(ACT_LABEL.get(act, act)), "anim": str(map[act]), "num": "", "desc": ""})

	if is_boss:
		for st in t.get("stages", []):
			var tf := str(st.get("transform", ""))
			if tf != "":
				out.append({"label": "变身", "anim": tf, "num": "", "desc": "血量跌破阶段阈值时的变身演出"})
				break
	return out


func _first_anim(a: Dictionary) -> String:
	if a.has("pool"):
		var pool: Array = a["pool"]
		if not pool.is_empty():
			return str(pool[0])
	return str(a.get("anim", ""))


## 普攻数值：伤害 / 射程（形态表里普攻写法有三代：hits 时间数组、hits 字典数组、按动画名查表）
func _attack_num(a: Dictionary, anim: String) -> String:
	var dmg := int(a.get("damage", 1))
	var rng := 0.0
	if a.has("hits"):
		var hits: Array = a["hits"]
		if not hits.is_empty() and typeof(hits[0]) == TYPE_DICTIONARY:
			var h: Dictionary = hits[0]
			dmg = int(h.get("damage", dmg))
			rng = float(h.get("range", 0.0))
		else:
			rng = float(a.get("range", 0.0))
	elif a.has("range"):
		var r = a["range"]
		rng = float(r.get(anim, 0.0)) if typeof(r) == TYPE_DICTIONARY else float(r)
	var parts: Array = ["%d伤" % dmg]
	if rng > 0.0:
		parts.append("%dpx" % int(rng))
	if a.has("projectile"):
		parts.append("远程")
	if a.has("launch"):
		parts.append("击飞")
	return " ｜ ".join(parts)


func _attack_desc(a: Dictionary) -> String:
	if a.has("launch"):
		return "把敌人挑到空中，落地硬直"
	if a.has("projectile"):
		return "挥剑甩出剑气，远程命中"
	if a.has("both"):
		return "回身横扫，身前身后都能命中"
	return "近身连击"


## 技能数值：冷却 / 伤害 / 治疗 / 强化 / 时停（卡片窄，全部用短写法）
func _skill_num(cfg: Dictionary) -> String:
	var parts: Array = []
	if cfg.has("cooldown"):
		parts.append("%.1fs" % float(cfg["cooldown"]))
	if cfg.has("heal"):
		parts.append("回血%d" % int(cfg["heal"]))
	if cfg.has("buff_damage"):
		parts.append("加伤%d/%ds" % [int(cfg["buff_damage"]), int(cfg.get("buff_time", 0))])
	if cfg.has("tick"):
		var tick: Dictionary = cfg["tick"]
		parts.append("转击%d/%.2fs" % [int(tick.get("damage", 1)), float(tick.get("interval", 0.5))])
	var dmg := 0
	var cnt := 0
	for h in cfg.get("hits", []):
		if typeof(h) == TYPE_DICTIONARY and (h as Dictionary).has("damage"):
			dmg = maxi(dmg, int((h as Dictionary)["damage"]))
			cnt += 1
	if dmg > 0:
		parts.append("%d伤%s" % [dmg, ("×%d" % cnt) if cnt > 1 else ""])
	if cfg.has("stop"):
		parts.append("时停")
	# 远程技能：命中段里带 projectile 就是扔东西出去
	for h in cfg.get("hits", []):
		if typeof(h) == TYPE_DICTIONARY and (h as Dictionary).has("projectile"):
			parts.append("远程")
			break
	return " ｜ ".join(parts)


## 技能机制标签：从配置里能读出来的机制逐条拍上去（真正的文字说明之后由 LORE/文案补）
func _skill_desc(cfg: Dictionary) -> String:
	var tags: Array = []
	if bool(cfg.get("poise", false)):
		tags.append("起手霸体")
	if bool(cfg.get("invincible", false)):
		tags.append("全程无敌")
	if bool(cfg.get("reflect", false)):
		tags.append("挨打反伤")
	if bool(cfg.get("ranged_guard", false)):
		tags.append("弹反远程")
	if bool(cfg.get("path", false)):
		tags.append("路径贯穿")
	if cfg.has("blink_from"):
		tags.append("瞬步位移")
	if cfg.has("knockback"):
		tags.append("击退撞墙")
	# 命中追加效果：叠流血 / 命中定身（都写在 hits 段的可选字段里）
	var bleed := false
	var root := false
	for h in cfg.get("hits", []):
		if typeof(h) != TYPE_DICTIONARY:
			continue
		if int((h as Dictionary).get("bleed", 0)) > 0:
			bleed = true
		var proj = (h as Dictionary).get("projectile", null)
		if typeof(proj) == TYPE_DICTIONARY and float((proj as Dictionary).get("root", 0.0)) > 0.0:
			root = true
	if bleed:
		tags.append("命中叠流血")
	if root:
		tags.append("命中定身")
	return " · ".join(tags)


# ---------- 预览 / 动作条 ----------

func _make_preview(data, view_scale: float, idle: String) -> void:
	var sprite = ClassDB.instantiate("SpineSprite")
	add_child(sprite)
	sprite.set("skeleton_data_res", data)
	data.call("set_default_mix", 0.2)
	sprite.scale = Vector2(view_scale, view_scale)
	sprite.position = Vector2(SPRITE_X, SPRITE_Y)
	_preview = sprite
	_idle_anim = idle
	_play(idle)


func _anim_names(data) -> Dictionary:
	var out := {}
	for a in data.call("get_animations"):
		out[str(a.call("get_name"))] = true
	return out


func _make_action_row(a: Dictionary, i: int) -> void:
	var b := TextureButton.new()
	b.texture_normal = InkTex.load("res://art/ui/menu/btn_normal.png")
	b.texture_hover = InkTex.load("res://art/ui/menu/btn_clicked.png")
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.size = Vector2(ACT_W, ACT_H)
	b.position = Vector2(STAGE_X + (i % ACT_COLS) * ACT_STEP_X, ACT_ROW_Y + int(i / ACT_COLS) * ACT_STEP_Y)
	b.mouse_entered.connect(_on_action_hover.bind(a, b))
	b.mouse_exited.connect(_on_action_unhover.bind(b))
	add_child(b)
	_entry_label(b, str(a["label"]), 3, 15, PAPER)
	_entry_label(b, str(a["num"]), 23, 10, DIM)


## 悬停某一条动作：预览立刻循环播它，说明行换成这条的数值与机制
func _on_action_hover(a: Dictionary, b: Control) -> void:
	_play(str(a["anim"]))
	_tint_row(b, true)
	if _desc == null or not is_instance_valid(_desc):
		return
	var text := str(a["label"])
	if str(a["num"]) != "":
		text += " ｜ " + str(a["num"])
	if str(a["desc"]) != "":
		text += " ｜ " + str(a["desc"])
	_desc.text = text
	_desc.add_theme_color_override("font_color", PAPER)


## 移开鼠标：预览回到待机，说明行复位
func _on_action_unhover(b: Control) -> void:
	_play(_idle_anim)
	_tint_row(b, false)
	if _desc == null or not is_instance_valid(_desc):
		return
	_desc.text = HINT_TEXT
	_desc.add_theme_color_override("font_color", DIM)


## 悬停时按钮换成亮底，文字要转成墨色才看得清（亮底 + 米白字会糊）
func _tint_row(b: Control, hovered: bool) -> void:
	var i := 0
	for c in b.get_children():
		if c is Label:
			c.add_theme_color_override("font_color", INK if hovered else (PAPER if i == 0 else DIM))
			i += 1


func _play(anim: String) -> void:
	_current_anim = anim
	if _preview == null or not is_instance_valid(_preview) or anim == "":
		return
	var st = _preview.call("get_animation_state")
	if st == null:
		return
	st.call("set_animation", anim, true, 0) # 循环播：鼠标停在上面就一直演


func _select(id: String) -> void:
	if _sel == id:
		return
	_sel = id
	_click_sfx()
	call_deferred("_refresh")


func _switch_tab(tab: int) -> void:
	if _tab == tab:
		return
	_tab = tab
	_sel = ""
	_click_sfx()
	call_deferred("_refresh")


# ---------- 控件 ----------

func _make_label(text: String, pos: Vector2, size: Vector2, font_size: int, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = size
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)


func _entry_label(parent: Control, text: String, y: float, font_size: int, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.position = Vector2(0, y)
	l.size = Vector2(parent.size.x, 22)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)


func _make_button(text: String, pos: Vector2, size: Vector2, font_size: int, cb: Callable, active := false) -> void:
	var b := TextureButton.new()
	b.texture_normal = InkTex.load("res://art/ui/menu/btn_clicked.png" if active else "res://art/ui/menu/btn_normal.png")
	b.texture_pressed = InkTex.load("res://art/ui/menu/btn_normal.png")
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.size = size
	b.position = pos
	var l := Label.new()
	l.text = text
	l.size = size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", RED if active else PAPER)
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(l)
	b.pressed.connect(func():
		_click_sfx()
		cb.call())
	add_child(b)


## 点击音：复用常驻播放器（重建不清它），不每次点击都新建节点
func _click_sfx() -> void:
	if is_instance_valid(_sfx):
		_sfx.play()
