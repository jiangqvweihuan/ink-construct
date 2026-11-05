extends Node2D

## 特效 / 音频 / 技能链路独立查看器，不参与正式游戏场景。
## 1：每个 Spine 动画逐项预览；2：每条音频独立试听；3：舜华斩真实时序演示。

const SpineFX := preload("res://scripts/systems/spine_fx.gd")
const Skulls := preload("res://scripts/player/skulls.gd")
const Inventory := preload("res://scripts/tests/spine_fx_test.gd")

const PAPER := Color(0.949, 0.918, 0.847)
const INK := Color(0.075, 0.072, 0.078)
const DIM := Color(0.39, 0.37, 0.34)
const RED := Color(0.66, 0.2, 0.16)
const GOLD := Color(0.82, 0.64, 0.25)
const STAGE_DARK := Color(0.105, 0.11, 0.125)
const STAGE_ORIGIN := Vector2(800, 420)
const DEMO_START := Vector2(480, 540)
const DEMO_TARGET := Vector2(800, 540)
const DEMO_DASH_FROM := 0.15
const DEMO_DASH_TO := 0.90
const DEMO_HIT_AT := 0.95
const DEMO_DASH_SPEED := 800.0

const FX_USAGE := {
	"E54156": "全体敌人｜魅惑状态（苏挽音·摄心）｜头顶持续特效",
	"E54151": "冷红绫（双刺）｜U 红缨缚雁｜技能期间随身持续特效",
	"E54148": "青魇剑主｜魔爆亡语｜前扑判定范围内贴地火焰爆裂，与实伤同帧",
	"E54110": "焚鼎｜炎骨觉醒｜觉醒期间随身持续特效",
	"E54083": "洛惊鸿（剑仙）｜U 穿透剑气（skill04）｜action1 飞行 / action3 首击 / action2 续击",
	"E54063": "定山（力僧）｜K 钟荡群山｜横扫命中的地裂，宽度随技能范围",
	"E54061": "苏挽音（绛弦）｜固有被动·神伤｜每 30 秒全房伤害时横向展开",
	"E54056": "苏挽音（绛弦）｜普攻第四段·余音入魔｜魔音真实命中特效",
	"E54055": "苏挽音（绛弦）｜普攻第四段·余音入魔｜魔音飞行特效",
	"E54054": "将去未还（影殇）｜P 天倾触发固有被动·魅唤｜协助者现身",
	"E54015": "冷红绫（双刺）｜固有被动·红蝶｜致命伤复活特效",
	"E54012": "将去未还（影殇）｜O 舜华斩 / P 天倾｜见当前动画的精确用途",
	"E53201": "定山（力僧）｜L 金刚怒目｜落点打击特效，宽度随技能范围",
	"E53174": "苏挽音（绛弦）｜I 红尘劫｜觉醒起手一次性特效",
	"E53038": "焚鼎｜炎起｜三处预警点岩浆喷发",
	"E53026": "冷红绫、定山、白疏影、洛惊鸿、苏挽音、将去未还｜Shift 闪避身后残影",
	"E53009": "苏挽音（绛弦）｜O 八音断识｜与 E53008 随机出现的视觉音波",
	"E53008": "苏挽音（绛弦）｜O 八音断识｜与 E53009 随机出现的视觉音波",
	"E52025": "全体角色｜金钟罩持续状态｜含定山·钟荡群山与敌方护罩",
	"E52007": "全体敌人｜癫狂状态｜余音入魔 / 黍离 / 众生同狂等",
	"E52000": "全体敌人｜眩晕状态｜金刚怒目 / 千锋回雪 / 剑奉山河等",
	"E50127": "全体敌人｜中毒状态｜白疏影·梅间回雪等",
	"E50041": "通用结算界面｜最后一击展示｜不绑定单个实体",
	"E100186": "将去未还（影殇）｜I 长夜明火｜觉醒起手身后特效",
	"E100182": "定山（力僧）｜U 立地听禅｜技能起手头顶佛像（K/L 不显示）",
	"E100180": "通用火球投射物管线（style=fireball）｜飞行动画｜未绑定单一专属技能",
	"E100177": "洛惊鸿（剑仙）｜I 一剑惊鸿｜觉醒期间随身持续特效",
	"E100172": "苏挽音（绛弦）｜I 红尘劫｜觉醒期间随身持续特效",
	"E100129": "苏挽音（绛弦）｜L 黍离｜穿透魔音飞行特效",
	"E54068": "通用界面｜鼠标点击反馈｜使用 action1，不绑定战斗实体或技能",
	"E100006": "将去未还（影殇）｜U 万籁停晷 / P 天倾｜世界或随身持续特效",
	"E21105": "将去未还（影殇）｜I 长夜明火｜觉醒期间随身持续特效",
	"E21022": "全体首领｜Boss 对峙入场｜全屏覆盖特效",
	"E21019": "精英与首领图鉴｜收录奖章｜不绑定技能",
	"E21013": "通用结算界面｜win 胜利 / lose 失败｜不绑定单个实体",
}

const FX_ANIM_USAGE := {
	"E54012/action1": "将去未还（影殇）｜O 舜华斩｜0.95 秒在每个路径命中目标身上生成，实战 scale=0.35",
	"E54012/action3": "将去未还（影殇）｜P 天倾｜全屏伤害时按视口覆盖并居中",
	"E54083/action1": "洛惊鸿（剑仙）｜U 穿透剑气｜飞行循环，实战 scale=0.35",
	"E54083/action2": "洛惊鸿（剑仙）｜U 穿透剑气｜后续目标命中，实战 scale=0.35",
	"E54083/action3": "洛惊鸿（剑仙）｜U 穿透剑气｜首个目标命中，实战 scale=0.35",
	"E21013/win": "通用结算界面｜通关胜利徽章",
	"E21013/lose": "通用结算界面｜战败徽章",
	"E21019/boss": "全体首领图鉴｜首领收录奖章",
	"E21019/elite": "精英图鉴｜精英收录奖章",
}

## 多动画素材里只列真实调用；其余动作在浏览时明确标成“仅素材，未接入”。
const USED_FX_ANIMS := {
	"E54151": ["action1"],
	"E54110": ["action1"],
	"E54063": ["action1"],
	"E54068": ["action1"],
	"E54012": ["action1", "action3"],
	"E53038": ["action1"],
	"E52025": ["action1"],
	"E21019": ["boss", "elite"],
	"E21013": ["win", "lose"],
}

const AUDIO_USAGE := {
	"assassin_basic_attack": "冷红绫（双刺）｜绛衣试水 / 回燕剪翎 / 红绫卷霜｜普攻起手",
	"assassin_projectile": "冷红绫（双刺）｜U 红缨缚雁｜匕首出手",
	"weapon_blade": "白疏影（梅剑）｜疏枝引鹤起手；梅间回雪持续循环",
	"monk_basic_attack": "定山（力僧）｜撞钟 / 碎磐｜普攻起手",
	"monk_bell_quake": "定山（力僧）｜K 钟荡群山｜技能起手",
	"monk_vajra_wrath": "定山（力僧）｜L 金刚怒目｜0.80 秒招式事件",
	"monk_meditation": "定山（力僧）｜U 立地听禅｜技能起手",
	"swordsman_swift_slash": "洛惊鸿（剑仙）｜I 一剑惊鸿｜觉醒技能起手",
	"pipa_string_step": "苏挽音（绛弦）｜K 踏弦｜技能起手",
	"pipa_taiyu": "苏挽音（绛弦）｜L 黍离｜技能起手",
	"pipa_mind_snare": "苏挽音（绛弦）｜U 摄心 / 觉醒·众生同狂｜技能起手",
	"pipa_mortal_tribulation": "苏挽音（绛弦）｜I 红尘劫｜觉醒技能起手",
	"pipa_eight_tones": "苏挽音（绛弦）｜O 八音断识｜技能期间循环",
	"pipa_inner_demon": "苏挽音（绛弦）｜P 心魔引｜技能起手",
	"jiangqu_silence": "将去未还（影殇）｜U 万籁停晷｜技能起手",
	"jiangqu_hibiscus_slash": "将去未还（影殇）｜O 舜华斩｜0.00 秒起手音；不是冲刺后的命中音",
	"hit_heavy": "重击命中｜将去未还·舜华斩（0.95 秒）；洛惊鸿·穿透剑气；白疏影·疏枝引鹤等",
	"skill_blade": "刀刃技能命中｜冷红绫·罗刹旋舞/红缨缚雁；白疏影·梅间回雪；洛惊鸿·月华斩/剑奉山河；将去未还·崩云等",
	"skill_fist": "重招命中｜冷红绫·罗刹旋舞；定山·钟荡群山；洛惊鸿·惊鸿燕返等",
	"skill_boom": "爆发/状态结算｜定山·钟荡群山；苏挽音·众生同狂/八音断识/心魔引/神伤；将去未还·天倾等",
	"voice_fan_hit": "多化身技能命中｜罗刹旋舞 / 金刚怒目 / 千锋回雪 / 剑奉山河 / 飞星送客等",
	"voice_skill_cast": "通用技能起手与特定技能事件｜苏挽音·黍离/摄心；洛惊鸿·剑奉山河等",
	"dash_step": "全部化身｜Shift 普通闪避；将去未还·去来返程｜注意：O 舜华斩不调用此音",
	"player_footstep": "全部玩家化身｜奔跑脚步",
	"weapon_sword": "通用刀剑起手与完美闪避擦身声｜按实际攻击配置调用",
	"golden_bell_block": "全体角色｜金钟罩成功抵挡攻击",
	"heal": "全体玩家化身｜生命恢复",
	"fire_burst": "焚鼎｜火焰技能爆发",
	"mo_ting_slam": "墨霆｜砸地技能",
	"boss_entrance": "首领战｜Boss 入场",
	"boss_skill_hit": "首领技能｜命中反馈",
	"telegraph": "敌人与首领｜招式预警",
	"player_hurt_blunt": "玩家｜钝击受击",
	"player_hurt_sharp": "玩家｜锐器受击",
	"voice_sword_hit": "通用近战｜刀剑命中",
	"voice_flyblade_hit": "通用投射物｜飞刃命中",
	"hit_flyblade": "通用投射物｜飞刃命中",
	"hit_light": "通用战斗｜轻击命中",
	"hit_fist": "通用战斗｜拳击/钝击命中",
	"hit_qi": "通用战斗｜气劲命中",
	"hit_fan": "通用战斗｜扇击命中",
	"skill_poison": "通用状态｜中毒触发",
	"click": "通用界面｜按钮点击",
	"ui_back": "通用界面｜返回",
	"ui_start_open": "开始界面｜打开",
	"shop_open": "商店｜打开",
	"shop_purchase": "商店｜购买",
	"swap_draw": "化身抽取/替换｜抽取反馈",
	"meta_upgrade_01": "局外修炼｜升级反馈（随机一）",
	"meta_upgrade_02": "局外修炼｜升级反馈（随机二）",
	"level_up": "局内成长｜升级",
	"room_reward": "房间结算｜奖励出现",
	"settle": "通用结算｜结算出现",
	"win": "通用结算｜胜利",
	"lose": "通用结算｜失败",
	"run_embark": "开局｜启程",
	"gold": "通用经济｜获得金钱",
	"pickup": "通用拾取｜获得物品",
	"loot_pickup": "通用掉落｜拾取战利品",
	"decor_pickup": "互动物件｜拾取",
	"decor_stele": "互动物件｜石碑触发",
}

var _page := 0
var _loop := true
var _zoom := 2.2
var _fx_entries: Array = []
var _audio_entries: Array = []
var _fx_index := 0
var _audio_index := 0
var _current_fx: Node2D
var _audio_player: AudioStreamPlayer
var _demo_audio: AudioStreamPlayer
var _audio_loop := false
var _failures := 0

var _tabs: Array[Button] = []
var _list: ItemList
var _count_label: Label
var _title_label: Label
var _usage_label: Label
var _meta_label: Label
var _stage_note: Label
var _status_label: Label
var _hint_label: Label
var _play_button: Button
var _loop_button: Button
var _stop_button: Button
var _progress: ProgressBar
var _dynamic_root: Node2D
var _stage_cross: Node2D

var _demo_player: Node2D
var _demo_sprite
var _demo_state
var _demo_target: Node2D
var _demo_target_status: Label
var _demo_effects: Node2D
var _demo_event_label: Label
var _demo_time_label: Label
var _demo_marker: ColorRect
var _demo_time := 0.0
var _demo_duration := 1.2
var _demo_distance := 0.0
var _demo_running := false
var _demo_hold := 0.0
var _demo_hit_done := false
var _demo_dash_started := false
var _demo_dash_ended := false
var _demo_audio_log: Array[String] = []
var _demo_spine_hit: Node2D


func _ready() -> void:
	_build_inventory()
	_build_ui()
	for bus_name in ["SFX", "Music"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			var bus_index := AudioServer.bus_count
			AudioServer.add_bus(bus_index)
			AudioServer.set_bus_name(bus_index, bus_name)
			AudioServer.set_bus_send(bus_index, "Master")
	_audio_player = AudioStreamPlayer.new()
	_audio_player.bus = "SFX"
	add_child(_audio_player)
	_audio_player.finished.connect(_on_audio_finished)
	_demo_audio = AudioStreamPlayer.new()
	_demo_audio.bus = "SFX"
	add_child(_demo_audio)
	_switch_page(0)
	if "--self-test" in OS.get_cmdline_user_args() or "--shot" in OS.get_cmdline_user_args():
		call_deferred("_run_auto_test")


func _build_inventory() -> void:
	for id in Inventory.IDS:
		var data = SpineFX.data(str(id))
		if data == null:
			push_error("预览器：特效加载失败 " + str(id))
			continue
		for animation in data.call("get_animations"):
			_fx_entries.append({
				"id": str(id), "anim": str(animation.call("get_name")),
				"duration": float(animation.call("get_duration")), "data": data,
			})
	for kind in ["sfx", "music"]:
		var dir_path: String = "res://audio/" + kind
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		var files: Array[String] = []
		for file in dir.get_files():
			if file.ends_with(".wav"):
				files.append(file)
		files.sort()
		for file in files:
			_audio_entries.append({
				"id": file.get_basename(), "path": dir_path.path_join(file),
				"kind": "SFX" if kind == "sfx" else "BGM",
			})
	print("[FXAV] 特效动画 %d 项 / 骨架 %d 组；音频 %d 条" % [_fx_entries.size(), Inventory.IDS.size(), _audio_entries.size()])


func _build_ui() -> void:
	_rect(self, Vector2.ZERO, Vector2(1280, 720), PAPER, -100)
	_label("骨骼特效 · 音频 · 技能链路", Vector2(22, 16), 27, INK, 390)
	for i in 3:
		var names := ["1  特效动画", "2  音频试听", "3  舜华斩演示"]
		var button := _button(names[i], Vector2(470 + i * 205, 18), Vector2(190, 42), _switch_page.bind(i))
		_tabs.append(button)
	_count_label = _label("", Vector2(22, 84), 15, DIM, 315)
	_list = ItemList.new()
	_list.position = Vector2(20, 112)
	_list.size = Vector2(320, 530)
	_list.add_theme_font_size_override("font_size", 16)
	_list.add_theme_color_override("font_color", INK)
	_list.add_theme_color_override("font_selected_color", Color.WHITE)
	_list.add_theme_stylebox_override("selected", _style(RED, 5))
	_list.add_theme_stylebox_override("selected_focus", _style(RED, 5))
	_list.item_selected.connect(_on_item_selected)
	add_child(_list)
	_title_label = _label("", Vector2(366, 80), 25, INK, 885)
	_usage_label = _label("", Vector2(366, 119), 17, RED, 885)
	_usage_label.custom_minimum_size.y = 58
	_meta_label = _label("", Vector2(366, 178), 14, DIM, 885)
	_rect(self, Vector2(360, 215), Vector2(900, 350), STAGE_DARK, -5)
	_stage_note = _label("", Vector2(378, 226), 13, Color(0.72, 0.72, 0.70), 450)
	_status_label = _label("", Vector2(800, 228), 15, Color(0.86, 0.82, 0.72), 440)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_progress = ProgressBar.new()
	_progress.position = Vector2(370, 582)
	_progress.size = Vector2(880, 12)
	_progress.show_percentage = false
	_progress.max_value = 1.0
	add_child(_progress)
	_demo_marker = _rect(self, Vector2(370, 576), Vector2(3, 24), GOLD, 20)
	_play_button = _button("空格  重播", Vector2(370, 615), Vector2(160, 38), _replay)
	_loop_button = _button("L  循环：开", Vector2(545, 615), Vector2(160, 38), _toggle_loop)
	_stop_button = _button("停止音频", Vector2(720, 615), Vector2(145, 38), _stop_audio)
	_hint_label = _label("↑ ↓ 选择条目    空格 重播/试听    L 循环    + / - 特效缩放    1 / 2 / 3 切页", Vector2(22, 674), 15, DIM, 1220)
	_dynamic_root = Node2D.new()
	_dynamic_root.z_index = 5
	add_child(_dynamic_root)
	_build_stage_cross()


func _build_stage_cross() -> void:
	_stage_cross = Node2D.new()
	_stage_cross.z_index = -1
	add_child(_stage_cross)
	_line(_stage_cross, [Vector2(390, STAGE_ORIGIN.y), Vector2(1230, STAGE_ORIGIN.y)], Color(1, 1, 1, 0.08), 1.0)
	_line(_stage_cross, [Vector2(STAGE_ORIGIN.x, 250), Vector2(STAGE_ORIGIN.x, 545)], Color(1, 1, 1, 0.08), 1.0)
	_line(_stage_cross, [Vector2(390, 548), Vector2(1230, 548)], Color(0.82, 0.64, 0.25, 0.32), 2.0)


func _switch_page(page: int) -> void:
	_page = page
	_stop_audio()
	_demo_audio.stop()
	_demo_running = false
	_clear_dynamic()
	_stage_cross.visible = page != 2
	_demo_marker.visible = page == 2
	_progress.visible = page != 0
	_stop_button.visible = page == 1
	_play_button.text = "空格  重播" if page != 1 else "空格  试听"
	_list.clear()
	if page == 0:
		for entry in _fx_entries:
			_list.add_item("%s   /   %s" % [entry["id"], entry["anim"]])
		_stage_note.text = "单个骨骼动画实时渲染 · 中央十字为定位参考"
		_fx_index = _find_fx("E54012", "action1")
	elif page == 1:
		for entry in _audio_entries:
			_list.add_item("[%s]  %s" % [entry["kind"], entry["id"]])
		_stage_note.text = "独立 AudioStreamPlayer · 不经过游戏技能逻辑"
		_audio_index = _find_audio("jiangqu_hibiscus_slash")
	else:
		_list.add_item("将去未还  /  O  舜华斩  /  skill11")
		_list.add_item("起手音  /  jiangqu_hibiscus_slash")
		_list.add_item("命中音  /  hit_heavy")
		_list.add_item("目标特效  /  E54012 action1")
		_stage_note.text = "真实技能配置时序 · 角色 skill11 · 世界坐标 1:1"
		_build_demo()
	for i in _tabs.size():
		_tabs[i].modulate = Color.WHITE if i == page else Color(0.65, 0.62, 0.58)
	if page == 0:
		_select_and_show(_fx_index)
	elif page == 1:
		_select_and_show(_audio_index)
	else:
		_list.select(0)
		_title_label.text = "将去未还（影殇）｜O 舜华斩"
		_usage_label.text = "起手音 jiangqu_hibiscus_slash → 0.15–0.90 秒突进 600px → 0.95 秒路径命中"
		_meta_label.text = "skill11｜8 伤 + 2 层流血｜每目标 E54012/action1｜命中音 hit_heavy｜O 无 dash_step"
		_status_label.text = "空格可重播完整链路"
		_progress.max_value = maxf(1.2, _demo_duration)
		_start_demo()


func _select_and_show(index: int) -> void:
	if _list.item_count == 0:
		return
	var safe := clampi(index, 0, _list.item_count - 1)
	_list.select(safe)
	_list.ensure_current_is_visible()
	_on_item_selected(safe)


func _on_item_selected(index: int) -> void:
	if _page == 0:
		_fx_index = index
		_show_fx()
	elif _page == 1:
		_audio_index = index
		_show_audio()
	elif index > 0:
		# 演示页的三条说明也可直接定位到对应素材/音频。
		if index == 1:
			_switch_page(1)
			_select_and_show(_find_audio("jiangqu_hibiscus_slash"))
		elif index == 2:
			_switch_page(1)
			_select_and_show(_find_audio("hit_heavy"))
		elif index == 3:
			_switch_page(0)
			_select_and_show(_find_fx("E54012", "action1"))


func _show_fx() -> void:
	if _fx_entries.is_empty():
		return
	if is_instance_valid(_current_fx):
		_current_fx.queue_free()
	var entry: Dictionary = _fx_entries[_fx_index]
	var key := "%s/%s" % [entry["id"], entry["anim"]]
	_title_label.text = "%s   /   %s" % [entry["id"], entry["anim"]]
	_usage_label.text = "应用实体 / 技能：" + _fx_usage(entry, key)
	_meta_label.text = "动画 %d/%d｜时长 %.3f 秒｜预览缩放 %.3f（基准 %.3f × %.2f）｜%s" % [
		_fx_index + 1, _fx_entries.size(), float(entry["duration"]),
		float(Inventory.THUMB_SCALE[entry["id"]]) * _zoom,
		float(Inventory.THUMB_SCALE[entry["id"]]), _zoom, "循环" if _loop else "单次播完停留"]
	_status_label.text = "%d / %d" % [_fx_index + 1, _fx_entries.size()]
	_current_fx = SpineFX.spawn(_dynamic_root, str(entry["id"]), STAGE_ORIGIN, {
		"anim": str(entry["anim"]), "scale": float(Inventory.THUMB_SCALE[entry["id"]]) * _zoom,
		"center": true, "loop": _loop, "auto_free": false,
	})


func _fx_usage(entry: Dictionary, key: String) -> String:
	if FX_ANIM_USAGE.has(key):
		return str(FX_ANIM_USAGE[key])
	if USED_FX_ANIMS.has(entry["id"]) and not USED_FX_ANIMS[entry["id"]].has(entry["anim"]):
		return "仅素材动画｜当前实战未调用；同组已用动画请查看对应条目"
	return str(FX_USAGE.get(entry["id"], "仅素材预览｜当前未登记实战应用"))


func _show_audio() -> void:
	if _audio_entries.is_empty():
		return
	_stop_audio()
	var entry: Dictionary = _audio_entries[_audio_index]
	_title_label.text = "%s   /   %s" % [entry["kind"], entry["id"]]
	_usage_label.text = "应用实体 / 技能 / 时点：" + _audio_usage(entry)
	var stream = load(str(entry["path"]))
	var duration := float(stream.call("get_length")) if stream != null else 0.0
	_meta_label.text = "%s｜时长 %.3f 秒｜总线 %s｜音频 %d/%d" % [entry["path"], duration, entry["kind"], _audio_index + 1, _audio_entries.size()]
	_audio_player.bus = "SFX" if entry["kind"] == "SFX" else "Music"
	_audio_player.stream = stream
	_progress.max_value = maxf(0.001, duration)
	_progress.value = 0.0
	_status_label.text = "正在播放" if stream != null else "加载失败"
	_status_label.add_theme_color_override("font_color", Color(0.86, 0.82, 0.72))
	if stream != null:
		_audio_player.play()
	_big_stage_text(str(entry["id"]), "音频独立试听\n" + str(entry["kind"]))


func _audio_usage(entry: Dictionary) -> String:
	if AUDIO_USAGE.has(entry["id"]):
		return str(AUDIO_USAGE[entry["id"]])
	if entry["kind"] == "BGM":
		return "背景音乐｜由 BGM 管理器按界面或战斗场景切换｜不绑定单个技能"
	return "通用音效｜当前未登记单一实体或专属技能绑定"


func _big_stage_text(main: String, sub: String) -> void:
	var label := _label(main, Vector2(420, 330), 34, Color(0.92, 0.88, 0.78), 740, _dynamic_root)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var detail := _label(sub, Vector2(420, 395), 19, Color(0.65, 0.65, 0.62), 740, _dynamic_root)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _load_z003_data():
	var base := "res://art/characters/player/skulls/z003/skeleton"
	var atlas = ClassDB.instantiate("SpineAtlasResource")
	var atlas_err := int(atlas.call("load_from_atlas_file", base + ".atlas")) if atlas != null else ERR_CANT_CREATE
	var skel = load(base + ".skel")
	if atlas_err != OK or skel == null:
		push_error("舜华斩演示：z003 骨骼加载失败")
		return null
	var data = ClassDB.instantiate("SpineSkeletonDataResource")
	data.call("set_atlas_res", atlas)
	data.call("set_skeleton_file_res", skel)
	data.call("set_default_mix", 0.1)
	return data


func _build_demo() -> void:
	_demo_effects = Node2D.new()
	_demo_effects.z_index = 30
	_dynamic_root.add_child(_demo_effects)
	_line(_dynamic_root, [Vector2(390, 548), Vector2(1230, 548)], Color(0.82, 0.64, 0.25, 0.6), 2.0)
	_line(_dynamic_root, [DEMO_START + Vector2(0, 18), DEMO_START + Vector2(600, 18)], Color(1, 1, 1, 0.18), 2.0)
	var path_label := _label("600px 路径贯穿", Vector2(665, 551), 13, Color(0.65, 0.65, 0.62), 250, _dynamic_root)
	path_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_demo_target = Node2D.new()
	_demo_target.position = DEMO_TARGET
	_dynamic_root.add_child(_demo_target)
	_rect(_demo_target, Vector2(-5, -86), Vector2(10, 86), Color(0.52, 0.38, 0.25), 0)
	_rect(_demo_target, Vector2(-38, -103), Vector2(76, 13), Color(0.62, 0.45, 0.28), 0)
	_rect(_demo_target, Vector2(-28, -138), Vector2(56, 56), Color(0.26, 0.22, 0.19), 0)
	var target_name := _label("前方目标", Vector2(-65, -184), 16, Color(0.92, 0.88, 0.78), 130, _demo_target)
	target_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_demo_target_status = _label("等待命中", Vector2(-100, -218), 18, Color(0.86, 0.72, 0.42), 200, _demo_target)
	_demo_target_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_demo_player = Node2D.new()
	_demo_player.position = DEMO_START
	_dynamic_root.add_child(_demo_player)
	_demo_sprite = ClassDB.instantiate("SpineSprite")
	_demo_player.add_child(_demo_sprite)
	var data = _load_z003_data()
	_demo_sprite.set("skeleton_data_res", data)
	_demo_sprite.scale = Vector2.ONE * float(Skulls.SKULLS["z003"]["scale"])
	_demo_sprite.call("set_update_mode", 2)
	_demo_state = _demo_sprite.call("get_animation_state")
	var animation = data.call("find_animation", "skill11")
	_demo_duration = float(animation.call("get_duration")) if animation != null else 1.2
	_demo_event_label = _label("", Vector2(395, 482), 16, Color(0.92, 0.88, 0.78), 825, _dynamic_root)
	_demo_time_label = _label("", Vector2(1080, 515), 16, Color(0.86, 0.72, 0.42), 150, _dynamic_root)


func _start_demo() -> void:
	if not is_instance_valid(_demo_player):
		return
	for child in _demo_effects.get_children():
		child.queue_free()
	_demo_audio.stop()
	_demo_time = 0.0
	_demo_distance = 0.0
	_demo_hold = 0.0
	_demo_hit_done = false
	_demo_dash_started = false
	_demo_dash_ended = false
	_demo_running = true
	_demo_audio_log.clear()
	_demo_spine_hit = null
	_demo_player.position = DEMO_START
	_demo_target.modulate = Color.WHITE
	_demo_target_status.text = "等待命中"
	_demo_target_status.add_theme_color_override("font_color", Color(0.86, 0.72, 0.42))
	_demo_state.call("set_animation", "skill11", false, 0)
	_demo_sprite.call("update_skeleton", 0.0)
	_demo_sprite.call("force_update_transform")
	_play_demo_sfx("jiangqu_hibiscus_slash")
	_update_demo_text()


func _process(delta: float) -> void:
	if _page == 1 and is_instance_valid(_audio_player) and _audio_player.playing:
		_progress.value = _audio_player.get_playback_position()
	if _page != 2 or not is_instance_valid(_demo_player):
		return
	if _demo_running:
		var previous := _demo_time
		_demo_time += delta
		if not _demo_dash_started and previous < DEMO_DASH_FROM and _demo_time >= DEMO_DASH_FROM:
			_demo_dash_started = true
		var move_from := maxf(previous, DEMO_DASH_FROM)
		var move_to := minf(_demo_time, DEMO_DASH_TO)
		if move_to > move_from:
			_demo_distance = minf(600.0, _demo_distance + DEMO_DASH_SPEED * (move_to - move_from))
		_demo_player.position = DEMO_START + Vector2(_demo_distance, 0)
		if not _demo_dash_ended and previous < DEMO_DASH_TO and _demo_time >= DEMO_DASH_TO:
			_demo_dash_ended = true
		if not _demo_hit_done and previous < DEMO_HIT_AT and _demo_time >= DEMO_HIT_AT:
			_demo_hit()
		_demo_sprite.call("update_skeleton", delta)
		_demo_sprite.call("force_update_transform")
		_progress.value = minf(_demo_time, _progress.max_value)
		_demo_marker.position.x = 370 + 880 * clampf(_demo_time / _progress.max_value, 0.0, 1.0)
		_update_demo_text()
		if _demo_time >= maxf(_demo_duration, 1.2):
			_demo_running = false
	else:
		_demo_hold += delta
		if _loop and _demo_hold >= 1.2:
			_start_demo()


func _demo_hit() -> void:
	_demo_hit_done = true
	_demo_spine_hit = SpineFX.spawn(_demo_effects, "E54012", DEMO_TARGET + Vector2(0, -60), {
		"anim": "action1", "scale": 0.35, "auto_free": true,
	})
	_play_demo_sfx("hit_heavy")
	_demo_target_status.text = "8 伤  ·  流血 × 2"
	_demo_target_status.add_theme_color_override("font_color", Color(1.0, 0.42, 0.32))
	_demo_target.modulate = Color(1.0, 0.65, 0.58)


func _play_demo_sfx(id: String) -> void:
	_demo_audio_log.append(id)
	_demo_audio.stream = load("res://audio/sfx/" + id + ".wav")
	_demo_audio.play()


func _update_demo_text() -> void:
	if _demo_time < DEMO_DASH_FROM:
		_demo_event_label.text = "0.00s  起手：jiangqu_hibiscus_slash"
	elif _demo_time < DEMO_DASH_TO:
		_demo_event_label.text = "0.15–0.90s  突进 800px/s（O 不额外播放 dash_step）"
	elif _demo_time < DEMO_HIT_AT:
		_demo_event_label.text = "0.90s  突进结束；下一命中帧为 0.95s"
	else:
		_demo_event_label.text = "0.95s  命中：E54012/action1；hit_heavy；8 伤 + 2 层流血"
	_demo_time_label.text = "t = %.2fs" % _demo_time
	_status_label.text = "位移 %.0f / 600px" % _demo_distance


func _replay() -> void:
	if _page == 0:
		_show_fx()
	elif _page == 1:
		_show_audio()
	else:
		_start_demo()


func _toggle_loop() -> void:
	if _page == 1:
		_audio_loop = not _audio_loop
	else:
		_loop = not _loop
	_update_loop_text()
	if _page == 0:
		_show_fx()


func _update_loop_text() -> void:
	var enabled := _audio_loop if _page == 1 else _loop
	_loop_button.text = "L  循环：" + ("开" if enabled else "关")


func _stop_audio() -> void:
	if is_instance_valid(_audio_player):
		_audio_player.stop()
	if _page == 1 and is_instance_valid(_status_label):
		_status_label.text = "已停止"


func _on_audio_finished() -> void:
	if _page != 1:
		return
	if _audio_loop:
		_audio_player.play()
	else:
		_status_label.text = "播放完成"


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_1:
			_switch_page(0)
		KEY_2:
			_switch_page(1)
		KEY_3:
			_switch_page(2)
		KEY_SPACE:
			_replay()
		KEY_L:
			_toggle_loop()
		KEY_PLUS, KEY_EQUAL:
			if _page == 0:
				_zoom = minf(4.0, _zoom + 0.1)
				_show_fx()
		KEY_MINUS:
			if _page == 0:
				_zoom = maxf(0.4, _zoom - 0.1)
				_show_fx()
		KEY_UP, KEY_LEFT:
			_step_item(-1)
		KEY_DOWN, KEY_RIGHT:
			_step_item(1)


func _step_item(direction: int) -> void:
	if _page == 2 or _list.item_count == 0:
		return
	var current := _fx_index if _page == 0 else _audio_index
	_select_and_show(wrapi(current + direction, 0, _list.item_count))


func _clear_dynamic() -> void:
	if not is_instance_valid(_dynamic_root):
		return
	for child in _dynamic_root.get_children():
		if child is CanvasItem:
			child.hide()
		child.queue_free()
	_current_fx = null
	_demo_player = null
	_demo_sprite = null
	_demo_state = null
	_demo_target = null
	_demo_effects = null
	_demo_event_label = null
	_demo_time_label = null


func _find_fx(id: String, anim: String) -> int:
	for i in _fx_entries.size():
		if _fx_entries[i]["id"] == id and _fx_entries[i]["anim"] == anim:
			return i
	return 0


func _find_audio(id: String) -> int:
	for i in _audio_entries.size():
		if _audio_entries[i]["id"] == id:
			return i
	return 0


func _run_auto_test() -> void:
	await get_tree().create_timer(0.4).timeout
	var unique: Dictionary = {}
	for i in _fx_entries.size():
		var entry: Dictionary = _fx_entries[i]
		unique[entry["id"]] = true
		_check(entry["data"].call("find_animation", str(entry["anim"])) != null, "%s/%s 动画存在" % [entry["id"], entry["anim"]])
		_select_and_show(i)
		await get_tree().process_frame
		_check(is_instance_valid(_current_fx) and _current_fx.sprite != null, "%s/%s 可生成" % [entry["id"], entry["anim"]])
	_check(unique.size() == 35, "35 组骨骼全部纳入逐项浏览")
	for entry in _audio_entries:
		var stream = load(str(entry["path"]))
		_check(stream != null and float(stream.call("get_length")) > 0.0, "音频可加载 " + str(entry["id"]))
	_check(_find_audio("jiangqu_hibiscus_slash") >= 0 and _find_audio("hit_heavy") >= 0, "舜华斩两条真实音频均已收录")
	_switch_page(0)
	_select_and_show(_find_fx("E54012", "action1"))
	await get_tree().create_timer(0.45).timeout
	await _shot("fx_audio_effects")
	_switch_page(1)
	_select_and_show(_find_audio("jiangqu_hibiscus_slash"))
	await get_tree().create_timer(0.25).timeout
	_check(_audio_player.stream != null and String(_audio_player.bus) == "SFX" and _audio_player.playing, "音频资源已送入独立 SFX 播放器并实际播放")
	await _shot("fx_audio_audio")
	_stop_audio()
	_switch_page(2)
	_start_demo()
	while _demo_time < 0.50:
		await get_tree().process_frame
	_check(_demo_audio_log.has("jiangqu_hibiscus_slash"), "O 起手播放 jiangqu_hibiscus_slash")
	_check(_demo_distance > 0.0 and _demo_distance < 600.0, "O 在 0.15–0.90 秒窗口内真实位移")
	while _demo_time < 1.04:
		await get_tree().process_frame
	_check(is_equal_approx(_demo_distance, 600.0), "O 位移精确为 600px")
	_check(_demo_hit_done, "O 在 0.95 秒执行路径命中")
	_check(_demo_audio_log == ["jiangqu_hibiscus_slash", "hit_heavy"] and not _demo_audio_log.has("dash_step"), "O 仅有起手音与命中音，无 dash_step")
	_check(is_instance_valid(_demo_spine_hit), "O 每目标仅生成 E54012/action1，不再生成黄色 slash")
	_check(_demo_target_status.text == "8 伤  ·  流血 × 2", "O 显示真实 8 伤与 2 层流血")
	await _shot("fx_audio_shunhua")
	print("[FXAV] RESULT %d failures" % _failures)
	print("[FXAV] ALL DONE")
	get_tree().quit(0 if _failures == 0 else 1)


func _check(ok: bool, label: String) -> void:
	print("[FXAV] ", "PASS " if ok else "FAIL ", label)
	if not ok:
		_failures += 1


func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/out"))
	var err := get_viewport().get_texture().get_image().save_png("res://tests/out/" + tag + ".png")
	_check(err == OK, "保存截图 " + tag)


func _label(text: String, pos: Vector2, font_size: int, color: Color, width: float = 0.0, parent: Node = null) -> Label:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.z_index = 40
	if width > 0.0:
		label.size.x = width
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	(parent if parent != null else self).add_child(label)
	return label


func _button(text: String, pos: Vector2, size: Vector2, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.position = pos
	button.size = size
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_color_override("font_focus_color", INK)
	button.add_theme_stylebox_override("normal", _style(Color(0.87, 0.83, 0.75), 5))
	button.add_theme_stylebox_override("hover", _style(Color(0.80, 0.73, 0.62), 5))
	button.add_theme_stylebox_override("pressed", _style(Color(0.66, 0.55, 0.42), 5))
	button.pressed.connect(action)
	add_child(button)
	return button


func _rect(parent: Node, pos: Vector2, size: Vector2, color: Color, z: int = 0) -> ColorRect:
	var rect := ColorRect.new()
	rect.position = pos
	rect.size = size
	rect.color = color
	rect.z_index = z
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)
	return rect


func _line(parent: Node, points: Array, color: Color, width: float) -> Line2D:
	var line := Line2D.new()
	line.points = PackedVector2Array(points)
	line.default_color = color
	line.width = width
	parent.add_child(line)
	return line


func _style(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = 8
	style.content_margin_right = 8
	return style
