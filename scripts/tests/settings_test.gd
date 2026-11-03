extends Node2D

## 设置系统验证：应用 + 持久化 + 场景切换不被打回

const Settings = preload("res://scripts/ui/settings.gd")

var _log: FileAccess

func p(msg: String) -> void:
	print("[S] ", msg)
	if _log:
		_log.store_line("[S] " + msg)
		_log.flush()

func _ready() -> void:
	_log = FileAccess.open("res://tests/settings_test.log", FileAccess.WRITE)
	get_window().size = Vector2i(1280, 720)
	await get_tree().process_frame

	# 1. 分辨率应用
	Settings.set_resolution(Vector2i(1600, 900))
	await get_tree().process_frame
	var sz := DisplayServer.window_get_size()
	p("分辨率应用: %s -> %s" % [sz, "PASS" if sz == Vector2i(1600, 900) else "FAIL"])

	# 2. 音量应用
	Settings.set_music(0.3)
	Settings.set_sfx(0.7)
	var mi := AudioServer.get_bus_index("Music")
	var si := AudioServer.get_bus_index("SFX")
	var mdb := AudioServer.get_bus_volume_db(mi)
	var sdb := AudioServer.get_bus_volume_db(si)
	p("Music bus: idx=%d db=%.2f -> %s" % [mi, mdb, "PASS" if absf(db_to_linear(mdb) - 0.3) < 0.01 else "FAIL"])
	p("SFX bus: idx=%d db=%.2f -> %s" % [si, sdb, "PASS" if absf(db_to_linear(sdb) - 0.7) < 0.01 else "FAIL"])

	# 3. 持久化文件
	var cfg := ConfigFile.new()
	var ok := cfg.load("user://settings.cfg")
	p("cfg 写盘: %s music=%s res=%s" % ["PASS" if ok == OK else "FAIL", str(cfg.get_value("audio", "music", -1)), str(cfg.get_value("video", "resolution", Vector2i.ZERO))])

	# 4. 静态状态重载模拟（重置 _loaded 再 ensure）
	Settings._loaded = false
	Settings.music_volume = 1.0
	Settings._ensure_loaded()
	p("重载读取: music=%.2f -> %s" % [Settings.music_volume, "PASS" if absf(Settings.music_volume - 0.3) < 0.01 else "FAIL"])

	# 5. 延迟后窗口保持（证明没有代码把它打回 1280）
	await get_tree().create_timer(0.3).timeout
	var sz2 := DisplayServer.window_get_size()
	p("延迟后窗口保持: %s -> %s" % [sz2, "PASS" if sz2 == Vector2i(1600, 900) else "FAIL"])

	# 6. BGM 快速 A→B→A：第一次切换遗留的淡出回调不得误停第三次复用播放器的新曲。
	BGM.play_bgm("battle")
	await get_tree().create_timer(0.2).timeout
	BGM.play_bgm("boss")
	BGM.play_bgm("battle")
	var bgm_ok: bool = BGM._current == "battle" and BGM._players[BGM._active].playing
	await get_tree().create_timer(BGM.FADE + 0.3).timeout
	bgm_ok = bgm_ok and BGM._current == "battle" and BGM._players[BGM._active].playing
	p("BGM 快速 A→B→A 后新曲仍在播: %s" % ("PASS" if bgm_ok else "FAIL"))

	# 还原默认，别污染用户配置
	Settings.set_resolution(Vector2i(1280, 720))
	Settings.set_music(1.0)
	Settings.set_sfx(1.0)
	p("已还原默认设置")
	p("ALL DONE")
	get_tree().quit(1 if not bgm_ok else 0)
