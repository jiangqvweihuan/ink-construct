extends Node

## 连击 / 击杀计数（autoload 名 Score）。
## 玩家每次命中 +1 连击，COMBO_WINDOW 秒内没有新命中则清零；开新一局时 reset()。

signal combo_changed(count: int)

const COMBO_WINDOW := 2.0 # 连击断连的间隔（秒）
const MAX_COMBO := 999

var combo := 0
var max_combo := 0 # 本局最高连击（结算面板战绩用）
var kills := 0 # 本局击杀数（结算战绩与墨锭收益用）
var _combo_left := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## 每次成功命中调用一次。注意：多段技能一次打中多个敌人算多次命中。
func add_hit() -> void:
	combo = mini(combo + 1, MAX_COMBO)
	max_combo = maxi(max_combo, combo)
	_combo_left = COMBO_WINDOW
	combo_changed.emit(combo)


## 击杀一只怪（与 Meta.add_kill 同处调用）
func add_kill() -> void:
	kills += 1



## 进入新房间 / 重开一局时清空
func reset() -> void:
	combo = 0
	max_combo = 0
	kills = 0
	_combo_left = 0.0
	combo_changed.emit(0)


func _process(delta: float) -> void:
	if get_tree().paused or _combo_left <= 0.0:
		return
	# 顿帧期间 time_scale 极低，delta 也变得极小，连击窗口不该被拉长，这里用真实时间
	_combo_left -= delta / maxf(Engine.time_scale, 0.001)
	if _combo_left <= 0.0 and combo > 0:
		combo = 0
		combo_changed.emit(0)
