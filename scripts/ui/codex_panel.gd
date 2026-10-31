extends CanvasLayer

## 图鉴 · 主菜单入口。
## 左栏收录列表（敌人 / 化身两页），右栏：上面是动画演示台 + 技能解析面板，右下是角色简介（可滚动）。
## 交互一律点击：默认播待机动画；点下方招式 / 技能 / 动作按钮，演示台播该动作并把
## 来历 / 机制 / 数值 / 冷却写进解析面板；一条技能带多个变式（pool）时用 ↑ / ↓ 手动切换。
## 每个角色（含敌人）都按词条分类，并预留一个被动技能占位钮（内容等第 6 阶段补）。
## 背景故事（LORE）与技能来历目前是占位，之后逐条替换即可；数值由形态表自动生成。

const InkTex = preload("res://scripts/ui/ink_tex.gd")
const Skulls = preload("res://scripts/player/skulls.gd")
const EnemyTypes = preload("res://scripts/enemies/enemy_types.gd")
const SpinePoseMixer = preload("res://scripts/systems/spine_pose_mixer.gd")
const BossTypes = preload("res://scripts/enemies/boss_types.gd")
const SFX_CLICK := preload("res://audio/sfx/click.wav")

const INK := Color(0.05, 0.05, 0.05)
const PAPER := Color(0.949, 0.918, 0.847)
const DIM := Color(0.82, 0.79, 0.72)
const RED := Color(0.66, 0.2, 0.16)
const GOLD := Color(0.9, 0.75, 0.3) # 英雄级主角的金标

const TAB_ENEMY := 0
const TAB_FORM := 1

## 敌人收录顺序：杂兵 → 精英 → Boss（Boss 追加在末尾，顺序按 boss_types.ROSTER）
const ENEMY_ORDER := ["c016", "z002", "c017", "c035", "c018", "c012", "c037"]

## 技能键位：与形态表 hud_skills 的顺序一一对应
const KEY_NAMES := ["K", "L", "U", "I", "O", "P"]

## 化身通用动作：图鉴里也能点看待机 / 奔跑 / 闪避 / 滞空 / 受击 / 倒地
const ACT_ORDER := ["idle", "run", "dash", "air", "hurt", "dead"]
const ENEMY_ACT_ORDER := ["idle", "patrol", "chase", "hurt", "dead"]
const ACT_LABEL := {
	"idle": "待机", "patrol": "巡逻", "chase": "追击", "run": "奔跑",
	"dash": "闪避", "air": "滞空", "hurt": "受击", "dead": "倒地",
}

## 词条体系：四组（战斗定位 / 机制 / 出身 / 稀有度），一个人物可挂多条
const TAG_COLORS := {
	"近战": "#e8dfc4", "远程": "#e8dfc4", "机动": "#e8dfc4", "站桩": "#e8dfc4",
	"控场": "#e8dfc4", "爆发": "#e8dfc4",
	"霸体": "#c89440", "反击": "#c89440", "回血": "#c89440", "击飞": "#c89440",
	"定身": "#c89440", "晕眩": "#c89440", "流血": "#c89440", "中毒": "#c89440",
	"时停": "#c89440", "召唤": "#c89440",
	"墨堂": "#5d8a93", "山野": "#5d8a93", "戏班": "#5d8a93", "僧门": "#5d8a93",
	"剑门": "#5d8a93", "妖异": "#5d8a93",
	"杂兵": "#a8332a", "精英": "#a8332a", "首领": "#a8332a", "化身": "#a8332a",
}

## 人物词条：键 = 形态 / 敌人 id，值 = 词条数组（2~5 条）
const TAGS := {
	"c016": ["近战", "爆发", "回血", "山野", "杂兵"],
	"z002": ["近战", "机动", "剑门", "杂兵"],
	"c017": ["近战", "站桩", "霸体", "山野", "杂兵"],
	"c035": ["近战", "机动", "爆发", "妖异", "杂兵"],
	"c037": ["近战", "站桩", "霸体", "击飞", "精英"],
	"c018": ["近战", "机动", "流血", "戏班", "精英"],
	"c012": ["近战", "机动", "反击", "剑门", "精英"],
	"c009": ["近战", "召唤", "击飞", "墨堂", "首领"],
	"c015a1": ["近战", "站桩", "晕眩", "妖异", "首领"],
	"c001": ["近战", "站桩", "击飞", "墨堂", "首领"],
	"c008": ["近战", "站桩", "霸体", "墨堂", "首领"],
	"c032": ["近战", "控场", "定身", "墨堂", "首领"],
	"c021": ["近战", "机动", "流血", "戏班", "化身"],
	"c013": ["近战", "站桩", "霸体", "僧门", "化身"],
	"c023": ["近战", "控场", "中毒", "剑门", "化身"],
	"z000": ["近战", "连段", "机动", "剑门", "化身"],
	"z003": ["近战", "机动", "时停", "剑门", "化身"],
}

## 刀客正式招式资料；其余敌人仍沿用「招式 N」与待定来历，后续逐个补齐。
const ENEMY_ATTACK_NAMES := {
	"c016": {"skill01": "亡命三刀", "skill02": "螺旋鞭", "skill03": "升龙刀", "skill04": "双镰"},
}
const ENEMY_ATTACK_MECH := {
	"c016": {
		"skill01": "默认普攻；三刀均有受击反馈，前两刀不扣血，末刀造成 1 点伤害",
		"skill02": "180～400px 内主动释放，独立冷却 8 秒；命中造成 1 点伤害",
		"skill03": "追击窗口内瞬至身前，独立冷却 12 秒；保留 0.87 秒前摇，命中造成 2 点伤害",
		"skill04": "164px 内低权重释放，独立冷却 6 秒；命中造成 1 点伤害",
	},
}
const ENEMY_ATTACK_LORE := {
	"c016": {
		"skill01": "他替商队挡过三次劫刀：第一刀断粮，第二刀断路，第三刀才明白命不是自己的。此后前两刀只逼破绽，最后一刀连旧账一起讨。",
		"skill02": "早年他在山口套惊马，绳索绕臂三周，借旋劲把畜生拉回。后来绳换成鞭，马没套住几匹，过路人倒是一个也没走远。",
		"skill03": "山民追崖羊练出一口憋气劲：先贴到猎物身前，再借上冲之势出刀。刀未必能升龙，人至少先离了泥地。",
		"skill04": "左手镰收麦，右手镰收债。丰年是农具，荒年就是兵器；他说两样都算收成，只看地里长的是谷子还是人。",
	},
}
const ENEMY_PASSIVES := {
	"c016": {
		"name": "山 民",
		"desc": "每 5 秒恢复 1 点生命，不超过生命上限",
		"lore": "山里跌打损伤没人替你看，采苦草、嚼根茎，熬过几夜就算捡回来。他不懂医术，只知道山不会主动救谁，却总会给人留一口气。",
	},
}

## 条目卡：左栏 2 列 × 6 行（当前最多 12 条）
const CARD_X := 70.0
const CARD_Y := 136.0
const CARD_W := 190.0
const CARD_H := 62.0
const CARD_STEP_X := 200.0
const CARD_STEP_Y := 70.0
const CARD_COLS := 2
const CARD_MAX := 12

## 动画演示台：骨架站在台上，脚底贴台面下沿
const STAGE_X := 470.0
const STAGE_Y := 130.0
const STAGE_W := 380.0
const STAGE_H := 278.0
const SPRITE_X := 660.0
const SPRITE_Y := 406.0

## 技能解析面板（点击下方按钮后填充）
const DESC_X := 470.0
const DESC_Y := 414.0
const DESC_W := 380.0
const DESC_H := 132.0

## 右侧简介栏（名称 / 副标 / 词条 / 状态 / 可滚动背景故事）
const TEXT_X := 870.0
const TEXT_W := 340.0
const TITLE_Y := 122.0
const SUB_Y := 160.0
const TAG_Y := 184.0
const TAG_H := 52.0
const STAT_Y := 238.0
const LORE_Y := 264.0
const LORE_H := 322.0

## 动作按钮：8 列 × 最多 3 行（普攻 / 技能 / 通用动作 / 被动全塞得下）
const BTN_X := 470.0
const BTN_Y := 552.0
const BTN_W := 86.0
const BTN_H := 30.0
const BTN_GAP := 5.0
const BTN_COLS := 8
const BTN_STEP_Y := 34.0
const ACT_MAX := 24

const HINT_TEXT := "点击招式 / 技能播放演示；多变式用 ↑ / ↓ 切换；解析含数值 · 机制 · 冷却 · 来历"

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
	"z000": "一袭青衣，一柄长剑。她出剑从不问远近，只因踏上剑锋所指之处，便已是她的近身。",
	"z003": "轻功踏雪无痕，五式剑技收在袖中。名姓取自一句旧诗——将去未还，便永不再回头。",
}

var _tab := TAB_ENEMY
var _sel := "" # 当前选中的条目 id
var _sfx: AudioStreamPlayer

var _preview = null # 演示台用的 SpineSprite
var _pose_mixer = null
var _pending_anim := ""
var _idle_anim := "" # 待机动画名（默认演示 / 取消选中时回到这里）
var _current_anim := "" # 测试用：当前正在演的动作名
var _desc_rt: RichTextLabel # 技能解析面板

var _acts: Array = [] # 当前角色的动作条目（{label, anims, kind, src}）
var _act_btns: Array = [] # 动作按钮
var _act_bars: Array = [] # 选中条（按钮左缘朱砂细条）
var _act_labels: Array = [] # 按钮文字（亮底时转墨色）
var _hover_idx := -1 # 鼠标悬停的按钮下标（亮底 + 墨字）
var _pick_idx := -1 # 当前选中动作下标
var _pool: Array = [] # 当前动作的动画池
var _pool_i := 0 # 池内当前变式下标


func _ready() -> void:
	layer = 9
	# 点击音常驻：切换条目 / 切页会整体重建界面，不能连它一起清掉
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
	_make_label("%s %d / %d ｜ 点选招式查看解析" % ["已收录" if _tab == TAB_ENEMY else "已解锁", got, entries.size()],
		Vector2(70, 104), Vector2(470, 26), 13, DIM)

	# 先搭演示与详情，再铺条目卡：招式动画会甩出演示台，卡片后画才能盖住溢出的部分
	_build_detail()

	for i in mini(entries.size(), CARD_MAX):
		_make_card(entries[i], i)

	_make_button("返  回", Vector2(70, 572), Vector2(130, 44), 20, _close)


## 重建：只留常驻节点（按钮不能在自身信号里销毁自己，故一律延迟调用）
func _refresh() -> void:
	for c in get_children():
		if c == _sfx:
			continue
		remove_child(c)
		c.queue_free()
	_preview = null
	_pose_mixer = null
	_pending_anim = ""
	_desc_rt = null
	_current_anim = ""
	_acts = []
	_act_btns = []
	_act_bars = []
	_act_labels = []
	_hover_idx = -1
	_pick_idx = -1
	_pool = []
	_pool_i = 0
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up") and _pool.size() > 1:
		_cycle_pool(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down") and _pool.size() > 1:
		_cycle_pool(1)
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
				"sub": _enemy_kind(t, false) if n > 0 else "尚未收录"})
		for id in BossTypes.ROSTER:
			if not BossTypes.BOSSES.has(id):
				continue
			var b: Dictionary = BossTypes.get_boss(id)
			var nb := Meta.enemy_kills(id)
			out.append({"id": id, "locked": nb <= 0, "label": str(b["label"]),
				"sub": "首领" if nb > 0 else "尚未收录"})
	else:
		for id in Skulls.ids():
			var p: Dictionary = Skulls.get_profile(id)
			var unlocked := Meta.is_unlocked(id)
			out.append({"id": id, "locked": not unlocked, "label": str(p["label"]),
				"sub": str(p.get("name", "")) if unlocked else "未解锁",
				"hero": bool(p.get("hero", false))})
	return out


func _enemy_kind(t: Dictionary, is_boss: bool) -> String:
	if is_boss:
		return "首领"
	return "精英" if bool(t.get("elite", false)) else "杂兵"


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

	# 英雄级主角（剑仙/银夜）：卡片右上角一点金标，扫一眼就知道这是能觉醒的主角
	if not locked and bool(e.get("hero", false)):
		var tag := Label.new()
		tag.text = "英雄"
		tag.position = Vector2(CARD_W - 48, 6)
		tag.size = Vector2(40, 18)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		tag.add_theme_color_override("font_color", GOLD)
		tag.add_theme_font_size_override("font_size", 12)
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(tag)


# ---------- 右侧详情 ----------

func _build_detail() -> void:
	var m := _model(_sel)

	var stage := ColorRect.new()
	stage.color = Color(0, 0, 0, 0.28)
	stage.position = Vector2(STAGE_X, STAGE_Y)
	stage.size = Vector2(STAGE_W, STAGE_H)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)

	# 演示先画：甩出演示台的刀光会被后面的文字 / 卡片盖住，不会糊字
	var data = null
	if not m.is_empty() and not bool(m["locked"]):
		data = load(str(m["data"]))
		if data == null or not data.call("is_skeleton_data_loaded"):
			data = null
		else:
			_make_preview(data, float(m["view_scale"]), str(m["idle"]))

	# 技能解析面板（点击动作按钮后填充）
	_desc_rt = RichTextLabel.new()
	_desc_rt.bbcode_enabled = true
	_desc_rt.position = Vector2(DESC_X, DESC_Y)
	_desc_rt.size = Vector2(DESC_W, DESC_H)
	_desc_rt.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_desc_rt.scroll_active = true
	_desc_rt.add_theme_stylebox_override("normal", _panel_style())
	_desc_rt.add_theme_color_override("default_color", DIM)
	_desc_rt.add_theme_font_size_override("normal_font_size", 13)
	_desc_rt.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_desc_rt)
	_desc_rt.text = "[color=#8a857a]%s[/color]" % HINT_TEXT

	if m.is_empty():
		return

	_make_label(str(m["title"]), Vector2(TEXT_X, TITLE_Y), Vector2(TEXT_W, 34), 26, PAPER)
	_make_label(str(m["sub"]), Vector2(TEXT_X, SUB_Y), Vector2(TEXT_W, 22), 13, DIM)

	# 词条：按组配色（战斗定位纸白 / 机制赭金 / 出身石青 / 稀有度朱砂）
	var tags: Array = m["tags"]
	var tag_rt := RichTextLabel.new()
	tag_rt.bbcode_enabled = true
	tag_rt.position = Vector2(TEXT_X, TAG_Y)
	tag_rt.size = Vector2(TEXT_W, TAG_H)
	tag_rt.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	tag_rt.scroll_active = false
	tag_rt.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	tag_rt.add_theme_font_size_override("normal_font_size", 13)
	tag_rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if tags.is_empty():
		tag_rt.text = "[color=#8a857a]词条未解锁[/color]"
	else:
		var parts: Array = []
		for t in tags:
			var nm := str(t)
			parts.append("[color=%s]· %s[/color]" % [str(TAG_COLORS.get(nm, "#e8dfc4")), nm])
		tag_rt.text = "  ".join(parts)
	add_child(tag_rt)

	if str(m["stat"]) != "":
		_make_label(str(m["stat"]), Vector2(TEXT_X, STAT_Y), Vector2(TEXT_W, 24), 13,
			RED if _tab == TAB_ENEMY else GOLD)

	# 背景故事：中文没有词边界，用 RichTextLabel 按矩形宽度逐字换行；过长可在栏内上下滚动
	var lore := RichTextLabel.new()
	lore.text = str(m["lore"])
	lore.position = Vector2(TEXT_X, LORE_Y)
	lore.size = Vector2(TEXT_W, LORE_H)
	lore.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	lore.scroll_active = true
	lore.add_theme_stylebox_override("normal", StyleBoxEmpty.new()) # 去掉默认内边距，和上方标题左对齐
	lore.add_theme_color_override("default_color", RED if bool(m["locked"]) else DIM)
	lore.add_theme_font_size_override("normal_font_size", 15)
	lore.mouse_filter = Control.MOUSE_FILTER_STOP # 鼠标在简介区才滚得动
	add_child(lore)

	if bool(m["locked"]):
		_make_label("尚 未 收 录", Vector2(STAGE_X, STAGE_Y + 108), Vector2(STAGE_W, 40), 24, RED)
		_desc_rt.text = "[color=#8a857a]%s[/color]" % str(m["lore"])
		return

	if data == null:
		_desc_rt.text = "[color=#8a857a]骨架资源缺失，仅显示文字资料。[/color]"
		return

	# 动作按钮：先按骨架里真实存在的动画过滤，再铺 8 列网格
	var anims := _anim_names(data)
	var built: Array = []
	for a in m["actions"]:
		if _trim_anims(a, anims):
			built.append(a)
	if built.size() > ACT_MAX:
		built = built.slice(0, ACT_MAX)
	_acts = built
	for i in _acts.size():
		_make_action_button(_acts[i], i)


## 条目详情模型：敌人与化身统一成同一份结构，右栏只认这一份
func _model(id: String) -> Dictionary:
	if id == "":
		return {}
	if _tab == TAB_ENEMY:
		var is_boss := BossTypes.ROSTER.has(id)
		var t: Dictionary = BossTypes.get_boss(id) if is_boss else EnemyTypes.get_type(id)
		var times := Meta.enemy_kills(id)
		if times <= 0:
			return {"id": id, "locked": true, "title": "？？？", "sub": "尚未收录", "stat": "",
				"tags": [], "data": str(t["data"]),
				"lore": "还没有击败过这只敌人。\n在战斗中击杀它之后，这里会亮出它的来历、招式与数值。",
				"view_scale": 1.0, "idle": "stand", "actions": []}
		return {
			"id": id, "locked": false, "title": str(t["label"]),
			"sub": "%s · 生命 %d" % [_enemy_kind(t, is_boss), int(t.get("hp", 0))],
			"stat": "已击败 %d 次" % times,
			"tags": (TAGS.get(id, []) as Array).duplicate(),
			"lore": str(LORE.get(id, "")),
			"data": str(t["data"]),
			"view_scale": _enemy_scale(t, is_boss),
			"idle": str(t["anim"]["idle"]),
			"actions": _enemy_actions(t, is_boss, id),
		}

	var p: Dictionary = Skulls.get_profile(id)
	if not Meta.is_unlocked(id):
		return {"id": id, "locked": true, "title": "？？？", "sub": Meta.unlock_hint(id), "stat": "",
			"tags": [], "data": str(p["data"]),
			"lore": "尚未解锁的化身。\n" + Meta.unlock_hint(id) + "（" + Meta.unlock_progress(id) + "）",
			"view_scale": 1.0, "idle": "stand", "actions": []}
	return {
		"id": id, "locked": false, "title": str(p["label"]),
		"sub": "化身 · %s" % str(p.get("name", "")),
		"stat": "契合 " + Meta.mastery_text(id),
		"tags": (TAGS.get(id, []) as Array).duplicate(),
		"lore": str(LORE.get(id, "")),
		"data": str(p["data"]),
		"view_scale": float(p["scale"]) * 1.45, # 游戏内 128px 高，图鉴里放大到约 186px
		"idle": str(p["anim"]["idle"]),
		"actions": _form_actions(p),
	}


## 预览缩放：杂兵 / 精英 / Boss 各给一档放大倍率，别让巨物溢出演示台
func _enemy_scale(t: Dictionary, is_boss: bool) -> float:
	var base := float(t["scale"])
	if is_boss:
		return base * 0.5 # Boss 本体最高 447px，缩到 225px 左右仍完整落在演示台内
	if bool(t.get("elite", false)):
		return base * 1.25
	return base * 1.55


# ---------- 动作清单 ----------

## 动作条目统一结构：{label, anims(动画池), kind(attack/skill/act/passive/enemy_atk/transform), src}
## anims 只放一条 = 单变式；放多条 = 点开后用 ↑ / ↓ 手动切换
func _form_actions(p: Dictionary) -> Array:
	var out: Array = []
	var atks: Array = p.get("attacks", [])
	for i in atks.size():
		var a: Dictionary = atks[i]
		out.append({"label": "普攻 %d" % (i + 1), "anims": _anims_of(a), "kind": "attack", "src": a})
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
			"anims": (pool as Array).duplicate(),
			"kind": "skill", "src": cfg,
		})
	var map: Dictionary = p.get("anim", {})
	for act in ACT_ORDER:
		if map.has(act):
			out.append({"label": str(ACT_LABEL.get(act, act)), "anims": [str(map[act])], "kind": "act", "src": {}})
	# 被动技能栏：每个角色都留一格，内容等第 6 阶段统一设计
	out.append({"label": "被 动", "anims": [], "kind": "passive", "src": {}})
	return out


func _enemy_actions(t: Dictionary, is_boss: bool, id: String) -> Array:
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

	for i in names.size():
		var n := str(names[i])
		var attack_names: Dictionary = ENEMY_ATTACK_NAMES.get(id, {})
		out.append({"label": str(attack_names.get(n, "招式 %d" % (i + 1))), "anims": [n], "kind": "enemy_atk", "src": t, "id": id})

	var map: Dictionary = t.get("anim", {})
	for act in ENEMY_ACT_ORDER:
		if map.has(act):
			out.append({"label": str(ACT_LABEL.get(act, act)), "anims": [str(map[act])], "kind": "act", "src": {}})

	if is_boss:
		for st in t.get("stages", []):
			var tf := str(st.get("transform", ""))
			if tf != "":
				out.append({"label": "变身", "anims": [tf], "kind": "transform", "src": st})
				break
	var passive: Dictionary = ENEMY_PASSIVES.get(id, {})
	out.append({"label": str(passive.get("name", "被 动")), "anims": [], "kind": "passive", "src": {"id": id}})
	return out


func _anims_of(a: Dictionary) -> Array:
	if a.has("pool"):
		var pool: Array = a["pool"]
		if not pool.is_empty():
			return (pool as Array).duplicate()
	if a.has("anim"):
		return [str(a["anim"])]
	return []


## 过滤骨架里不存在的动画（变式池里缺的单独剔掉，不影响整条技能）
func _trim_anims(a: Dictionary, anims: Dictionary) -> bool:
	if str(a["kind"]) == "passive":
		return true
	var keep: Array = []
	for nm in a["anims"]:
		if anims.has(str(nm)):
			keep.append(str(nm))
	if keep.is_empty():
		return false
	a["anims"] = keep
	return true


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
	var parts: Array = ["%d 伤" % dmg]
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


## 技能数值：伤害 / 治疗 / 强化 / 时停 / 远程（冷却单列一行）
func _skill_num(cfg: Dictionary) -> String:
	var parts: Array = []
	if cfg.has("heal"):
		parts.append("回血 %d" % int(cfg["heal"]))
	if cfg.has("buff_damage"):
		parts.append("加伤 +%d / %ds" % [int(cfg["buff_damage"]), int(cfg.get("buff_time", 0))])
	if cfg.has("tick"):
		var tick: Dictionary = cfg["tick"]
		parts.append("转击 %d 伤 / %.2fs" % [int(tick.get("damage", 1)), float(tick.get("interval", 0.5))])
	var dmg := 0
	var cnt := 0
	for h in cfg.get("hits", []):
		if typeof(h) == TYPE_DICTIONARY and (h as Dictionary).has("damage"):
			dmg = maxi(dmg, int((h as Dictionary)["damage"]))
			cnt += 1
	if dmg == 0 and cfg.has("damage"):
		dmg = int(cfg["damage"]) # 单段技能（hit_at 按动画查表）的伤害写在 cfg 顶层
	if dmg > 0:
		parts.append("%d 伤%s" % [dmg, (" ×%d" % cnt) if cnt > 1 else ""])
	if cfg.has("stop"):
		parts.append("时停")
	for h in cfg.get("hits", []):
		if typeof(h) == TYPE_DICTIONARY and (h as Dictionary).has("projectile"):
			parts.append("远程")
			break
	if cfg.has("projectile"):
		parts.append("远程")
	if cfg.has("awaken_time"):
		parts.append("觉醒 %ds" % int(cfg["awaken_time"]))
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
	if bool(cfg.get("require_buff", false)):
		tags.append("觉醒限定")
	if bool(cfg.get("full_screen", false)):
		tags.append("全屏伤害")
	if cfg.has("room_buff"):
		tags.append("每房一次强化")
	# 命中追加效果：叠流血 / 命中定身 / 命中晕眩 / 命中中毒 / 自身金钟罩
	var bleed := false
	var root := false
	var stun := false
	var poison := false
	var shield := false
	for h in cfg.get("hits", []):
		if typeof(h) != TYPE_DICTIONARY:
			continue
		if int((h as Dictionary).get("bleed", 0)) > 0:
			bleed = true
		if float((h as Dictionary).get("stun", 0.0)) > 0.0:
			stun = true
		if float((h as Dictionary).get("poison", 0.0)) > 0.0:
			poison = true
		if (h as Dictionary).has("self_shield"):
			shield = true
		var proj = (h as Dictionary).get("projectile", null)
		if typeof(proj) == TYPE_DICTIONARY and float((proj as Dictionary).get("root", 0.0)) > 0.0:
			root = true
		if float((h as Dictionary).get("root", 0.0)) > 0.0:
			root = true
	if int(cfg.get("bleed", 0)) > 0:
		bleed = true # 池技能（hit_at 按动画查表）的 bleed 写在 cfg 顶层
	if bleed:
		tags.append("命中叠流血")
	if root:
		tags.append("命中定身")
	if stun:
		tags.append("命中晕眩")
	if poison:
		tags.append("命中中毒")
	if shield:
		tags.append("自身金钟罩")
	return " · ".join(tags)


## 敌人招式数值：段数 / 命中时刻 / 射程 / 伤害（按 t 的查表逐条取）
func _enemy_num(t: Dictionary, anim: String) -> String:
	var parts: Array = []
	var hit_at: Dictionary = t.get("hit_at", {})
	var ranges: Dictionary = t.get("ranges", {})
	var damage: Dictionary = t.get("damage", {})
	if hit_at.has(anim):
		var h = hit_at[anim]
		if typeof(h) == TYPE_ARRAY:
			parts.append("%d 段" % (h as Array).size())
		else:
			parts.append("%.2fs" % float(h))
	if ranges.has(anim):
		var r = ranges[anim]
		if typeof(r) == TYPE_ARRAY:
			parts.append("%dpx" % int((r as Array)[0]))
		else:
			parts.append("%dpx" % int(r))
	parts.append("%d 伤" % int(damage.get(anim, 1)))
	if (t.get("both", {}) as Dictionary).has(anim):
		parts.append("前后判定")
	return " ｜ ".join(parts)


func _num_for(a: Dictionary, anim: String) -> String:
	match str(a["kind"]):
		"attack":
			return _attack_num(a["src"], anim)
		"skill":
			return _skill_num(a["src"])
		"enemy_atk":
			return _enemy_num(a["src"], anim)
	return ""


func _mech_for(a: Dictionary) -> String:
	match str(a["kind"]):
		"attack":
			return _attack_desc(a["src"])
		"skill":
			return _skill_desc(a["src"])
		"enemy_atk":
			var anim := str((a["anims"] as Array)[0])
			return str((ENEMY_ATTACK_MECH.get(str(a.get("id", "")), {}) as Dictionary).get(anim, "出招时刻即判定命中"))
		"transform":
			return "血量跌破阶段阈值时的变身演出"
	return ""


func _cd_for(a: Dictionary) -> float:
	if str(a["kind"]) == "skill":
		return float((a["src"] as Dictionary).get("cooldown", 0.0))
	return 0.0


# ---------- 演示 / 动作按钮 ----------

func _make_preview(data, view_scale: float, idle: String) -> void:
	var sprite = ClassDB.instantiate("SpineSprite")
	add_child(sprite)
	sprite.set("skeleton_data_res", data)
	data.call("set_default_mix", 0.0 if _tab == TAB_ENEMY and _sel == "c016" else 0.2)
	sprite.scale = Vector2(view_scale, view_scale)
	sprite.position = Vector2(SPRITE_X, SPRITE_Y)
	_preview = sprite
	if _tab == TAB_ENEMY and _sel == "c016":
		_pose_mixer = SpinePoseMixer.new(sprite)
	_idle_anim = idle
	_play(idle)


func _anim_names(data) -> Dictionary:
	var out := {}
	for a in data.call("get_animations"):
		out[str(a.call("get_name"))] = true
	return out


func _make_action_button(a: Dictionary, i: int) -> void:
	var b := TextureButton.new()
	b.texture_normal = InkTex.load("res://art/ui/menu/btn_normal.png")
	b.texture_hover = InkTex.load("res://art/ui/menu/btn_clicked.png")
	b.texture_pressed = InkTex.load("res://art/ui/menu/btn_clicked.png")
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.size = Vector2(BTN_W, BTN_H)
	b.position = Vector2(BTN_X + (i % BTN_COLS) * (BTN_W + BTN_GAP), BTN_Y + int(i / BTN_COLS) * BTN_STEP_Y)
	b.pressed.connect(_pick.bind(i))
	b.mouse_entered.connect(_on_btn_hover.bind(i))
	b.mouse_exited.connect(_on_btn_unhover.bind(i))
	add_child(b)

	# 选中反馈：左缘一道朱砂细条
	var bar := ColorRect.new()
	bar.color = RED
	bar.size = Vector2(4, BTN_H)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.visible = false
	b.add_child(bar)

	var l := Label.new()
	l.text = str(a["label"])
	l.size = Vector2(BTN_W, BTN_H)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", PAPER)
	l.add_theme_font_size_override("font_size", 14)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(l)

	_act_btns.append(b)
	_act_bars.append(bar)
	_act_labels.append(l)


## 点击某条动作：演示台播它的动画，解析面板写对应资料；多变式由 ↑ / ↓ 手动切换
func _pick(i: int) -> void:
	if i < 0 or i >= _acts.size():
		return
	var a: Dictionary = _acts[i]
	_pick_idx = i
	_pool = a["anims"]
	_pool_i = 0
	_click_sfx()

	var anim := _idle_anim
	if str(a["kind"]) != "passive" and not _pool.is_empty():
		anim = str(_pool[0])
	_play(anim)
	_desc_rt.text = _desc_text(a, anim)
	_refresh_btns()


## 上 / 下键在当前动作的变式池中循环选择；不自动跳转，选中的动画持续循环播放
func _cycle_pool(step: int) -> void:
	if _pick_idx < 0 or _pool.size() <= 1:
		return
	if _desc_rt == null or not is_instance_valid(_desc_rt):
		return
	_pool_i = posmod(_pool_i + step, _pool.size())
	var anim := str(_pool[_pool_i])
	_play(anim)
	var a: Dictionary = _acts[_pick_idx]
	_desc_rt.text = _desc_text(a, anim)


func _refresh_btns() -> void:
	for i in mini(_act_btns.size(), _act_labels.size()):
		var lit := i == _pick_idx or i == _hover_idx
		_act_bars[i].visible = i == _pick_idx
		var tex := "res://art/ui/menu/btn_clicked.png" if lit else "res://art/ui/menu/btn_normal.png"
		(_act_btns[i] as TextureButton).texture_normal = InkTex.load(tex)
		# 亮底（选中 / 悬停）必须转墨字，否则白底白字看不清
		(_act_labels[i] as Label).add_theme_color_override("font_color", INK if lit else PAPER)


func _on_btn_hover(i: int) -> void:
	_hover_idx = i
	_refresh_btns()


func _on_btn_unhover(i: int) -> void:
	if _hover_idx == i:
		_hover_idx = -1
		_refresh_btns()


## 解析面板文案：标题（含变式 x/n 与切换提示）+ 数值 / 机制 / 冷却 / 来历
func _desc_text(a: Dictionary, anim: String) -> String:
	var lines: Array = []
	var head := "[b]%s[/b]" % str(a["label"])
	var pool: Array = a["anims"]
	if pool.size() > 1:
		head += "  [color=#b07a2c]· 变式 %d/%d · ↑ / ↓ 切换[/color]" % [_pool_i + 1, pool.size()]
	lines.append(head)

	var kind := str(a["kind"])
	if kind == "passive":
		var passive: Dictionary = ENEMY_PASSIVES.get(str((a["src"] as Dictionary).get("id", "")), {})
		if not passive.is_empty():
			lines.append("[color=#a8332a]被动技能 · 山民[/color]")
			lines.append("[color=#8a857a]机制：[/color]" + str(passive["desc"]))
			lines.append("[color=#8a857a]来历：[/color]" + str(passive["lore"]))
		else:
			lines.append("[color=#a8332a]被动技能 · 【待定】[/color]")
			lines.append("[color=#8a857a]每个角色预留一格，内容等第 6 阶段统一设计。[/color]")
		return "\n".join(lines)
	if kind == "act":
		lines.append("[color=#8a857a]角色通用动作，仅作演示。[/color]")
		return "\n".join(lines)
	if kind == "transform":
		lines.append("[color=#8a857a]机制：[/color]" + _mech_for(a))
		lines.append("[color=#8a857a]来历：[/color]【待定】")
		return "\n".join(lines)

	var num := _num_for(a, anim)
	if num != "":
		lines.append("[color=#8a857a]数值：[/color]" + num)
	var mech := _mech_for(a)
	if mech != "":
		lines.append("[color=#8a857a]机制：[/color]" + mech)
	var cd := _cd_for(a)
	if cd > 0.0:
		lines.append("[color=#8a857a]冷却：[/color]%.1f 秒" % cd)
	var origin := "【待定】"
	if kind == "enemy_atk":
		origin = str((ENEMY_ATTACK_LORE.get(str(a.get("id", "")), {}) as Dictionary).get(anim, origin))
	lines.append("[color=#8a857a]来历：[/color]" + origin)
	return "\n".join(lines)


func _process(delta: float) -> void:
	if _pose_mixer == null or _preview == null or not is_instance_valid(_preview):
		return
	var step := delta
	if not _pending_anim.is_empty():
		var st = _preview.call("get_animation_state")
		st.call("set_animation", _pending_anim, true, 0)
		_pending_anim = ""
		step = 0.0
	_pose_mixer.update(step)


func _play(anim: String) -> void:
	if _preview == null or not is_instance_valid(_preview) or anim == "":
		return
	# 重复点击同一动作不重开轨道，避免循环动画回到第 0 帧造成肉眼可见的一抽。
	if anim == _current_anim:
		return
	_current_anim = anim
	var st = _preview.call("get_animation_state")
	if st == null:
		return
	if _pose_mixer != null:
		_pose_mixer.capture()
		_pending_anim = anim
		return
	st.call("set_animation", anim, true, 0) # 循环播：停在该动作上就一直演


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

func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0.34)
	s.border_color = Color(1, 1, 1, 0.2)
	s.set_border_width_all(1)
	s.set_corner_radius_all(4)
	s.content_margin_left = 10
	s.content_margin_right = 8
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


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
