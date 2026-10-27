extends Node

## 打击感管理器（autoload 名 Feel）：顿帧 + 屏幕震动。
## 顿帧把 Engine.time_scale 短暂压到极低，制造"命中一僵"的顿挫；
## 震动抖动当前 Camera2D 的 offset。两者纯粹是表现层，不改任何伤害逻辑。
## 计时一律用真实毫秒（Time.get_ticks_msec），因为 time_scale 被压低时
## 常规 delta 也跟着变小，用它算会把顿帧无限拉长。

const HITSTOP_SCALE := 0.04 # 顿帧期间的时间流速
const MAX_HITSTOP := 0.12 # 连续命中时顿帧总时长上限，防止卡死

var _hitstop_until := 0 # 顿帧结束的毫秒时间戳，0 表示未顿帧
var _hitstop_start := 0
var _cam: Camera2D
var _shake_until := 0
var _shake_start := 0
var _shake_amt := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # 暂停时也能收尾，避免 time_scale 卡住


## 由场景在创建相机后调用，之后 shake() 才有作用对象。
func register_camera(cam: Camera2D) -> void:
	_cam = cam


## 顿帧：命中瞬间时间几近凝固 dur 秒（真实时间）。重复调用只延长、不叠加。
func hitstop(dur := 0.055) -> void:
	var now := Time.get_ticks_msec()
	if _hitstop_until > now:
		# 已在顿帧中：累加但设上限，超长会把整局卡成幻灯片
		_hitstop_until = mini(_hitstop_until + int(dur * 1000.0), _hitstop_start + int(MAX_HITSTOP * 1000.0))
		return
	_hitstop_start = now
	_hitstop_until = now + int(dur * 1000.0)
	Engine.time_scale = HITSTOP_SCALE


## 屏幕震动：amount 是像素幅度，dur 是持续秒数。取历史最大值，不叠加衰减。
func shake(amount := 5.0, dur := 0.16) -> void:
	var now := Time.get_ticks_msec()
	var until := now + int(dur * 1000.0)
	_shake_amt = maxf(_shake_amt, amount)
	if until > _shake_until:
		_shake_start = now
		_shake_until = until


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	# --- 顿帧收尾 ---
	if _hitstop_until > 0 and now >= _hitstop_until:
		_hitstop_until = 0
		Engine.time_scale = 1.0
	# --- 屏幕震动 ---
	if _cam == null or not is_instance_valid(_cam):
		return
	if _shake_until > now:
		var span := float(_shake_until - _shake_start)
		var k := 1.0 - float(now - _shake_start) / maxf(span, 1.0) # 1 -> 0 线性衰减
		_cam.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake_amt * k
	elif _shake_until != 0 or _cam.offset != Vector2.ZERO:
		_shake_until = 0
		_shake_amt = 0.0
		_cam.offset = Vector2.ZERO
