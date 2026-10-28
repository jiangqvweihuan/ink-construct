extends Node2D

## 临时工具：把指定骨架按较大尺寸摆成网格（带中线），判断默认朝向 / 武器侧。
## 用 SubViewport 定尺寸截图，不依赖游戏窗口大小。
## 用法：运行 scenes/tests/face_check.tscn -> tests/out/face_grid.png

const OUT := "res://tests/out/face_grid.png"
const COLS := 3
const CELL := Vector2i(533, 400)

const SETS := [
	{"id": "c021", "data": "res://art/characters/player/c021_data.tres", "h": 324.8},
	{"id": "pc023", "data": "res://art/characters/player/skulls/c023/c023_data.tres", "h": 262.9},
	{"id": "c016", "data": "res://art/characters/enemies/c016/c016_data.tres", "h": 308.6},
	{"id": "c017", "data": "res://art/characters/enemies/c017/c017_data.tres", "h": 502.9},
	{"id": "c012", "data": "res://art/characters/enemies/c012/c012_data.tres", "h": 262.9},
	{"id": "c013", "data": "res://art/characters/player/skulls/c013/c013_data.tres", "h": 262.9},
	{"id": "z000", "data": "res://art/characters/player/skulls/z000/z000_data.tres", "h": 285.7},
	{"id": "c035", "data": "res://art/characters/enemies/c035/c035_data.tres", "h": 262.9},
	{"id": "c037", "data": "res://art/characters/enemies/c037/c037_data.tres", "h": 365.7},
	{"id": "c018", "data": "res://art/characters/enemies/c018/c018_data.tres", "h": 274.3},
	{"id": "z002", "data": "res://art/characters/enemies/z002/z002_data.tres", "h": 308.6},
	{"id": "c009", "data": "res://art/characters/enemies/bosses/c009/c009_data.tres", "h": 628.6},
	{"id": "c015a1", "data": "res://art/characters/enemies/bosses/c015a1/c015a1_data.tres", "h": 765.7},
	{"id": "c001", "data": "res://art/characters/enemies/bosses/c001/c001_data.tres", "h": 742.9},
]


func _ready() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(CELL.x * COLS, CELL.y * int(ceil(SETS.size() / float(COLS))))
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)

	var bg := ColorRect.new()
	bg.color = Color(0.949, 0.918, 0.847)
	bg.size = Vector2(vp.size)
	vp.add_child(bg)

	var i := 0
	for s in SETS:
		var col := i % COLS
		var row := int(i / float(COLS))
		var cx := col * CELL.x + CELL.x * 0.5
		var top := row * CELL.y
		var by := top + CELL.y - 30.0
		var line := ColorRect.new()
		line.color = Color(0.72, 0.18, 0.14, 0.55)
		line.position = Vector2(cx, top)
		line.size = Vector2(1, CELL.y)
		vp.add_child(line)
		var lbl := Label.new()
		lbl.text = str(s["id"])
		lbl.position = Vector2(cx - 26.0, top + 6.0)
		lbl.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
		vp.add_child(lbl)

		var data = load(str(s["data"]))
		if data == null or not data.call("is_skeleton_data_loaded"):
			print("[FACE] FAIL ", s["id"])
			i += 1
			continue
		data.call("set_default_mix", 0.0)
		var sc: float = minf(330.0 / float(s["h"]), 0.6)
		var sp = ClassDB.instantiate("SpineSprite")
		vp.add_child(sp)
		sp.set("skeleton_data_res", data)
		sp.scale = Vector2(sc, sc)
		sp.position = Vector2(cx, by)
		var st = sp.call("get_animation_state")
		st.call("set_animation", "stand", true, 0)
		i += 1

	await get_tree().create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT))
	print("[FACE] saved ", OUT, " ", img.get_width(), "x", img.get_height())
	get_tree().quit()
