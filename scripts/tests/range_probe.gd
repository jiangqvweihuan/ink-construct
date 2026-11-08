extends Node2D

## 素材探针（需窗口模式运行：要读画面像素）
## 1) 测 stand 的视觉高度（scale=1 的骨架像素）-> 用来反推游戏内缩放
## 2) 测攻击动画的水平伸展峰值与时刻 -> 用来写判定范围 / 命中时刻
## 3) 新增：在每个配置命中时刻输出「剪影伸展 × 角色缩放 vs 配置 range」，超容差判 FAIL
## 结论写进 tests/range_probe.log，数值均为 scale=1 的骨架像素；reach.json 供标定脚本比对

const Skulls := preload("res://scripts/player/skulls.gd")
const Types := preload("res://scripts/enemies/enemy_types.gd")
const BossTypes := preload("res://scripts/enemies/boss_types.gd")

const PROBE_SCALE := 0.35 # 缩小才能在 1280x720 里量到最长伸展；结果再除回来
const ORIGIN := Vector2(640.0, 660.0)
const SAMPLES_PER_SEC := 60.0

var SETS: Array = []
var _expect: Dictionary = {} # 角色 id -> 动画名 -> [{t, range, both, tag}]
var _log: FileAccess
var _out: Dictionary = {} # 全部采样写进 tests/out/reach.json，供标定脚本逐条比对配置
var _vis_checks := 0
var _vis_fails := 0


func p(msg: String) -> void:
	print("[P] ", msg)
	if _log:
		_log.store_line("[P] " + msg)
		_log.flush()


func _ready() -> void:
	_log = FileAccess.open("res://tests/range_probe.log", FileAccess.WRITE)
	RenderingServer.set_default_clear_color(Color(1, 0, 1))
	_build_sets()
	for set in SETS:
		await _probe(set)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/out"))
	var f := FileAccess.open("res://tests/out/reach.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(_out))
	f.close()
	p("VIS RESULT checks=%d fail=%d" % [_vis_checks, _vis_fails])
	p("ALL DONE")
	get_tree().quit()


# ---------------------------------------------------------------- 按配置生成探针清单

func _add_anim(list: Array, anim: String) -> void:
	if not anim.is_empty() and not list.has(anim):
		list.append(anim)


func _add_ex(ex: Dictionary, anim: String, t: float, rng: float, both: bool, tag: String, back := -1.0) -> void:
	if rng <= 0.0 or t < 0.0:
		return
	if not ex.has(anim):
		ex[anim] = []
	(ex[anim] as Array).append({"t": t, "range": rng, "back": back, "both": both, "tag": tag})


func _seg_damage(dmg, seg: int) -> float:
	if dmg == null:
		return 1.0
	if dmg is Array:
		var a := dmg as Array
		return float(a[mini(seg, a.size() - 1)]) if not a.is_empty() else 1.0
	return float(dmg)


func _seg_range_local(rng, seg: int) -> float:
	if rng == null:
		return 0.0
	if rng is Array:
		var a := rng as Array
		return float(a[mini(seg, a.size() - 1)]) if not a.is_empty() else 0.0
	return float(rng)


func _build_sets() -> void:
	## ---------------- 玩家形态 ----------------
	for id in Skulls.SKULLS.keys():
		var s: Dictionary = Skulls.SKULLS[str(id)]
		var cid := "P/" + str(id)
		var anims: Array = []
		var ex: Dictionary = {}
		for atk in s.get("attacks", []):
			if atk.has("pool"):
				var hm: Dictionary = atk.get("hit_at", {})
				var rm: Dictionary = atk.get("range", {})
				for v in atk["pool"]:
					var anim := str(v)
					_add_anim(anims, anim)
					if hm.has(anim):
						var times: Array = hm[anim] if hm[anim] is Array else [hm[anim]]
						for ti in times.size():
							_add_ex(ex, anim, float(times[ti]), _seg_range_local(rm.get(anim, 0.0), ti), false, "%s/atk" % cid)
			else:
				var anim := str(atk.get("anim", ""))
				_add_anim(anims, anim)
				var hits: Array = atk.get("hits", [])
				for hi in hits.size():
					var h = hits[hi]
					var at := float((h as Dictionary).get("at", 0.0)) if h is Dictionary else float(h)
					var rng := float((h as Dictionary).get("range", atk.get("range", 0.0))) if h is Dictionary else float(atk.get("range", 0.0))
					var both := bool((h as Dictionary).get("both", atk.get("both", false))) if h is Dictionary else bool(atk.get("both", false))
					_add_ex(ex, anim, at, rng, both, "%s/atk%d" % [cid, hi + 1])
		for key in s.get("skills", {}):
			var cfg: Dictionary = s["skills"][key]
			# 位移斩杀 / 全屏技：range 表示路径宽度或全场，不按静止剪影比对
			if bool(cfg.get("path", false)) or bool(cfg.get("full_screen", false)):
				continue
			var variants: Array = []
			if cfg.has("pool"):
				variants = (cfg["pool"] as Array).duplicate()
			else:
				variants.append(cfg.get("anim", key))
			if cfg.has("awaken") and (cfg["awaken"] as Dictionary).has("anim"):
				variants.append((cfg["awaken"] as Dictionary)["anim"])
			var hm: Dictionary = cfg.get("hit_at", {})
			var rmap = cfg.get("range", {})
			for v in variants:
				var anim := str(v)
				_add_anim(anims, anim)
				if hm.has(anim):
					var times: Array = hm[anim] if hm[anim] is Array else [hm[anim]]
					var rv = rmap.get(anim, null) if rmap is Dictionary else rmap
					for ti in times.size():
						_add_ex(ex, anim, float(times[ti]), _seg_range_local(rv, ti), bool(cfg.get("both", false)),
							"%s/skill:%s" % [cid, str(key)])
					continue
				for hi in (cfg.get("hits", []) as Array).size():
					var h = cfg["hits"][hi]
					if not (h is Dictionary):
						continue
					var hd := h as Dictionary
					if hd.has("projectile") or hd.has("full_screen") or hd.has("charm") or hd.has("self_shield") or hd.has("path"):
						continue
					if not hd.has("at"):
						continue
					var rng := float(hd.get("range", 0.0)) if hd.has("range") else (float(rmap) if rmap != null and not (rmap is Dictionary) else 0.0)
					_add_ex(ex, anim, float(hd["at"]), rng, bool(hd.get("both", cfg.get("both", false))),
						"%s/skill:%s/seg%d" % [cid, str(key), hi + 1])
		SETS.append({"id": cid, "data": s.get("data", ""), "scale": float(s.get("scale", 1.0)), "anims": anims})
		_expect[cid] = ex

	## ---------------- 小怪 / 精英 ----------------
	for id in Types.TYPES.keys():
		_build_enemy_set("E/" + str(id), Types.TYPES[str(id)], false)

	## ---------------- Boss ----------------
	for id in BossTypes.BOSSES.keys():
		_build_enemy_set("B/" + str(id), BossTypes.BOSSES[str(id)], true)


func _build_enemy_set(cid: String, t: Dictionary, is_boss: bool) -> void:
	var anims: Array = []
	var ex: Dictionary = {}
	var ranges: Dictionary = t.get("ranges", {})
	var hit_at: Dictionary = t.get("hit_at", {})
	var dmg_map: Dictionary = t.get("damage", {})
	var both_map: Dictionary = t.get("both", {})
	var back_map: Dictionary = t.get("back_ranges", {})
	var pool: Dictionary = t.get("move_pool", {})
	var move_anims: Dictionary = t.get("move_anims", {})
	var moves: Array = []
	if is_boss:
		for stage in t.get("stages", []):
			for m in stage.get("attacks", []):
				if not moves.has(str(m)):
					moves.append(str(m))
	else:
		for m in t.get("attacks", []):
			if not moves.has(str(m)):
				moves.append(str(m))
	for move in moves:
		var variants: Array = []
		if pool.has(move) and not (pool[move] as Array).is_empty():
			for v in pool[move]:
				variants.append([str(v), str(v)])
		else:
			variants.append([move, str(move_anims.get(move, move))])
		for pair in variants:
			var key := str(pair[0])
			var visual := str(pair[1])
			_add_anim(anims, visual)
			if not hit_at.has(key) or not ranges.has(key):
				continue
			var ha: Array = hit_at[key] if hit_at[key] is Array else [hit_at[key]]
			var dmg = dmg_map.get(move, 1)
			for seg in ha.size():
				if _seg_damage(dmg, seg) <= 0.0:
					continue
				# back_ranges：both 招式身后有独立射程（如双镰），比对时左右各看各的
				var back := -1.0
				if back_map.has(move):
					back = _seg_range_local(back_map[move], seg)
				_add_ex(ex, visual, float(ha[seg]), _seg_range_local(ranges[key], seg), bool(both_map.get(move, false)),
					"%s/%s seg%d" % [cid, move, seg + 1], back)
	SETS.append({"id": cid, "data": t.get("data", ""), "scale": float(t.get("scale", 1.0)), "anims": anims})
	_expect[cid] = ex


# ---------------------------------------------------------------- 采样

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
	await RenderingServer.frame_post_draw
	var _probe_img := get_viewport().get_texture().get_image()
	p("IMG %dx%d visible=%.0fx%.0f" % [_probe_img.get_width(), _probe_img.get_height(),
		get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y])

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
		var h: float = bottom - top
		p("HEIGHT top=%.0f bottom=%.0f -> %.1f px @scale1  WIDTH L=%.0f R=%.0f" % [top, bottom, h, wl, wr])

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
		var series: Array = [] # [动画秒, 左, 右, 上]
		while true:
			# 先等这一帧画完，再读轨道时间并取像素，保证「时间戳」和「画面」是同一帧，
			# 否则会稳定地差 1 帧，误判成“命中早于挥击峰值”。
			await RenderingServer.frame_post_draw
			var entry = state.call("get_current", 0)
			var t: float = float(entry.call("get_track_time")) if entry != null else 0.0
			var e := _extent(get_viewport().get_texture().get_image())
			series.append([t, e[0], e[1], e[2]])
			if float(Time.get_ticks_msec() - t0) / 1000.0 > dur + 0.10:
				break
			await get_tree().create_timer(1.0 / SAMPLES_PER_SEC).timeout
		anims_out[anim] = {"dur": dur, "s": series}
		p("ANIM %s dur=%.3f %s" % [anim, dur, _peaks(series, wl, wr)])
		_check_visual(str(set["id"]), anim, series, float(set["scale"]))

	_out[str(set["id"])] = {"wl": wl, "wr": wr, "anims": anims_out}

	sprite.queue_free()
	await get_tree().process_frame


## 在配置的每个命中时刻读取剪影伸展，与配置 range（世界像素）比对
## 判定口径：从命中时刻起 2 帧内，剪影只要到达配置射程 - 容差，就算对齐
## （挥击是「扫过」目标，首次够到即接触，不必等到峰值）。
## 输出四种偏差：
##   OK    命中时刻已在容差内或 2 帧内够到；
##   SHIFT 够到时刻晚于 2 帧 → hit_at 早于挥击（需要把命中时刻后移）；
##   LOW   整段峰值都够不到配置射程（判定比画面更长，多为远程/特效招式，见 INFO）；
##   HIGH  整段峰值明显超过配置射程（画面够得到但判不上）。
func _check_visual(cid: String, anim: String, series: Array, char_scale: float) -> void:
	var ex: Array = (_expect.get(cid, {}) as Dictionary).get(anim, [])
	if ex.is_empty():
		return
	for e in ex:
		var at := float(e["t"])
		var both := bool(e["both"])
		var cfg := float(e["range"])
		var t_end := 0.0
		for smp in series:
			t_end = maxf(t_end, float(smp[0]))
		if at >= t_end:
			p("VIS %s %s@%.2f 命中时刻超出动画时长 %.2f（占位/不触发，跳过）" % [
				str(e["tag"]), anim, at, t_end])
			continue
		if cfg >= 900.0:
			p("VIS %s %s@%.2f 配置射程 %.0f 为全屏/横穿判定，不按单帧剪影比对（跳过）" % [
				str(e["tag"]), anim, at, cfg])
			continue
		var s: Array = _nearest(series, at)
		var l: float = float(s[1]) * char_scale
		var r: float = float(s[2]) * char_scale
		if l <= 0.001 and r <= 0.001:
			p("VIS %s %s@%.2f 采样为空（该帧无墨迹，跳过）" % [str(e["tag"]), anim, at])
			continue
		var tol: float = maxf(25.0, cfg * 0.20)
		var back_cfg := float(e.get("back", -1.0))
		var hit_meas: float = maxf(l, r) if both else r
		# 命中时刻之后首次「够到配置射程 - 容差」的时间；同时记录 ±0.12s 峰值
		var reach_dt := 999.0
		var peak := hit_meas
		var peak_dt := 0.0
		var peak_l := l
		var peak_r := r
		for smp in series:
			var dt := float(smp[0]) - at
			if dt < -0.02 or dt > 0.12:
				continue
			var sl: float = float(smp[1]) * char_scale
			var sr: float = float(smp[2]) * char_scale
			var v: float = maxf(sl, sr) if both else sr
			if v >= cfg - tol and reach_dt > 900.0:
				reach_dt = dt
			if v > peak:
				peak = v
				peak_dt = dt
				peak_l = sl
				peak_r = sr
		var status := "OK"
		if back_cfg > 0.0:
			# both + back_ranges（如双镰）：前侧对 ranges、后侧对 back_ranges，各自核对
			var btol: float = maxf(25.0, back_cfg * 0.20)
			var front_hit := absf(r - cfg) <= tol
			var rear_hit := absf(l - back_cfg) <= btol
			var front_peak := absf(peak_r - cfg) <= tol
			var rear_peak := absf(peak_l - back_cfg) <= btol
			if front_hit and rear_hit:
				status = "OK"
			elif front_peak and rear_peak and absf(peak_dt) <= 0.034:
				status = "OK" # 两侧都在 2 帧内挥到位
			elif front_peak and rear_peak:
				status = "SHIFT"
			elif r > cfg + tol or l > back_cfg + btol:
				status = "HIGH"
			elif peak_r < cfg - tol or peak_l < back_cfg - btol:
				status = "LOW"
			else:
				status = "SHIFT"
		elif absf(hit_meas - cfg) <= tol:
			status = "OK" # 命中帧剪影已在容差带内
		elif hit_meas > cfg + tol:
			status = "HIGH" # 命中帧画面已明显伸过判定，反方向错配
		elif reach_dt <= 0.034:
			status = "OK" # 2 帧内够到：肉眼无差
		elif peak < cfg - tol:
			status = "LOW" # 画面全程够不到判定距离
		else:
			status = "SHIFT" # 峰值够得到，但命中后 2~6 帧才挥到位 → 命中偏早
		_vis_checks += 1
		if status != "OK":
			_vis_fails += 1
		p("VIS %s %s@%.2f 命中=%.0f(L%.0f R%.0f) 首达%+.3f 峰=%.0f@%+.3f(L%.0f R%.0f) 配置=%.0f%s 容差±%.0f [%s]" % [
			str(e["tag"]), anim, at, hit_meas, l, r, reach_dt, peak, peak_dt, peak_l, peak_r, cfg,
			(" 背侧=%.0f" % back_cfg) if back_cfg > 0.0 else "", tol, status])


func _nearest(series: Array, t: float) -> Array:
	if series.is_empty():
		return [t, 0.0, 0.0, 0.0]
	var best: Array = series[0]
	var bd := absf(float(best[0]) - t)
	for s in series:
		var d := absf(float(s[0]) - t)
		if d < bd:
			bd = d
			best = s
	return best


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
## 注意：Windows 高 DPI 下视口纹理是物理像素，必须按 图像宽/逻辑宽 换算回逻辑坐标
func _extent(img: Image) -> Array:
	var w := img.get_width()
	var h := img.get_height()
	var k := float(w) / maxf(get_viewport().get_visible_rect().size.x, 1.0)
	var ox := ORIGIN.x * k
	var oy := ORIGIN.y * k
	var left := 0.0
	var right := 0.0
	var top := 0.0
	for y in range(0, h, 4):
		for x in range(0, w, 3):
			var c := img.get_pixel(x, y)
			if absf(c.r - 1.0) > 0.08 or absf(c.b - 1.0) > 0.08:
				var d: float = (ox - float(x)) / (PROBE_SCALE * k)
				if d > left:
					left = d
				if -d > right:
					right = -d
				var u: float = (oy - float(y)) / (PROBE_SCALE * k)
				if u > top:
					top = u
	return [left, right, top]


## 相对骨架原点的 [上, 下]（屏幕像素，正值向上）
func _bbox(img: Image) -> Array:
	var w := img.get_width()
	var h := img.get_height()
	var k := float(w) / maxf(get_viewport().get_visible_rect().size.x, 1.0)
	var oy := ORIGIN.y * k
	var top := 0.0
	var bottom := 0.0
	for y in range(0, h, 4):
		for x in range(0, w, 3):
			var c := img.get_pixel(x, y)
			if absf(c.r - 1.0) > 0.08 or absf(c.b - 1.0) > 0.08:
				var u: float = (oy - float(y)) / (PROBE_SCALE * k)
				top = minf(top, u)
				bottom = maxf(bottom, u)
	return [top, bottom]
