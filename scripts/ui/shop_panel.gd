extends CanvasLayer

## 独立墨锭商栈：永久强化 / 重随秘宝 / 开局补给 / 外观收藏。
## 角色买断仍在各角色修炼页顶部；外观按化身 / 敌人类别分册出售，购买后在图鉴里更换。

const InkTex = preload("res://scripts/ui/ink_tex.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")
const Skins = preload("res://scripts/systems/skins.gd")
const SFX_CLICK := preload("res://audio/sfx/click.wav")
const SFX_PURCHASE := preload("res://audio/sfx/shop_purchase.wav")
const SFX_BACK := preload("res://audio/sfx/ui_back.wav")
const INK := Color(0.05, 0.05, 0.05)
const PAPER := Color(0.949, 0.918, 0.847)
const DIM := Color(0.82, 0.79, 0.72)
const RED := Color(0.66, 0.2, 0.16)
const GOLD := Color(0.9, 0.75, 0.3)
const TABS := {
	"permanent": "永久强化",
	"reroll": "重随秘宝",
	"supply": "开局补给",
	"appearance": "外观收藏",
}

var _tab := "permanent"
var _sfx: AudioStreamPlayer
var _appearance_enemy := false
var _appearance_owner := ""
var _appearance_pick := ""


func _ready() -> void:
	layer = 11
	_sfx = AudioStreamPlayer.new()
	_sfx.bus = "SFX"
	_sfx.stream = SFX_CLICK
	add_child(_sfx)
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.52)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	UiKit.fit_layer(self, [dim])
	var win := TextureRect.new()
	win.texture = InkTex.load("res://art/ui/menu/window_large.png")
	win.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	win.stretch_mode = TextureRect.STRETCH_SCALE
	win.position = Vector2(40, 40)
	win.size = Vector2(1200, 640)
	win.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(win)
	_text(self, "墨 锭 商 栈", Vector2(250, 52), Vector2(780, 58), 42, PAPER)
	_text(self, "墨锭 %d" % Meta.ink, Vector2(250, 112), Vector2(780, 32), 23, RED)
	_button(self, "返  回", Vector2(70, 66), Vector2(145, 48), _close, SFX_BACK)
	var keys := TABS.keys()
	for i in keys.size():
		var key := str(keys[i])
		var b := _button(self, str(TABS[key]), Vector2(150 + i * 250, 165), Vector2(220, 48), _set_tab.bind(key))
		b.modulate = Color.WHITE if key == _tab else Color(1, 1, 1, 0.6)
	if _tab == "appearance":
		_build_appearance()
		return
	var i := 0
	for key in Meta.INK_SHOP:
		var item: Dictionary = Meta.INK_SHOP[key]
		if str(item.get("tab", "")) != _tab:
			continue
		_shop_card(str(key), Vector2(120 + (i % 2) * 550, 245 + int(i / 2) * 150))
		i += 1
	var hints := {
		"permanent": "购买后永久生效，适用于所有化身",
		"reroll": "赐福重随按局计次；强化重随每次三选一刷新",
		"supply": "补给先入行囊，在「开始游戏 → 选角」页选用，开局消耗一个",
	}
	_text(self, str(hints.get(_tab, "")), Vector2(180, 570), Vector2(920, 48), 17, DIM)


func _shop_card(key: String, pos: Vector2) -> void:
	var item: Dictionary = Meta.INK_SHOP[key]
	var lv := Meta.shop_level(key)
	var cost := Meta.shop_cost(key)
	var b := TextureButton.new()
	b.texture_normal = InkTex.load("res://art/ui/menu/btn_normal.png")
	b.texture_pressed = InkTex.load("res://art/ui/menu/btn_clicked.png")
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.position = pos
	b.size = Vector2(490, 126)
	b.disabled = not Meta.can_buy(key)
	if b.disabled:
		b.modulate = Color(1, 1, 1, 0.58)
	add_child(b)
	var title := str(item["label"])
	if item.has("supply"):
		title += "  库存 %d/%d" % [lv, Meta.shop_max_level(key)]
	else:
		title += "  Lv%d/%d" % [lv, Meta.shop_max_level(key)]
	_text(b, title, Vector2(18, 10), Vector2(454, 32), 22, PAPER)
	_text(b, str(item["desc"]), Vector2(20, 47), Vector2(450, 34), 16, DIM)
	var price := "已满级" if cost < 0 and not item.has("supply") else ("库存已满" if cost < 0 else "%d 墨锭" % cost)
	_text(b, price, Vector2(18, 86), Vector2(454, 28), 18, RED if not b.disabled else DIM)
	b.pressed.connect(func():
		if Meta.buy(key):
			_play_sfx(SFX_PURCHASE)
			call_deferred("_refresh")
		else:
			_click())


func _build_appearance() -> void:
	var owners: Array = Skins.owners(_appearance_enemy)
	if not owners.has(_appearance_owner):
		_appearance_owner = str(owners[0]) if not owners.is_empty() else ""
	var hero_tab := _button(self, "主 角 外 观", Vector2(100, 224), Vector2(120, 36), _set_appearance_side.bind(false))
	hero_tab.modulate = Color.WHITE if not _appearance_enemy else Color(1, 1, 1, 0.6)
	var enemy_tab := _button(self, "敌 人 外 观", Vector2(230, 224), Vector2(120, 36), _set_appearance_side.bind(true))
	enemy_tab.modulate = Color.WHITE if _appearance_enemy else Color(1, 1, 1, 0.6)

	if owners.is_empty():
		# 图鉴还没解锁任何带外观的角色时，页面不能只剩两个分页：给出可预期的空状态说明
		if _appearance_enemy:
			_text(self, "暂无可展示的敌人外观", Vector2(100, 344), Vector2(1040, 40), 24, PAPER)
			_text(self, "在图鉴中收录带外观的敌人后，这里会自动更新",
				Vector2(100, 396), Vector2(1040, 32), 18, DIM)
		else:
			_text(self, "暂无可展示的主角外观", Vector2(100, 344), Vector2(1040, 40), 24, PAPER)
			_text(self, "在图鉴 / 化身谱中解锁带外观的化身之后，这里会自动更新",
				Vector2(100, 396), Vector2(1040, 32), 18, DIM)
		return

	var y := 276.0
	for oid in owners:
		_owner_row(str(oid), Vector2(100, y))
		y += 46.0
	if Skins.worn(_appearance_owner) != "":
		_button(self, "恢复原装", Vector2(100, y + 4), Vector2(250, 36), _reset_skin)

	if _appearance_owner == "":
		return
	var list: Array = Skins.defs(_appearance_owner, _appearance_enemy)
	_pick_default(list)
	_build_stage(Skins.find(_appearance_owner, _appearance_pick, _appearance_enemy))
	for i in list.size():
		_pick_row(list[i], Vector2(752, 276 + i * 58))
	_text(self, "点左侧分类翻册 · 点右侧条目在左侧试穿 · 价格见条目 · 购买后在图鉴中更换",
		Vector2(100, 648), Vector2(1050, 22), 14, DIM)


## 左侧分类：每个化身 / 敌种一行，附带「已穿哪套」
func _owner_row(oid: String, pos: Vector2) -> void:
	var info: Dictionary = Skins.group(oid, _appearance_enemy)
	var list: Array = Skins.defs(oid, _appearance_enemy)
	var worn := Skins.worn(oid)
	var b := TextureButton.new()
	b.texture_normal = InkTex.load("res://art/ui/menu/btn_normal.png")
	b.texture_pressed = InkTex.load("res://art/ui/menu/btn_clicked.png")
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.position = pos
	b.size = Vector2(250, 42)
	b.modulate = Color.WHITE if oid == _appearance_owner else Color(1, 1, 1, 0.78)
	add_child(b)
	_text(b, str(info.get("label", oid)), Vector2(14, 0), Vector2(222, 22), 18, PAPER)
	var sub := "%d 套" % list.size()
	if worn != "":
		var d: Dictionary = Skins.find(oid, worn, _appearance_enemy)
		sub += " · " + str(d.get("name", worn))
	_text(b, sub, Vector2(14, 21), Vector2(222, 18), 12, GOLD if worn != "" else DIM)
	b.pressed.connect(func():
		_appearance_owner = oid
		_appearance_pick = ""
		call_deferred("_refresh"))


## 中间试衣台：大图预览当前选中的皮肤（真实骨骼动画，不是静态贴图）
func _build_stage(d: Dictionary) -> void:
	var plate := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.902, 0.867, 0.784, 0.96)
	sb.border_color = Color(0.16, 0.13, 0.10, 0.38)
	sb.set_corner_radius_all(2)
	sb.set_border_width_all(1)
	plate.add_theme_stylebox_override("panel", sb)
	plate.position = Vector2(372, 276)
	plate.size = Vector2(368, 268)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(plate)
	if d.is_empty():
		return
	var sid := str(d["id"])
	var ok := _skin_loadable(sid)
	var title := str(d.get("name", sid))
	var tag := str(d.get("tag", ""))
	if tag != "":
		title += " · " + tag
	_text(self, title, Vector2(372, 546), Vector2(368, 24), 20, GOLD)
	var desc := str(d.get("desc", ""))
	if desc != "":
		_text(self, desc, Vector2(392, 570), Vector2(328, 26), 12, DIM)
	if ok:
		var data = load(Skins.data_path(_appearance_owner, sid, _appearance_enemy))
		var sprite = ClassDB.instantiate("SpineSprite")
		add_child(sprite)
		sprite.set("skeleton_data_res", data)
		data.call("set_default_mix", 0.2)
		var h := maxf(float(data.call("get_height")), 1.0)
		var sc := 238.0 / h
		sprite.scale = Vector2(sc, sc)
		sprite.position = Vector2(556, 534)
		var anim := _idle_anim(data, d)
		if anim != "":
			sprite.call("get_animation_state").call("set_animation", anim, true, 0)

	var owned := Skins.owned(_appearance_owner, sid)
	var worn := Skins.worn(_appearance_owner) == sid
	var price := Skins.price_of(d)
	var affordable := Meta.ink >= price
	if not ok:
		_text(self, "素材待补 · 暂不可购买", Vector2(372, 598), Vector2(368, 40), 15, RED)
		return
	if worn:
		var b := _button(self, "使 用 中", Vector2(372, 598), Vector2(368, 40), func(): pass)
		b.disabled = true
	elif owned:
		_button(self, "穿    戴", Vector2(372, 598), Vector2(368, 40), _wear_pick)
	elif affordable:
		_button(self, "购买 · %d 墨锭" % price, Vector2(372, 598), Vector2(368, 40), _buy_pick)
	else:
		var b2 := _button(self, "墨锭不足 · 需 %d" % price, Vector2(372, 598), Vector2(368, 40), func(): pass)
		b2.disabled = true


## 右侧条目：只负责选中，买 / 穿都在左侧试衣台确认
func _pick_row(d: Dictionary, pos: Vector2) -> void:
	var sid := str(d["id"])
	var owned := Skins.owned(_appearance_owner, sid)
	var worn := Skins.worn(_appearance_owner) == sid
	var sel := sid == _appearance_pick
	var broken := not _skin_loadable(sid)
	var b := TextureButton.new()
	b.texture_normal = InkTex.load("res://art/ui/menu/btn_normal.png")
	b.texture_pressed = InkTex.load("res://art/ui/menu/btn_clicked.png")
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.position = pos
	b.size = Vector2(398, 52)
	b.modulate = Color.WHITE if sel else Color(1, 1, 1, 0.78)
	add_child(b)
	var pic := str(d.get("portrait", ""))
	var text_x := 18.0
	var title_w := 222.0
	if pic != "" and ResourceLoader.exists(pic):
		var thumb := TextureRect.new()
		thumb.texture = load(pic)
		thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		thumb.position = Vector2(8, 8)
		thumb.size = Vector2(36, 36)
		thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(thumb)
		text_x = 52.0
		title_w = 190.0
	var title := _text(b, str(d.get("name", sid)), Vector2(text_x, 1), Vector2(title_w, 24), 18, PAPER)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var tag := str(d.get("tag", ""))
	if tag != "":
		var tag_text := _text(b, tag, Vector2(text_x, 26), Vector2(title_w, 16), 11, DIM)
		tag_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var st := "%d 墨锭" % Skins.price_of(d)
	var color := RED
	if broken:
		st = "素材待补"
		color = DIM
	elif worn:
		st = "当前穿戴"
		color = GOLD
	elif owned:
		st = "已拥有"
		color = DIM
	_text(b, st, Vector2(250, 2), Vector2(132, 26), 14, color)
	if sel:
		var bar := ColorRect.new()
		bar.color = RED
		bar.size = Vector2(3, 52)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(bar)
	b.pressed.connect(func():
		_play_sfx(SFX_CLICK)
		_appearance_pick = sid
		call_deferred("_refresh"))


## 选中项失效（换分类 / 换页）时落到已穿的那套，再不行落到第一套
func _pick_default(list: Array) -> void:
	for d in list:
		if str(d["id"]) == _appearance_pick:
			return
	var w := Skins.worn(_appearance_owner)
	if w != "" and not Skins.find(_appearance_owner, w, _appearance_enemy).is_empty():
		_appearance_pick = w
	elif not list.is_empty():
		_appearance_pick = str(list[0]["id"])
	else:
		_appearance_pick = ""


func _skin_loadable(sid: String) -> bool:
	return Skins.loadable(_appearance_owner, sid, _appearance_enemy)


## 试穿动作：优先皮肤指定的 preview，其次站姿（所有角色都被映射成 stand），最后退回第一个动画
func _idle_anim(data, d: Dictionary) -> String:
	var names := {}
	for a in data.call("get_animations"):
		names[str(a.call("get_name"))] = true
	var preview := str(d.get("preview", ""))
	if preview != "" and names.has(preview):
		return preview
	var amap: Dictionary = d.get("anim", {})
	for cand in ["stand", "idle", "daiji"]:
		var n := str(amap.get(cand, cand))
		if names.has(n):
			return n
	return str(names.keys()[0]) if not names.is_empty() else ""


func _wear_pick() -> void:
	Skins.wear(_appearance_owner, _appearance_pick)
	call_deferred("_refresh")


func _buy_pick() -> void:
	if Skins.buy(_appearance_owner, _appearance_pick, _appearance_enemy):
		_play_sfx(SFX_PURCHASE)
		call_deferred("_refresh")
	else:
		_click()


func _set_appearance_side(is_enemy: bool) -> void:
	_appearance_enemy = is_enemy
	_appearance_owner = ""
	_appearance_pick = ""
	call_deferred("_refresh")


func _reset_skin() -> void:
	Skins.wear(_appearance_owner, "")
	_appearance_pick = ""
	call_deferred("_refresh")


func _set_tab(tab: String) -> void:
	_tab = tab
	_refresh()


func _refresh() -> void:
	for c in get_children():
		if c == _sfx:
			continue
		remove_child(c)
		c.queue_free()
	_build()


func _close() -> void:
	var p := get_parent()
	queue_free()
	if p != null and p.has_method("_refresh"):
		p.call_deferred("_refresh")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_play_sfx(SFX_BACK)
		_close()
		get_viewport().set_input_as_handled()


func _play_sfx(stream: AudioStream) -> void:
	var s := AudioStreamPlayer.new()
	s.bus = "SFX"
	get_tree().root.add_child(s)
	s.stream = stream
	s.play()
	s.finished.connect(s.queue_free, CONNECT_ONE_SHOT)


func _click() -> void:
	if is_instance_valid(_sfx):
		_sfx.play()


func _button(parent: Node, text: String, pos: Vector2, size: Vector2, cb: Callable, sfx: AudioStream = SFX_CLICK) -> TextureButton:
	var b := TextureButton.new()
	b.texture_normal = InkTex.load("res://art/ui/menu/btn_normal.png")
	b.texture_pressed = InkTex.load("res://art/ui/menu/btn_clicked.png")
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.position = pos
	b.size = size
	parent.add_child(b)
	_text(b, text, Vector2.ZERO, size, 19, PAPER)
	b.pressed.connect(func():
		_play_sfx(sfx)
		cb.call())
	return b


func _text(parent: Node, text: String, pos: Vector2, size: Vector2, font_size: int, color: Color) -> Label:
	return UiKit.label(parent, text, pos, size, font_size, color, HORIZONTAL_ALIGNMENT_CENTER, true)
