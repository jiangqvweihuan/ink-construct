extends Node

## 字体探针：验证 gui/theme/custom 全局主题是否生效、Label 实际拿到哪个字体


func _ready() -> void:
	var log := FileAccess.open("res://tests/font_probe.log", FileAccess.WRITE)
	var l := Label.new()
	l.text = "墨构 测试"
	add_child(l)
	var f := l.get_theme_font("font")
	log.store_line("theme font = " + str(f))
	log.store_line("setting = " + str(ProjectSettings.get_setting("gui/theme/custom")))
	var t: Theme = load(str(ProjectSettings.get_setting("gui/theme/custom")))
	log.store_line("theme loaded = " + str(t))
	if t != null:
		log.store_line("default_font = " + str(t.default_font))
	log.flush()
	log.close()
	get_tree().quit()
