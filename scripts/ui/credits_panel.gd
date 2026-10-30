extends CanvasLayer

## 致谢名单：主界面左下角竖排「致谢」入口打开，全屏向上滚动（标准游戏致谢顺序）。
## 顺序：制作 → 核心开发团队 → 外部协作 → 软件与素材署名 → 特别感谢 → 版权免责 → 纠错 → 结尾。
## 自动滚动，Esc 立即返回；滚完自动淡出。没填的项保留【】占位，等全部开发完成后统一核验。

const InkTex = preload("res://scripts/ui/ink_tex.gd")
const BODY_FONT = preload("res://art/ui/fonts/pangmen.ttf") # 庞门正道粗书体：正文
const TITLE_FONT = preload("res://art/ui/fonts/slidefu_regular.ttf") # 演示佛系体：标题 / 章节

const PAPER := Color(0.949, 0.918, 0.847)
const DIM := Color(0.66, 0.63, 0.58)
const GOLD := Color(0.82, 0.68, 0.42)

const SCROLL_SPEED := 56.0 # 每秒上移像素
const COL_X := 260.0 # 正文列左边
const COL_W := 760.0 # 正文列宽（超出折行）
const START_Y := 620.0 # 进场位置：标题刚好露在屏幕下沿，打开即见内容

## 名单数据：t = 条目类型（决定字号 / 配色 / 间距），s = 文本
const CREDITS := [
	{"t": "title", "s": "墨  构"},
	{"t": "sub", "s": "InkConstruct"},

	{"t": "section", "s": "制作 / 项目管理"},
	{"t": "person", "s": "将去未还 —— 独立制作人和负责人"},

	{"t": "section", "s": "核心开发团队"},
	{"t": "role", "s": "程序"},
	{"t": "person", "s": "将去未还 —— 动画衔接，技能机制逻辑与数值"},
	{"t": "person", "s": "Trae CN —— 统筹合并，细节优化，AI 逻辑"},
	{"t": "role", "s": "美术"},
	{"t": "person", "s": "将去未还 —— UI 美化，音效特效收集"},
	{"t": "person", "s": "爱给网 —— 美术素材以及特效音频"},
	{"t": "role", "s": "设计"},
	{"t": "person", "s": "将去未还 —— 游戏玩法和全部设计思路和模式"},
	{"t": "person", "s": "DeepSeek AI —— 基础玩法的构建想法"},
	{"t": "role", "s": "音频"},
	{"t": "person", "s": "爱给网 —— 所有音频来源"},
	{"t": "role", "s": "QA / 测试"},
	{"t": "person", "s": "将去未还 —— 全流程实测"},

	{"t": "section", "s": "软件、中间件与素材署名"},
	{"t": "role", "s": "引擎与工具"},
	{"t": "person", "s": "Godot Engine 4.6 —— MIT License，© Juan Linietsky / Ariel Manzur 及 Godot 贡献者"},
	{"t": "role", "s": "字体"},
	{"t": "person", "s": "庞门正道粗书体 —— 庞门正道（阿门），免费商用授权"},
	{"t": "person", "s": "演示佛系体 —— 演示字体（YanShi），免费商用授权"},
	{"t": "role", "s": "音效 / 音乐素材"},
	{"t": "person", "s": "爱给网 —— 所有音频来源"},
	{"t": "person", "s": "【素材名称】——【作者 / 授权方】"},
	{"t": "role", "s": "开源库 / 插件"},
	{"t": "person", "s": "spine-godot 4.2 —— Esoteric Software（Spine Runtimes License，仅作非商业学习用途）"},

	{"t": "section", "s": "特别感谢"},
	{"t": "role", "s": "社区与玩家"},
	{"t": "person", "s": "【社区名称 / 玩家群体】"},
	{"t": "person", "s": "【特别感谢对象】"},
	{"t": "role", "s": "家人与朋友"},
	{"t": "person", "s": "【姓名】"},
	{"t": "person", "s": "【姓名】"},
	{"t": "role", "s": "其他特别感谢"},
	{"t": "person", "s": "【姓名 / 团队】——【感谢原因】"},

	{"t": "section", "s": "版权与免责声明"},
	{"t": "legal", "s": "1. 禁止二次传播与商业化：本游戏未取得开发者的许可，不得进行任何形式的二次传播（包含但不限于游戏本体、代码、音效、美术资源）。同时，严禁以任何手段利用本游戏进行盈利操作（包括但不限于售卖、出租、植入广告等盈利操作）。"},
	{"t": "legal", "s": "2. 素材来源与侵权处理：本游戏内大部分美术、音频等素材均获取于网络，仅供学习交流使用。若您（原作者）认为内容侵犯了您的权益，请务必联系邮箱：jiangqvweihuan@outlook.com 进行反馈。我方将在收到通知的第一时间核实，并立即删除相关内容。"},
	{"t": "legal", "s": "3. 游玩免责：本游戏为个人开发作品，玩家在游玩过程中因设备兼容性等原因造成的任何数据丢失或硬件问题，开发者不承担相关责任。"},

	{"t": "section", "s": "致谢纠错"},
	{"t": "person", "s": "如名单有遗漏、拼写错误或署名问题，请联系：jiangqvweihuan@outlook.com"},

	{"t": "end", "s": "感谢每一位参与者和支持者"},
]

var _scroll: Control
var _offset := 0.0 # 已上移的像素
var _total := 0.0 # 名单总高（滚过这个值即播完）
var _done := false


func _ready() -> void:
	layer = 12
	_build()
	set_process(true)


func _process(delta: float) -> void:
	if _done:
		return
	_offset += SCROLL_SPEED * delta
	_scroll.position.y = -_offset
	if _offset >= _total:
		_finish()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		queue_free()


## 滚完：淡出后自动回主菜单（不漏掉最后一行的阅读时间，所以淡出 0.8s）
func _finish() -> void:
	_done = true
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.8)
	tw.tween_callback(queue_free)


func _build() -> void:
	var bg := TextureRect.new()
	bg.texture = InkTex.load("res://art/environment/background/bg_mountains.jpg")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.modulate = Color(0.42, 0.40, 0.44) # 远山压暗当底纹
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP # 全屏遮罩吃掉点击，否则会穿透到底下的主菜单按钮
	add_child(dim)

	_scroll = Control.new()
	_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_scroll)

	var y := START_Y
	for e in CREDITS:
		y += _add(str(e["t"]), str(e["s"]), y)
	_total = y

	# 固定提示：不随名单滚动
	var hint := Label.new()
	hint.text = "按 Esc 返回"
	hint.position = Vector2(1080, 676)
	hint.size = Vector2(160, 24)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.add_theme_color_override("font_color", Color(DIM.r, DIM.g, DIM.b, 0.55))
	hint.add_theme_font_size_override("font_size", 14)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)


## 放一条名单，返回它占的高度（含上方间距）
func _add(kind: String, text: String, y: float) -> float:
	var font_size := 19
	var color := PAPER
	var gap := 2.0 # 本条上方间距
	var align := HORIZONTAL_ALIGNMENT_CENTER
	match kind:
		"title":
			font_size = 64
			gap = 0.0
		"sub":
			font_size = 20
			color = DIM
			gap = 10.0
		"section":
			font_size = 28
			color = GOLD
			gap = 40.0
		"role":
			font_size = 17
			color = Color(DIM.r, DIM.g, DIM.b, 0.85)
			gap = 16.0
		"person":
			font_size = 19
			gap = 2.0
		"legal":
			font_size = 15
			color = DIM
			gap = 10.0
			align = HORIZONTAL_ALIGNMENT_LEFT
		"end":
			font_size = 26
			color = GOLD
			gap = 64.0

	var h := _text_height(text, font_size)
	var l := Label.new()
	l.text = text
	# 先定折行与对齐，最后才给 size：反过来设的话 Label 的最小尺寸会把宽度顶回去、长条款不折行
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = align
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_font_override("font", TITLE_FONT if kind in ["title", "section"] else BODY_FONT)
	l.add_theme_constant_override("line_spacing", 6) # 折行条款的行距，太挤会糊成一坨
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.position = Vector2(COL_X, y + gap)
	l.size = Vector2(COL_W, h)
	_scroll.add_child(l)
	return gap + h + 8.0


## 按字体实测量宽估行数：正文有折行，不能用固定行高
func _text_height(text: String, font_size: int) -> float:
	var w := BODY_FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var lines := maxi(1, int(ceil(w / COL_W)))
	return float(lines) * float(font_size) * 1.5
