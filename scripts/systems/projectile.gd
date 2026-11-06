extends Node2D

## 飞行投射物（剑仙剑气）：生成后直线飞行，命中第一个敌人结算伤害，飞满射程自灭。
## 纯 Node2D 手动移动 + 敌组距离判定，和玩家近战判定同一套思路，不开物理区。
## 视觉用 _draw 画一道朱砂剑气弧 + 拖尾墨痕，命中靠 Feel 顿帧震屏 + 音效收尾。

const INK := Color(0.08, 0.07, 0.1)
const RED := Color(0.66, 0.2, 0.16)
const QI := Color(0.78, 0.36, 0.42) # 剑气的朱砂偏粉芯
const QI_GLOW := Color(0.78, 0.36, 0.42, 0.28)
const SPINE_FX := preload("res://scripts/systems/spine_fx.gd")

var _dir := 1
var _speed := 520.0
var _range := 420.0
var _damage := 1
var _sfx := ""
var _sfx_stream
var _travel := 0.0
var _sfx_player: AudioStreamPlayer
var _pierce := false # 穿云剑气（剑仙形态专属）：命中后不消失继续飞
var _pierce_left := 0 # 永久剑气：有限穿透次数；与无限穿透独立
var _hit_list: Array = [] # 穿透模式下已结算过的敌人，防止同一目标反复掉血
var _source: Node = null # 来源玩家：目标状态加伤、技能命中与多道剑气回报
var _from_skill := false
var _cast_id := 0
var _root_time := 0.0 # 命中定身秒数（绯刃 U：无法移动但可以攻击）
var _split_left := 0 # 命中后还要分裂出去的第二把数量（绯刃 U）
var _from_split := false # 是否由另一把匕命中后分裂而来
var _style := "qi" # 视觉：qi=朱砂剑气弧 / dagger=短匕
var _bleed := 0 # 命中叠流血层数（剑仙月华斩）
var _size := 1.0 # 剑气视觉与判定尺寸倍率（巨大剑气）
var _effects: Dictionary = {} # 状态附加与 Spine 飞行/命中特效配置
var _spine_fx: Node2D = null
var _fx_id := ""
var _hits_done := 0


## dir: 1 朝右 -1 朝左；damage 已含局内强化/契合加成；sfx 命中音效名（空则不播）；pierce 命中不毁；
## root 命中定身秒数；split 命中后分裂数量；style 视觉风格；bleed 命中叠流血层数；scale 尺寸倍率
func setup(p_dir: int, p_speed: float, p_range: float, p_damage: int, p_sfx := "", p_pierce := false,
		p_root := 0.0, p_split := 0, p_style := "qi", p_bleed := 0, p_scale := 1.0,
		p_pierce_charges := 0, p_source: Node = null, p_from_skill := false, p_cast_id := 0,
		p_effects: Dictionary = {}) -> void:
	_dir = p_dir
	_speed = p_speed
	_range = p_range
	_damage = p_damage
	_sfx = p_sfx
	_pierce = p_pierce
	_root_time = p_root
	_split_left = p_split
	_style = p_style
	_bleed = p_bleed
	_size = p_scale
	_pierce_left = p_pierce_charges
	_source = p_source
	_from_skill = p_from_skill
	_cast_id = p_cast_id
	_effects = p_effects.duplicate(true)


func _ready() -> void:
	scale = Vector2(_dir * _size, _size) # 剑气弧朝飞行方向，尺寸按配置放大
	_fx_id = str(_effects.get("fx_id", ""))
	if _fx_id.is_empty() and _style == "fireball":
		_fx_id = "E100180"
		_effects["fx_id"] = _fx_id
	if not _fx_id.is_empty():
		var anim := _resolve_fx_anim(_fx_id, str(_effects.get("fx_anim", "")))
		_spine_fx = SPINE_FX.attach(self, _fx_id, Vector2.ZERO, {
			"anim": anim, "loop": true, "auto_free": false,
			"speed": float(_effects.get("fx_speed", 1.0)),
			"scale": float(_effects.get("fx_scale", 1.0)),
			"height": float(_effects.get("fx_height", 0.0)),
			"center": true,
		})
		if _spine_fx != null:
			_spine_fx.set_meta("fx_id", _fx_id)
			_spine_fx.set_meta("fx_anim", anim)
			_spine_fx.set_meta("fx_role", "flight")
	if _sfx != "":
		_sfx_stream = load("res://audio/sfx/" + _sfx + ".wav")
		_sfx_player = AudioStreamPlayer.new()
		_sfx_player.bus = "SFX"
		add_child(_sfx_player)
	queue_redraw()


static func _resolve_fx_anim(fx_id: String, requested: String) -> String:
	var d = SPINE_FX.data(fx_id)
	if d == null:
		return requested
	for candidate in [requested, "action", "action1"]:
		var name := str(candidate)
		if not name.is_empty() and d.call("find_animation", name) != null:
			return name
	var animations: Array = d.call("get_animations")
	return str(animations[0].call("get_name")) if not animations.is_empty() else requested


func _spawn_hit_spine(pos: Vector2, first: bool) -> void:
	var host := get_tree().current_scene
	if host == null:
		return
	if first and not str(_effects.get("first_fx_anim", "")).is_empty() and not _fx_id.is_empty():
		var first_anim := _resolve_fx_anim(_fx_id, str(_effects["first_fx_anim"]))
		var first_fx := SPINE_FX.spawn(host, _fx_id, pos, {
			"anim": first_anim, "loop": false, "auto_free": true,
			"scale": float(_effects.get("first_fx_scale", _effects.get("fx_scale", 1.0))) * _size,
			"flip": _dir < 0,
			"bottom": true, # 落地爆炸按脚底对齐，整段激光坠落画面才不会偏到地面以下
		})
		if first_fx != null:
			first_fx.set_meta("fx_id", _fx_id)
			first_fx.set_meta("fx_anim", first_anim)
			first_fx.set_meta("fx_role", "first_hit")
		# 首击专属音效：一次技能只响一次，命中多人也只有第一次命中触发
		var hit_sfx := str(_effects.get("hit_sfx", ""))
		if not hit_sfx.is_empty():
			var stream := load("res://audio/sfx/%s.wav" % hit_sfx)
			if stream != null:
				var voice := AudioStreamPlayer.new()
				voice.bus = "SFX"
				voice.stream = stream
				host.add_child(voice)
				voice.finished.connect(voice.queue_free)
				voice.play()
		return
	var hit_id := str(_effects.get("hit_fx_id", ""))
	if hit_id.is_empty():
		return
	var hit_anim := _resolve_fx_anim(hit_id, str(_effects.get("hit_fx_anim", "")))
	var hit_fx := SPINE_FX.spawn(host, hit_id, pos + Vector2(0.0, -60.0), {
		"anim": hit_anim, "loop": false, "auto_free": true,
		"scale": float(_effects.get("hit_fx_scale", 1.0)) * _size,
		"height": float(_effects.get("hit_fx_height", 0.0)) * _size,
		"flip": _dir < 0,
		"center": true,
	})
	if hit_fx != null:
		hit_fx.set_meta("fx_id", hit_id)
		hit_fx.set_meta("fx_anim", hit_anim)
		hit_fx.set_meta("fx_role", "hit")


func _draw() -> void:
	if is_instance_valid(_spine_fx):
		return
	if _style == "dagger":
		_draw_dagger()
		return
	if _style == "magic_sound":
		_draw_magic_sound()
		return
	# 剑气：一道前凸的朱砂弧 + 内侧淡晕 + 后方两笔墨拖尾
	var arc_pts := PackedVector2Array()
	for i in 9:
		var a: float = lerpf(-1.15, 1.15, i / 8.0)
		arc_pts.append(Vector2(cos(a) * 10.0, sin(a) * 30.0))
	draw_circle(Vector2.ZERO, 20.0, QI_GLOW)
	draw_polyline(arc_pts, QI, 4.0, true)
	draw_polyline(arc_pts, Color(1.0, 0.86, 0.82, 0.9), 1.5, true)
	# 墨拖尾：从弧心往后拉两道细线
	draw_line(Vector2(-4, -14), Vector2(-34, -7), Color(INK, 0.55), 2.5)
	draw_line(Vector2(-4, 14), Vector2(-30, 8), Color(INK, 0.4), 2.0)


## 短匕：刃身朝前 + 朱砂护手 + 墨色缠柄，后方一缕红线拖尾（绯刃 U 投掷）
func _draw_dagger() -> void:
	draw_colored_polygon(PackedVector2Array([
		Vector2(4, -4), Vector2(34, 0), Vector2(4, 4),
	]), QI)
	draw_line(Vector2(2, -10), Vector2(2, 10), RED, 3.0) # 护手
	draw_line(Vector2(-18, 0), Vector2(2, 0), INK, 4.5) # 缠柄
	draw_circle(Vector2(-18, 0), 2.5, Color(0.85, 0.75, 0.62))
	draw_line(Vector2(-6, -12), Vector2(-40, -6), Color(RED, 0.45), 2.0) # 拖尾
	draw_line(Vector2(-6, 12), Vector2(-36, 7), Color(INK, 0.35), 1.5)


## 魔音：三重绛紫声波与一缕墨色尾迹，远程普攻和黍离共用。
func _draw_magic_sound() -> void:
	var purple := Color(0.68, 0.38, 0.76)
	draw_circle(Vector2.ZERO, 22.0, Color(purple, 0.16))
	for ring in 3:
		var pts := PackedVector2Array()
		for i in 11:
			var a := lerpf(-1.2, 1.2, i / 10.0)
			pts.append(Vector2(cos(a) * (8.0 + ring * 6.0) - ring * 5.0, sin(a) * (22.0 + ring * 7.0)))
		draw_polyline(pts, Color(purple, 0.95 - ring * 0.2), 3.0 - ring * 0.5, true)
	draw_line(Vector2(-12, -10), Vector2(-42, -4), Color(INK, 0.55), 2.5)
	draw_line(Vector2(-12, 10), Vector2(-36, 5), Color(purple, 0.45), 2.0)


func _physics_process(delta: float) -> void:
	var step := _speed * delta
	position.x += _dir * step
	_travel += step
	# 命中判定：横向贴近剑气、纵向与敌人脚底同一平面（剑气在胸口高度飞）
	for e in get_tree().get_nodes_in_group("enemies"):
		if bool(_effects.get("visual_only", false)):
			break
		var p := e as Node2D
		if p == null:
			continue
		if int(e.get("hp")) <= 0: # 尸体不吃投射物，与近战判定一致
			continue
		if _hit_list.has(e.get_instance_id()): # 穿透模式下已结算过的目标直接掠过
			continue
		# 命中窗口 = 剑气自身 30px + 目标受击半径：大体型 Boss 边缘就能截住剑气
		var r = e.get("body_radius")
		var br := float(r) if r != null else 30.0
		if absf(p.global_position.x - global_position.x) <= 30.0 * _size + br and absf(p.global_position.y - global_position.y) <= 80.0:
			var hit_damage := _damage
			if _hits_done == 0:
				hit_damage = int(_effects.get("first_damage", hit_damage))
			else:
				hit_damage = int(_effects.get("later_damage", hit_damage))
			_hits_done += 1
			_spawn_hit_spine(p.global_position, _hits_done == 1)
			if bool(_effects.get("pipa_wave", false)) and is_instance_valid(_source) and _source.has_method("on_pipa_wave_hit"):
				_source.call("on_pipa_wave_hit", p, hit_damage)
			else:
				if is_instance_valid(_source) and _source.has_method("_target_damage_bonus"):
					hit_damage += int(_source.call("_target_damage_bonus", p))
				if is_instance_valid(_source) and _source.has_method("_damage_enemy"):
					_source.call("_damage_enemy", p, hit_damage)
				else:
					p.call("take_damage", hit_damage, global_position.x)
			# 命中计数与永久效果优先回报给实际来源；旧测试场景没有来源时保留原入口。
			if is_instance_valid(_source) and _source.has_method("on_projectile_hit"):
				_source.call("on_projectile_hit", p, _from_skill, _cast_id)
				if _style == "dagger" and _source.has_method("on_dagger_hit"):
					_source.call("on_dagger_hit", p, global_position, _from_split)
			else:
				var pl = get_tree().get_first_node_in_group("player")
				if pl != null and pl.has_method("hit_scored"):
					pl.call("hit_scored")
				else:
					Score.add_hit()
			# 定身：命中时敌人还在（没被这一下打死）才挂，避免对着尸体定身
			if _root_time > 0.0 and int(e.get("hp")) > 0 and e.has_method("root"):
				e.call("root", _root_time)
			# 流血（剑仙月华斩）：命中即叠层，剑气本身不消失
			if _bleed > 0 and int(e.get("hp")) > 0 and e.has_method("apply_bleed"):
				e.call("apply_bleed", _bleed)
			if int(e.get("hp")) > 0 and float(_effects.get("frenzy", 0.0)) > 0.0 and e.has_method("apply_frenzy"):
				e.call("apply_frenzy", float(_effects["frenzy"]), bool(_effects.get("frenzy_empower", false)))
			if int(e.get("hp")) > 0 and bool(_effects.get("frenzy_double", false)) and e.has_method("double_frenzy"):
				e.call("double_frenzy", float(_effects.get("frenzy_min", 12.0)))
			if _style == "magic_sound" and is_instance_valid(_source) and _source.has_method("on_pipa_sound_hit"):
				_source.call("on_pipa_sound_hit", p)
			Feel.hitstop(0.04)
			Feel.shake(3.0, 0.1)
			# 分裂（绯刃 U）：第一把钉进敌人，第二把从命中点继续飞，忽略刚命中的目标防重复掉血
			var split_hit := false
			if _split_left > 0:
				_split_left -= 1
				var child = get_script().new()
				child.setup(_dir, _speed, _range, _damage, _sfx, _pierce, _root_time, _split_left, _style, _bleed, _size,
					_pierce_left, _source, _from_skill, _cast_id, _effects)
				child._hit_list = _hit_list.duplicate()
				child._from_split = true
				child._hit_list.append(e.get_instance_id())
				child.global_position = global_position + Vector2(_dir * 34.0 * _size, 0.0)
				get_tree().current_scene.add_child(child)
				split_hit = true
			if not split_hit and (_pierce or _pierce_left > 0): # 记下这个目标继续飞；有限穿透只消耗次数，不与无限穿透混淆
				if not _pierce:
					_pierce_left -= 1
				_hit_list.append(e.get_instance_id())
				if _sfx_stream != null and not _sfx_player.playing:
					_sfx_player.stream = _sfx_stream
					_sfx_player.play()
				continue
			if _sfx_stream != null:
				_sfx_player.stream = _sfx_stream
				_sfx_player.play()
				_sfx_player.finished.connect(queue_free, CONNECT_ONE_SHOT) # 等命中音放完再灭
				set_physics_process(false)
				visible = false
			else:
				queue_free()
			return
	if _travel >= _range:
		if is_instance_valid(_source) and _source.has_method("on_projectile_expire"):
			_source.call("on_projectile_expire", global_position, _style)
		queue_free()
