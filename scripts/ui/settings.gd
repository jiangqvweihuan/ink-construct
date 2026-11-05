extends RefCounted

## 设置管理器（静态）：音频 3 总线 / 显示模式 / 分辨率 / 帧率 / 垂直同步 / 亮度 / 屏幕震动 / 键位绑定。
## 所有改动经 set_xxx() 立即生效并写盘（user://settings.cfg）；启动时由主菜单调 apply_all()。
## 键位只允许绑键盘（InputEventKey，物理键码），Esc 永远保留给「返回/取消」不参与改键。

const PATH := "user://settings.cfg"
const RESOLUTIONS: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]

## 可改键动作 -> 默认物理键码（与 project.godot [input] 一致，恢复默认用）
const DEFAULT_BINDS := {
	"move_left": KEY_A, "move_right": KEY_D, "jump": KEY_SPACE, "dash": KEY_SHIFT,
	"attack": KEY_J, "skill": KEY_K, "skill_sweep": KEY_L, "skill_ult": KEY_U,
	"skill_i": KEY_I, "skill_o": KEY_O, "skill_p": KEY_P,
}

## 动作 -> 中文显示名（键位页/冲突提示用）
const ACTION_NAMES := {
	"move_left": "左移", "move_right": "右移", "jump": "跳跃", "dash": "闪避",
	"attack": "普攻", "skill": "技能一", "skill_sweep": "技能二", "skill_ult": "技能三",
	"skill_i": "技能四", "skill_o": "技能五", "skill_p": "技能六",
}

## 特殊键的短显示名（字母/数字直接出字符，其余兜底取 keycode 字符串前 3 位）
const KEY_TEXT := {
	KEY_SPACE: "空", KEY_SHIFT: "Sh", KEY_CTRL: "Ct", KEY_ALT: "Al", KEY_TAB: "Ta",
	KEY_ENTER: "En", KEY_UP: "↑", KEY_DOWN: "↓", KEY_LEFT: "←", KEY_RIGHT: "→",
}

static var master_volume := 1.0 # 线性 0~1
static var music_volume := 1.0
static var sfx_volume := 1.0
static var display_mode := 0 # 0 窗口化 / 1 无边框窗口 / 2 全屏
static var resolution := Vector2i(1280, 720)
static var fps_limit := 0 # 0 = 不限制
static var vsync := true
static var brightness := 1.0 # 0.5 ~ 1.5
static var screen_shake := true
static var damage_numbers := 1 # 伤害飘字：0 关闭 / 1 仅重击（≥3）/ 2 全部显示
static var binds := {} # action -> 物理键码（只记用户改过的键）
static var persist := true # 测试置 false：不写玩家配置
static var _loaded := false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	master_volume = cfg.get_value("audio", "master", 1.0)
	music_volume = cfg.get_value("audio", "music", 1.0)
	sfx_volume = cfg.get_value("audio", "sfx", 1.0)
	# 旧版只有 fullscreen 布尔，迁移成三档显示模式
	if cfg.has_section_key("video", "display_mode"):
		display_mode = cfg.get_value("video", "display_mode", 0)
	elif cfg.get_value("video", "fullscreen", false):
		display_mode = 2
	resolution = cfg.get_value("video", "resolution", Vector2i(1280, 720))
	fps_limit = cfg.get_value("video", "fps_limit", 0)
	vsync = cfg.get_value("video", "vsync", true)
	brightness = cfg.get_value("video", "brightness", 1.0)
	screen_shake = cfg.get_value("video", "screen_shake", true)
	damage_numbers = clampi(int(cfg.get_value("video", "damage_numbers", 1)), 0, 2)
	var saved: Dictionary = cfg.get_value("input", "binds", {})
	for action in saved:
		if DEFAULT_BINDS.has(action):
			binds[action] = int(saved[action])


static func _save() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("video", "display_mode", display_mode)
	cfg.set_value("video", "resolution", resolution)
	cfg.set_value("video", "fps_limit", fps_limit)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("video", "brightness", brightness)
	cfg.set_value("video", "screen_shake", screen_shake)
	cfg.set_value("video", "damage_numbers", damage_numbers)
	cfg.set_value("input", "binds", binds)
	cfg.save(PATH)


static func _ensure_bus(bus_name: String) -> int:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		idx = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")
	return idx


static func _root() -> Node:
	var ml := Engine.get_main_loop()
	return ml.root if ml is SceneTree else null


## 启动时一次性应用全部设置
static func apply_all() -> void:
	_ensure_loaded()
	AudioServer.set_bus_volume_db(_ensure_bus("Master"), linear_to_db(master_volume))
	AudioServer.set_bus_volume_db(_ensure_bus("Music"), linear_to_db(music_volume))
	AudioServer.set_bus_volume_db(_ensure_bus("SFX"), linear_to_db(sfx_volume))
	_apply_display()
	Engine.max_fps = fps_limit
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	var fx := _root().get_node_or_null("ScreenFX") if _root() != null else null
	if fx != null:
		fx.set_brightness(brightness)
	var feel := _root().get_node_or_null("Feel") if _root() != null else null
	if feel != null:
		feel.shake_enabled = screen_shake
	for action in binds: # 只覆盖用户改过的键，没改的用 project.godot 默认
		_apply_bind(action, binds[action])


## 设置面板打开时复制草稿，关闭时一次性应用，避免滑条和改键半途写盘。
static func snapshot() -> Dictionary:
	_ensure_loaded()
	return {
		"master": master_volume, "music": music_volume, "sfx": sfx_volume,
		"display_mode": display_mode, "resolution": resolution, "fps_limit": fps_limit,
		"vsync": vsync, "brightness": brightness, "screen_shake": screen_shake,
		"damage_numbers": damage_numbers,
		"binds": binds.duplicate(true),
	}


static func default_snapshot() -> Dictionary:
	return {
		"master": 1.0, "music": 1.0, "sfx": 1.0,
		"display_mode": 0, "resolution": RESOLUTIONS[0], "fps_limit": 0,
		"vsync": true, "brightness": 1.0, "screen_shake": true, "damage_numbers": 1, "binds": {},
	}


static func apply_snapshot(data: Dictionary) -> void:
	master_volume = clampf(float(data.get("master", 1.0)), 0.0, 1.0)
	music_volume = clampf(float(data.get("music", 1.0)), 0.0, 1.0)
	sfx_volume = clampf(float(data.get("sfx", 1.0)), 0.0, 1.0)
	display_mode = clampi(int(data.get("display_mode", 0)), 0, 2)
	resolution = data.get("resolution", RESOLUTIONS[0])
	fps_limit = int(data.get("fps_limit", 0))
	vsync = bool(data.get("vsync", true))
	brightness = clampf(float(data.get("brightness", 1.0)), 0.5, 1.5)
	screen_shake = bool(data.get("screen_shake", true))
	damage_numbers = clampi(int(data.get("damage_numbers", 1)), 0, 2)
	binds = (data.get("binds", {}) as Dictionary).duplicate(true)
	for action in DEFAULT_BINDS:
		_apply_bind(action, DEFAULT_BINDS[action])
	apply_all()
	_save()


static func _apply_display() -> void:
	# Godot 没有「无边框」窗口模式，无边框 = 窗口化 + WINDOW_FLAG_BORDERLESS
	match display_mode:
		2:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			DisplayServer.window_set_size(resolution)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_size(resolution)


# ---------- 音频 ----------

static func set_master(v: float) -> void:
	master_volume = v
	AudioServer.set_bus_volume_db(_ensure_bus("Master"), linear_to_db(v))
	_save()


static func set_music(v: float) -> void:
	music_volume = v
	AudioServer.set_bus_volume_db(_ensure_bus("Music"), linear_to_db(v))
	_save()


static func set_sfx(v: float) -> void:
	sfx_volume = v
	AudioServer.set_bus_volume_db(_ensure_bus("SFX"), linear_to_db(v))
	_save()


# ---------- 画面 ----------

static func set_display_mode(mode: int) -> void:
	display_mode = mode
	_apply_display()
	_save()


static func set_resolution(r: Vector2i) -> void:
	resolution = r
	if display_mode != 2: # 全屏时不改桌面窗口尺寸，只记住供退回窗口化时用
		DisplayServer.window_set_size(r)
	_save()


static func set_fps(limit: int) -> void:
	fps_limit = limit
	Engine.max_fps = limit
	_save()


static func set_vsync(on: bool) -> void:
	vsync = on
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if on else DisplayServer.VSYNC_DISABLED)
	_save()


static func set_brightness(v: float) -> void:
	brightness = clampf(v, 0.5, 1.5)
	var fx := _root().get_node_or_null("ScreenFX") if _root() != null else null
	if fx != null:
		fx.set_brightness(brightness)
	_save()


static func set_screen_shake(on: bool) -> void:
	screen_shake = on
	var feel := _root().get_node_or_null("Feel") if _root() != null else null
	if feel != null:
		feel.shake_enabled = on
	_save()


# ---------- 键位 ----------

## 键码 -> 短显示名（字母/数字出单字符，特殊键查表，其余取前 3 位）
static func key_label(code: int) -> String:
	if (code >= KEY_A and code <= KEY_Z) or (code >= KEY_0 and code <= KEY_9):
		return String.chr(code)
	var s := str(KEY_TEXT.get(code, ""))
	if s != "":
		return s
	s = OS.get_keycode_string(code)
	return s.substr(0, mini(3, s.length()))


## 动作当前生效的按键显示名（读 InputMap，改键后自动跟新）
static func action_label(action: String) -> String:
	if not InputMap.has_action(action):
		return "-"
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var k := ev as InputEventKey
			var code: int = k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
			var s := key_label(code)
			if s != "":
				return s
	return "-"


## 这个键码当前被哪个动作占用（"" = 空闲），冲突检测用
static func action_for_key(code: int) -> String:
	for action in DEFAULT_BINDS:
		if not InputMap.has_action(action):
			continue
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey and (ev.physical_keycode == code or ev.keycode == code):
				return action
	return ""


static func rebind(action: String, code: int) -> void:
	binds[action] = code
	_apply_bind(action, code)
	_save()


static func _apply_bind(action: String, code: int) -> void:
	if not InputMap.has_action(action):
		return
	InputMap.action_erase_events(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	InputMap.action_add_event(action, ev)


static func reset_binds() -> void:
	binds = {}
	for action in DEFAULT_BINDS:
		_apply_bind(action, DEFAULT_BINDS[action])
	_save()


## 恢复全部默认（面板「恢复默认设置」按钮）
static func reset_all() -> void:
	master_volume = 1.0
	music_volume = 1.0
	sfx_volume = 1.0
	display_mode = 0
	resolution = RESOLUTIONS[0]
	fps_limit = 0
	vsync = true
	brightness = 1.0
	screen_shake = true
	damage_numbers = 1
	reset_binds()
	apply_all()
