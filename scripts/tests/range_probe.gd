extends Node2D

## 素材探针：一次跑多套骨架
## 1) 测 stand 的视觉高度（scale=1 的骨架像素）-> 用来反推游戏内缩放
## 2) 测攻击动画的水平伸展峰值与时刻 -> 用来写判定范围 / 命中时刻
## 结论写进 tests/range_probe.log，数值均为 scale=1 的骨架像素

const SETS := [
	{"id": "c021", "data": "res://art/characters/player/c021_data.tres",
		"anims": ["atk01", "atk02", "atk03", "skill01", "skill03", "skill04", "skill5-", "skill02-cankao"]},
	{"id": "pc023", "data": "res://art/characters/player/skulls/c023/c023_data.tres",
		"anims": ["animation", "2", "skill01", "skill02"]},
	{"id": "c016", "data": "res://art/characters/enemies/c016/c016_data.tres",
		"anims": ["skill01", "skill02", "skill03", "skill04", "skill05"]},
	{"id": "z000", "data": "res://art/characters/player/skulls/z000/z000_data.tres",
		"anims": ["atk01", "atk02", "skill16", "skill07_02", "atk04", "atk04_air",
			"skill02-", "skill12", "skill04", "skill09", "skill20_03"]},
	{"id": "c013", "data": "res://art/characters/player/skulls/c013/c013_data.tres",
		"anims": ["skill04", "skill02_01", "skill02_03", "skill01", "skill02", "skill03"]},
	{"id": "c012", "data": "res://art/characters/enemies/c012/c012_data.tres",
		"anims": ["animation", "skill01", "skill02"]},
	{"id": "z002", "data": "res://art/characters/enemies/z002/z002_data.tres",
		"anims": ["atk01", "atk02", "atk03", "skill01"]},
	{"id": "c017", "data": "res://art/characters/enemies/c017/c017_data.tres",
		"anims": ["skill01", "skill02", "skill03_2", "skill03_3"]},
	{"id": "c035", "data": "res://art/characters/enemies/c035/c035_data.tres",
		"anims": ["skill01", "skill02"]},
	{"id": "c037", "data": "res://art/characters/enemies/c037/c037_data.tres",
		"anims": ["skill01", "skill02", "skill03", "skill04", "skill05", "skill06"]},
	{"id": "c018", "data": "res://art/characters/enemies/c018/c018_data.tres",
		"anims": ["skill01", "skill02", "skill03"]},
	{"id": "c009", "data": "res://art/characters/enemies/bosses/c009/c009_data.tres",
		"anims": ["skill01", "skill02", "skill03", "skill04", "skill05", "skill06", "skill07", "skill08", "def_break"]},
	{"id": "c015a1", "data": "res://art/characters/enemies/bosses/c015a1/c015a1_data.tres",
		"anims": ["skill01", "skill02", "skill3", "skill04", "skill4", "skill05", "skill03-01", "skill03-02", "def_break"]},
	{"id": "c001", "data": "res://art/characters/enemies/bosses/c001/c001_data.tres",
		"anims": ["skill01", "skill02", "skill03", "skill01-", "zhuanshen", "speed_run", "stop"]},
	{"id": "z003", "data": "res://art/characters/player/skulls/z003/z003_data.tres",
		"anims": ["skill02", "skill03", "skill04", "skill05", "skill06", "skill07", "skill08",
			"skill08-cankao", "skill09", "skill10", "skill11", "skill11-cankao", "skill14_02",
			"skill18_02", "skill23_03", "skill24_03", "skill17_02", "jump",
			"atk03_03", "atk04_02", "skill01"]}, # K 新随机池（#15/#17/#70）
]

const PROBE_SCALE := 0.35 # 缩小才能在 1280x720 里量到最长伸展；结果再除回来
const ORIGIN := Vector2(640.0, 660.0)
const SAMPLES_PER_SEC := 60.0

var _log: FileAccess
var _out: Dictionary = {} # 全部采样写进 tests/out/reach.json，供标定脚本逐条比对配置


func p(msg: String) -> void:
	print("[P] ", msg)
	if _log:
		_log.store_line("[P] " + msg)
		_log.flush()


func _ready() -> void:
	_log = FileAccess.open("res://tests/range_probe.log", FileAccess.WRITE)
	RenderingServer.set_default_clear_color(Color(1, 0, 1))
	for set in SETS:
		await _probe(set)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/out"))
	var f := FileAccess.open("res://tests/out/reach.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(_out))
	f.close()
	p("ALL DONE")
	get_tree().quit()


func _probe(set: Dictionary) -> void:
	p("##### " + str(set["id"]))
	var data = load(str(set["data"]))
	if data == null or not data.call("is_skeleton_data_loaded"):
		p("FAIL load data")
		return
	data.call("set_default_mix", 0.0) # 关键：不许混上一段动画的收势姿势，否则 t=0 的伸展量是脏数据
	var sprite = ClassDB.instantiate("SpineSprite")
	add_child(sprite)
	sprite.set("skeleton_data_res", data)
	sprite.position = ORIGIN
	sprite.scale = Vector2(PROBE_SCALE, PROBE_SCALE)
	var state = sprite.call("get_animation_state")

	# ---- 1. 身高：stand 播一个循环，逐帧取最高/最低点 ----
	var wl := 0.0 # stand 静态左右伸展（判定基线，攻击峰值必须明显超过它才算"挥出去"）
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
		var h: float = (bottom - top) / PROBE_SCALE
		p("HEIGHT top=%.0f bottom=%.0f -> %.1f px @scale1  WIDTH L=%.0f R=%.0f" % [top / PROBE_SCALE, bottom / PROBE_SCALE, h, wl, wr])

	# ---- 2. 攻击伸展：逐帧采样左右伸展，输出所有局部峰值（多段招式能逐段对上） ----
	var anims_out: Dictionary = {}
	for anim in set["anims"]:
		var a = data.call("find_animation", anim)
		if a == null:
			p("MISSING anim " + str(anim))
			continue
		var dur: float = a.call("get_duration")
		state.call("set_animation", anim, false, 0)
		var t0 := Time.get_ticks_msec()
		var series: Array = [] # [t, 左, 右]
		await RenderingServer.frame_post_draw
		while true:
			var t: float = float(Time.get_ticks_msec() - t0) / 1000.0
			var e := _extent(get_viewport().get_texture().get_image())
			series.append([t, e[0], e[1]])
			if t > dur + 0.10:
				break
			await get_tree().create_timer(1.0 / SAMPLES_PER_SEC).timeout
		anims_out[anim] = {"dur": dur, "s": series}
		p("ANIM %s dur=%.3f %s" % [anim, dur, _peaks(series, wl, wr)])
	_out[str(set["id"])] = {"wl": wl, "wr": wr, "anims": anims_out}

	sprite.queue_free()
	await get_tree().process_frame


## 逐侧找"挥出去"的局部峰值：超过 stand 静态基线 40px、且是 ±0.12s 窗口内最大值
func _peaks(series: Array, wl: float, wr: float) -> String:
	var out: Array = []
	for side in [1, 2]:
		var base: float = wl if side == 1 else wr
		var label := "L" if side == 1 else "R"
		var last_t := -1.0
		for i in series.size():
			var v: float = float(series[i][side])
			if v < base + 40.0:
				continue
			var is_peak := true
			for j in series.size():
				if j == i:
					continue
				if absf(float(series[j][0]) - float(series[i][0])) > 0.12:
					continue
				if float(series[j][side]) > v + 0.5:
					is_peak = false
					break
			if not is_peak:
				continue
			if float(series[i][0]) - last_t < 0.1: # 平顶只留一个
				continue
			last_t = float(series[i][0])
			out.append("%s%.0f@%.2f" % [label, v, float(series[i][0])])
	return " ".join(out)


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
