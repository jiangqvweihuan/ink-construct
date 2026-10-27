extends Node2D

var _log: FileAccess

func p(msg: String) -> void:
	print("[P] ", msg)
	if _log:
		_log.store_line("[P] " + msg)
		_log.flush()

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests"))
	_log = FileAccess.open("res://tests/probe.log", FileAccess.WRITE)
	p("probe start")
	for cls in ["SpineSprite", "SpineAtlasResource", "SpineSkeletonFileResource", "SpineSkeletonDataResource", "SpineAnimationState", "SpineSkeleton", "SpineSkeletonData", "SpineAnimation"]:
		p("class " + cls + " exists=" + str(ClassDB.class_exists(cls)))

	p("--- load via import (.atlas) ---")
	var a1 = load("res://art/characters/player/skeleton.atlas")
	p("load(.atlas) => " + str(a1))
	if a1:
		p("class=" + a1.get_class() + " source_path=" + str(a1.call("get_source_path")) + " textures=" + str(a1.call("get_textures")))

	p("--- manual load_from_atlas_file ---")
	var a2 = ClassDB.instantiate("SpineAtlasResource")
	p("instantiate => " + str(a2))
	if a2:
		var err = a2.call("load_from_atlas_file", "res://art/characters/player/skeleton.atlas")
		p("manual err=" + str(err) + " source_path=" + str(a2.call("get_source_path")) + " textures=" + str(a2.call("get_textures")))

	p("--- skel load via import (.skel) ---")
	var s1 = load("res://art/characters/player/skeleton.skel")
	p("load(.skel) => " + str(s1))
	if s1:
		p("class=" + s1.get_class())
		_dump_methods_of("SpineSkeletonFileResource")

	p("--- skeleton data resource ---")
	var d = ClassDB.instantiate("SpineSkeletonDataResource")
	if d:
		_dump_methods_of("SpineSkeletonDataResource")
		for prop in d.get_property_list():
			if String(prop.name).begins_with("_"):
				continue
			if prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE or prop["usage"] & PROPERTY_USAGE_STORAGE:
				p("  prop: " + prop.name + " type=" + str(prop.type) + " class=" + str(prop.get("class_name", "")))

	p("probe done, idling 3s")
	await get_tree().create_timer(3.0).timeout
	get_tree().quit()

func _dump_methods_of(cls: String) -> void:
	var names: Array[String] = []
	for m in ClassDB.class_get_method_list(cls, true):
		names.append(m["name"])
	p("methods of " + cls + ": " + ", ".join(names))
