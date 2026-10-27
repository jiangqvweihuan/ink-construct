extends Node

## 连击 / 墨骨计数（autoload 名 Score）。
## 玩家每次命中 +1 连击，COMBO_WINDOW 秒内没有新命中则清零；
## 敌人死亡 +1 墨骨。两者变化通过信号广播给 HUD，切场景时调 reset()。

signal combo_changed(count: int)
signal bones_changed(count: int)

const COMBO_WINDOW := 2.0 # 连击断连的间隔（秒）
const MAX_COMBO := 999

var combo := 0
var bones := 0
var _combo_left := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## 每次成功命中调用一次。注意：多段技能一次打中多个敌人算多次命中。
func add_hit() -> void:
	combo = mini(combo + 1, MAX_COMBO)
	_combo_left = COMBO_WINDOW
	combo_changed.emit(combo)


func add_bones(n := 1) -> void:
	bones += n
	bones_changed.emit(bones)


## 消耗墨骨（换头等）。不够就返回 false，不动计数。
func spend_bones(n: int) -> bool:
	if n <= 0:
		return true
	if bones < n:
		return false
	bones -= n
	bones_changed.emit(bones)
	return true


## 进入新房间 / 重开一局时清空
func reset() -> void:
	combo = 0
	bones = 0
	_combo_left = 0.0
	combo_changed.emit(0)
	bones_changed.emit(0)


func _process(delta: float) -> void:
	if _combo_left <= 0.0:
		return
	# 顿帧期间 time_scale 极低，delta 也变得极小，连击窗口不该被拉长，这里用真实时间
	_combo_left -= delta / maxf(Engine.time_scale, 0.001)
	if _combo_left <= 0.0 and combo > 0:
		combo = 0
		combo_changed.emit(0)
