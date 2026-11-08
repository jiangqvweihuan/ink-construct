extends RefCounted

## 本机双人（同屏联机）输入约定。
## P1 继续沿用 project.godot 里原有的 move_left / jump / attack ... 动作；
## P2 的动作在运行时注册为 p2_ 前缀（方向键移动、跳跃、闪避 + 右侧小键盘出招），
## 不写进 project.godot，避免和设置面板里的单人改键表混在一起。

const ACTIONS := [
	"move_left", "move_right", "jump", "dash", "attack",
	"skill", "skill_sweep", "skill_ult", "skill_i", "skill_o", "skill_p",
]

## P2 默认键位：方向键（← → 移动 / ↑ 跳跃 / ↓ 闪避）+ 小键盘 1~8
const P2_BINDS := {
	"move_left": [KEY_LEFT],
	"move_right": [KEY_RIGHT],
	"jump": [KEY_UP, KEY_KP_0],
	"dash": [KEY_DOWN, KEY_KP_5],
	"attack": [KEY_KP_1],
	"skill": [KEY_KP_2],
	"skill_sweep": [KEY_KP_3],
	"skill_ult": [KEY_KP_4],
	"skill_i": [KEY_KP_6],
	"skill_o": [KEY_KP_7],
	"skill_p": [KEY_KP_8],
}

## 键位短名（面板/提示用）
const KEY_TEXT := {
	KEY_LEFT: "←", KEY_RIGHT: "→", KEY_UP: "↑", KEY_DOWN: "↓",
	KEY_KP_0: "0", KEY_KP_1: "1", KEY_KP_2: "2", KEY_KP_3: "3", KEY_KP_4: "4",
	KEY_KP_5: "5", KEY_KP_6: "6", KEY_KP_7: "7", KEY_KP_8: "8",
}

## 模式选择/开局面板上的键位说明
const HINTS := [
	"P1  WASD 移动 · 空格跳跃 · Shift 闪避 · J 普攻 · K/L/U/I/O/P 技能",
	"P2  方向键左右移动 · ↑ 跳跃 · ↓ 闪避 · 小键盘 1 普攻 · 2/3/4/6/7/8 技能",
]

static var _input_ready := false


## 把 P2 动作注册进 InputMap；幂等，可在任意场景先调。
static func ensure_input() -> void:
	if _input_ready:
		return
	_input_ready = true
	for action in ACTIONS:
		var full: String = "p2_" + str(action)
		if not InputMap.has_action(full):
			InputMap.add_action(full)
		for code in P2_BINDS.get(action, []):
			var ev := InputEventKey.new()
			ev.physical_keycode = int(code)
			InputMap.action_add_event(full, ev)


## 输入槽 -> InputMap 动作名：0 = P1 原动作，1 = P2 的 p2_ 动作
static func action(slot: int, logical: String) -> String:
	if slot == 0:
		return logical
	ensure_input()
	return "p2_" + logical


## P2 动作的首选键短名（HUD 用）
static func key_label(logical: String) -> String:
	var codes: Array = P2_BINDS.get(logical, [])
	for code in codes:
		var text := str(KEY_TEXT.get(int(code), ""))
		if text != "":
			return text
	return "-"
