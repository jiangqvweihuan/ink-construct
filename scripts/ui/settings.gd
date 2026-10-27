extends RefCounted

## 设置管理器（静态）：音量 / 全屏 / 分辨率，立即生效 + ConfigFile 持久化到 user://settings.cfg。
## 启动时由主菜单调 apply_all()；设置面板改动走 set_xxx()。

const PATH := "user://settings.cfg"
const RESOLUTIONS: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]

static var music_volume := 1.0 # 线性 0~1
static var sfx_volume := 1.0
static var fullscreen := false
static var resolution := Vector2i(1280, 720)
static var _loaded := false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	music_volume = cfg.get_value("audio", "music", 1.0)
	sfx_volume = cfg.get_value("audio", "sfx", 1.0)
	fullscreen = cfg.get_value("video", "fullscreen", false)
	resolution = cfg.get_value("video", "resolution", Vector2i(1280, 720))


static func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "resolution", resolution)
	cfg.save(PATH)


static func _ensure_bus(bus_name: String) -> int:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		idx = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")
	return idx


## 启动时一次性应用全部设置
static func apply_all() -> void:
	_ensure_loaded()
	AudioServer.set_bus_volume_db(_ensure_bus("Music"), linear_to_db(music_volume))
	AudioServer.set_bus_volume_db(_ensure_bus("SFX"), linear_to_db(sfx_volume))
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(resolution)


static func set_music(v: float) -> void:
	music_volume = v
	AudioServer.set_bus_volume_db(_ensure_bus("Music"), linear_to_db(v))
	_save()


static func set_sfx(v: float) -> void:
	sfx_volume = v
	AudioServer.set_bus_volume_db(_ensure_bus("SFX"), linear_to_db(v))
	_save()


static func set_fullscreen(on: bool) -> void:
	fullscreen = on
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)
	if not on:
		DisplayServer.window_set_size(resolution) # 退出全屏恢复窗口大小
	_save()


static func set_resolution(r: Vector2i) -> void:
	resolution = r
	if not fullscreen:
		DisplayServer.window_set_size(r)
	_save()
