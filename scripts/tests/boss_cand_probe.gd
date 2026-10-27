extends Node2D

## Boss 候选骨架探针：枚举全部动画（名字+时长）-> 测 stand 身高 -> 逐招式测伸展峰值
## 数值均为 scale=1 的骨架像素，结论写 tests/boss_cand_probe.log
## 用法：把候选骨架（4.2 版 .skel/atlas/png/_data.tres）拷进 art/_cand_probe/<id>/，
##       改下面的 SETS 清单，运行 scenes/tests/boss_cand_probe.tscn（量完临时目录可删）

const SETS := [
	{"id": "c008", "data": "res://art/_cand_probe/c008/c008_data.tres"},
	{"id": "c014", "data": "res://art/_cand_probe/c014/c014_data.tres"},
	{"id": "c032", "data": "res://art/_cand_probe/c032/c032_data.tres"},
]

const PROBE_SCALE := 0.35 # 缩小才能在 1280x720 里量到最长伸展；结果再除回来
const ORIGIN := Vector2(640.0, 660.0)
const SAMPLES_PER_SEC := 60.0

var _log: FileAccess


func p(msg: String) -> void:
	print("[P] ", msg)
	if _log:
		_log.store_line("[P] " + msg)
		_log.flush()


func _ready() -> void:
	_log = FileAccess.open("res://tests/boss_cand_probe.log", FileAccess.WRITE)
	RenderingServer.set_default_clear_color(Color(1, 0, 1))
	for set in SETS:
		await _probe(set)
	p("ALL DONE")
	get_tree().quit()


func _probe(set: Dictionary) -> void:
	p("##### " + str(set["id"]))
	var data = load(str(set["data"]))
	if data == null or not data.call("is_skeleton_data_loaded"):
		p("FAIL load data")
		return
	data.call("set_default_mix", 0.0) # 不许混上一段收势姿势，否则采样是脏数据
	var sprite = ClassDB.instantiate("SpineSprite")
	add_child(sprite)
	sprite.set("skeleton_data_res", data)
	sprite.position = ORIGIN
	sprite.scale = Vector2(PROBE_SCALE, PROBE_SCALE)
	var state = sprite.call("get_animation_state")

	# ---- 1. 枚举动画，挑出要实测伸展的招式 ----
	var probe_anims: Array = []
	var all: Array = data.call("get_animations")
	p("total=%d" % all.size())
	for a in all:
		var anim_name := str(a.call("get_name"))
		p("ANIM %s dur=%.3f" % [anim_name, a.call("get_duration")])
		if _is_skill(anim_name):
			probe_anims.append(anim_name)

	# ---- 2. 身高：stand 播一个循环，逐帧取最高/最低点 ----
	var wl := 0.0 # stand 静态左右伸展（判定基线）
	var wr := 0.0
	var stand = data.call("find_animation", "stand")
	if stand == null:
		p("MISSING stand")
	else:
		state.call("set_animation", "stand", true, 0)
		await get_tree().create_timer(0.25).timeout
		var top := 0.0
		var bottom := 0.0
		for _i in range(30):
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			var r := _bbox(img)
			top = minf(top, r[0])
			bottom = maxf(bottom, r[1])
			var e := _extent(img)
			wl = maxf(wl, e[0])
			wr = maxf(wr, e[1])
			await get_tree().create_timer(1.0 / SAMPLES_PER_SEC).timeout
		p("HEIGHT %.1f px @scale1  WIDTH L=%.0f R=%.0f" % [(bottom - top) / PROBE_SCALE, wl, wr])

	# ---- 3. 招式伸展：取右侧峰值与时刻，左侧超出基线也记录（扫身后判定用） ----
	for anim in probe_anims:
		var a = data.call("find_animation", anim)
		var dur: float = a.call("get_duration")
		state.call("set_animation", anim, false, 0)
		var t0 := Time.get_ticks_msec()
		var best_l := 0.0
		var best_r := 0.0
		var best_t := 0.0
		var left_note := ""
		await RenderingServer.frame_post_draw
		while true:
			var t: float = float(Time.get_ticks_msec() - t0) / 1000.0
			var e := _extent(get_viewport().get_texture().get_image())
			if e[1] > best_r:
				best_r = e[1]
				best_l = e[0]
				best_t = t
			if e[0] > wl + 40.0:
				left_note += " L%.0f@%.2f" % [e[0], t]
			if t > dur + 0.10:
				break
			await get_tree().create_timer(1.0 / SAMPLES_PER_SEC).timeout
		p("REACH %s dur=%.2f R=%.0f@%.2f L_at_peak=%.0f%s" % [anim, dur, best_r, best_t, best_l, left_note])

	sprite.queue_free()
	await get_tree().process_frame


## 只实测"招式类"动画：剔除 cankao 参考动画与 atked 受击类
func _is_skill(name: String) -> bool:
	if "cankao" in name:
		return false
	if name.begins_with("atked"):
		return false
	for prefix in ["skill", "atk", "transform", "stop", "zhuanshen", "animation"]:
		if name.begins_with(prefix):
			return true
	return false


## 相对骨架原点 [左, 右, 上]，洋红背景以外的像素
func _extent(img: Image) -> Array:
	var w := img.get_width()
	var h := img.get_height()
	var left := 0.0
	var right := 0.0
	var top := 0.0
	for y in range(0, h, 4):
		for x in range(0, w, 3):
			var c := img.get_pixel(x, y)
			if absf(c.r - 1.0) > 0.08 or absf(c.b - 1.0) > 0.08:
				var d: float = (ORIGIN.x - float(x)) / PROBE_SCALE
				if d > left:
					left = d
				if -d > right:
					right = -d
				var u: float = (ORIGIN.y - float(y)) / PROBE_SCALE
				if u > top:
					top = u
	return [left, right, top]


## 相对骨架原点的 [上, 下]（屏幕像素，正值向上）
func _bbox(img: Image) -> Array:
	var w := img.get_width()
	var h := img.get_height()
	var top := 0.0
	var bottom := 0.0
	for y in range(0, h, 4):
		for x in range(0, w, 3):
			var c := img.get_pixel(x, y)
			if absf(c.r - 1.0) > 0.08 or absf(c.b - 1.0) > 0.08:
				var u: float = (ORIGIN.y - float(y))
				top = minf(top, u)
				bottom = maxf(bottom, u)
	return [top, bottom]
