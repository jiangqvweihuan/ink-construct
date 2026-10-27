extends Node2D

## 临时探针：查 Spine 动画里是否带事件关键帧（可用事件当命中帧），并列出 timeline 类型。
## 结果写 tests/anim_event_probe.log

var _log: FileAccess

func p(msg: String) -> void:
	print("[E] ", msg)
	if _log:
		_log.store_line("[E] " + str(msg))
		_log.flush()


func _ready() -> void:
	_log = FileAccess.open("res://tests/anim_event_probe.log", FileAccess.WRITE)
	for cls in ["SpineAnimation", "SpineTimeline", "SpineEventTimeline", "SpineEvent", "SpineAnimationState"]:
		p("class %s exists=%s" % [cls, str(ClassDB.class_exists(cls))])
	_dump("SpineAnimation")
	var data = load("res://art/characters/player/skulls/c013/c013_data.tres")
	p("data loaded=" + str(data != null))
	var anims = data.call("get_animations")
	p("anims=%d" % anims.size())
	for a in anims:
		var nm = str(a.call("get_name"))
		if not (nm in ["skill04", "skill02_01", "skill02_03", "skill01", "skill03", "skill02"]):
			continue
		p("--- anim %s dur=%.3f" % [nm, float(a.call("get_duration"))])
		for m in a.get_method_list():
			if str(m["name"]).to_lower().contains("timeline") or str(m["name"]).to_lower().contains("event"):
				p("    method " + str(m["name"]))
		for tl in a.call("get_timelines"):
			p("    timeline class=" + str(tl.get_class()) + " methods=" + str(_methods(tl)))
			if str(tl.get_class()).to_lower().contains("event"):
				p("      frames=" + str(tl.call("get_frame_count")))
				for i in range(int(tl.call("get_frame_count"))):
					var ev = tl.call("get_frame", i)
					p("      frame %d t=%.3f event=%s" % [i, float(ev.call("get_time")), str(ev.call("get_event"))])
	await get_tree().create_timer(0.3).timeout
	p("ALL DONE")
	get_tree().quit()


func _methods(o) -> String:
	var out: Array = []
	for m in o.get_method_list():
		out.append(str(m["name"]))
	return ", ".join(out)


func _dump(cls: String) -> void:
	var names: Array[String] = []
	for m in ClassDB.class_get_method_list(cls, true):
		names.append(m["name"])
	p("methods of %s: %s" % [cls, ", ".join(names)])
