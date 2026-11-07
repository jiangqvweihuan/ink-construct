extends CanvasLayer

## 致谢名单：主界面左下角竖排「致谢」入口打开，全屏向上滚动（标准游戏致谢顺序）。
## 顺序：制作 → 开发（程序 / 美术 / 设计）→ 音频（音乐 / 音效 / 整合）→ 质量管理 → 软件与素材署名 → 特别感谢 → 版权免责 → 纠错 → 结尾。
## 音频署名按素材实况归档：音乐 10 首、音效 70 条，按战斗 / 武器技能 / 角色 / 界面 / 流程 / 人声分列。
## 自动滚到末尾后停住，滚轮上下复查；Esc 立即返回。尚未确定的署名保留空位，不显示模板占位文本。
## 打开期间只播卷终曲：普通 BGM 暂停、音效静音，Esc 返回后原样恢复。
## 右侧留白放两列竖排歌词（右列当前句、左列下一句），严格按人声实测时间轴浮现：
## 前奏先亮歌名，1:41—2:17 长间奏改画墨圈，2:53 后留住末句，整首循环时回到歌名重走。

const InkTex = preload("res://scripts/ui/ink_tex.gd")
const BODY_FONT = preload("res://art/ui/fonts/pangmen.ttf") # 庞门正道粗书体：正文
const TITLE_FONT = preload("res://art/ui/fonts/slidefu_regular.ttf") # 演示佛系体：标题 / 章节
const SFX_BACK := preload("res://audio/sfx/ui_back.wav")
const CREDITS_MUSIC := "res://audio/music/credits_roll.mp3" # 卷终曲 · 落款

const PAPER := Color(0.949, 0.918, 0.847)
const DIM := Color(0.66, 0.63, 0.58)
const GOLD := Color(0.82, 0.68, 0.42)

const SCROLL_SPEED := 56.0 # 每秒上移像素
const WHEEL_STEP := 72.0 # 播完后的单次滚轮复查步长
const COL_X := 260.0 # 正文列左边
const COL_W := 760.0 # 正文列宽（超出折行）
const START_Y := 620.0 # 进场位置：标题刚好露在屏幕下沿，打开即见内容
const END_BOTTOM_Y := 620.0 # 播完时名单底部仍留在屏幕内，不继续滚到空白

# 右侧题跋：两列竖排歌词，全部在名单正文（x ≤ 1020）之外
const LYRIC_TOP := 128.0
const LYRIC_BLOCK_H := 372.0 # 题跋可用高度：再长就自动缩字号，避免压到下方印章
const LYRIC_W := 36.0
const LYRIC_NOW_X := 1188.0 # 右列：当前句（竖排右起）
const LYRIC_NEXT_X := 1116.0 # 左列：下一句
const LYRIC_DIVIDER_X := 1086.0
const LYRIC_SEAL_X := 1188.0
const LYRIC_SEAL_Y := 518.0
const LYRIC_FONT_SIZE := 21 # 词句用庞门正道粗书体
const TITLE_FONT_SIZE := 30 # 歌名用演示佛系体
const TITLE_FADE_IN := 0.9

## 人声实测时间轴（秒）：与 CREDITS_LYRICS 逐句对应
const LYRIC_CUES := [
	16.0, 23.0, 31.0, 38.0, 45.0, 53.0, 61.0, 68.0,
	76.0, 79.0, 83.0, 86.0, 91.0, 94.0, 97.0, 101.0,
	137.0, 145.0, 151.0, 159.0, 166.0, 173.0,
]
const TITLE_END := 16.0 # 前面全是伴奏：先亮完整歌名，第一句人声起才切词
const TITLE_NOW := "卷终曲" # 右列
const TITLE_NEXT := "·落款" # 左列：与右列拼出《卷终曲 · 落款》
const LYRIC_FADE_OUT := 0.35 # 下一句人声前提前收墨
const LYRIC_FADE_IN := 0.25 # 到点换词后浮上来
const INTERLUDE_START := 105.5 # 1:41 那句唱完，进入长间奏
const INTERLUDE_END := 137.0 # 2:17 人声回来
const INTERLUDE_FADE := 0.8
const ENSO_FADE_IN := 1.5 # 墨圈起笔
const ENSO_DRAW_END := 119.0 # 画圆完成
const ENSO_FADE_OUT := 2.5 # 回收，给下一句让位

## 《落款》全词，与 LYRIC_CUES 逐句对应；与 docs/theme-songs.txt 保持一致
const CREDITS_LYRICS := [
	"一笔起于砚心 山河便有了影",
	"残页翻过千遍 仍留旧世的风",
	"谁把名字写在 卷角的空白",
	"谁的执念未散 还在字里相逢",
	"走过长街雪 也走过断桥烟",
	"刀锋与琴声 都收进这一卷",
	"有人问归途 有人只问本心",
	"我们以墨为身 便不惧墨尽",
	"卷终处 落一行款",
	"写我们 曾并肩走完",
	"山会褪 水会远 名字不散",
	"这一纸 记得所有的答案",
	"卷终处 不必圆满",
	"留白处 还等你来看",
	"墨会淡 纸会旧 灯还会燃",
	"愿此身 无悔此卷 无悔此岸",
	"若有一天 残页再翻",
	"愿你仍认得 我们的眉眼",
	"那些没说完的话",
	"就留在最后一笔的留白间",
	"砚未干 卷未合",
	"归途在下一页 等着你我",
]

## 名单数据：t = 条目类型（决定字号 / 配色 / 间距），s = 文本
const CREDITS := [
	{"t": "title", "s": "墨  构"},
	{"t": "sub", "s": "InkConstruct"},

	{"t": "section", "s": "制作"},
	{"t": "person", "s": "将去未还 —— 制作人 / 独立开发"},

	{"t": "section", "s": "开发"},
	{"t": "role", "s": "程序"},
	{"t": "person", "s": "将去未还 —— 动画衔接、技能机制与数值平衡"},
	{"t": "person", "s": "Trae CN —— 工程整合、系统调优、AI 行为逻辑"},
	{"t": "role", "s": "美术"},
	{"t": "person", "s": "将去未还 —— 界面视觉、动效与场景美术"},
	{"t": "person", "s": "爱给网 —— 部分美术素材与特效素材"},
	{"t": "role", "s": "设计"},
	{"t": "person", "s": "将去未还 —— 玩法框架、系统设计与模式设计"},
	{"t": "person", "s": "DeepSeek AI —— 早期玩法构思"},

	{"t": "section", "s": "音频"},
	{"t": "role", "s": "音乐 · 10 首"},
	{"t": "person", "s": "爱给网 —— 主菜单、战斗、守关者、图鉴、剧情与卷终曲《落款》"},
	{"t": "role", "s": "音效 · 70 条 · 爱给网"},
	{"t": "person", "s": "战斗打击：轻击、重击、拳、扇、飞刃、气劲与格挡"},
	{"t": "person", "s": "武器与技能：刀、扇、剑、爆裂、毒与拳劲"},
	{"t": "person", "s": "角色专属：刺客、武僧、琵琶、剑客、墨霆与绛曲"},
	{"t": "person", "s": "界面操作：点击、返回、面板开合、购买与换位"},
	{"t": "person", "s": "流程反馈：升级、治疗、拾取、奖励、胜负与结算"},
	{"t": "person", "s": "人声：挥砍、飞刃、施法与剑击"},
	{"t": "role", "s": "音频整合"},
	{"t": "person", "s": "将去未还 —— 音效筛选、触发时机与音量校正"},

	{"t": "section", "s": "质量管理"},
	{"t": "role", "s": "测试"},
	{"t": "person", "s": "将去未还 —— 全流程实测与回归验证"},
	{"t": "role", "s": "外部测试"},
	{"t": "person", "s": ""},
	{"t": "person", "s": ""},

	{"t": "section", "s": "软件与素材署名"},
	{"t": "role", "s": "引擎"},
	{"t": "person", "s": "Godot Engine 4.6 —— MIT License，© Juan Linietsky、Ariel Manzur 及 Godot 贡献者"},
	{"t": "role", "s": "字体"},
	{"t": "person", "s": "庞门正道粗书体 —— 庞门正道（阿门），免费商用授权"},
	{"t": "person", "s": "演示佛系体 —— 演示字体（YanShi），免费商用授权"},
	{"t": "role", "s": "骨骼动画"},
	{"t": "person", "s": "Spine 4.2 运行时 —— Esoteric Software（spine-godot，Spine Runtimes License，仅作非商业学习用途）"},

	{"t": "section", "s": "特别感谢"},
	{"t": "role", "s": "社区与玩家"},
	{"t": "person", "s": ""},
	{"t": "role", "s": "家人与朋友"},
	{"t": "person", "s": ""},
	{"t": "role", "s": "其他"},
	{"t": "person", "s": ""},

	{"t": "section", "s": "版权与免责声明"},
	{"t": "legal", "s": "1. 禁止二次传播与商业化：未经开发者许可，不得以任何形式二次传播本作品（包括但不限于游戏本体、代码、音效与美术资源），亦不得以任何手段将其用于盈利（包括但不限于售卖、出租、植入广告等）。"},
	{"t": "legal", "s": "2. 素材来源与侵权处理：本作部分美术与音频素材来源于网络，仅供学习交流。若权利人认为相关内容侵犯其权益，请致信 jiangqvweihuan@outlook.com；我方将在收到通知后第一时间核实，并立即删除相关内容。"},
	{"t": "legal", "s": "3. 游玩免责：本作为个人开发作品，因设备兼容性等原因造成的任何数据丢失或硬件问题，开发者不承担相关责任。"},

	{"t": "section", "s": "致谢纠错"},
	{"t": "person", "s": "名单如有遗漏、拼写错误或署名不当，请联系：jiangqvweihuan@outlook.com"},

	{"t": "end", "s": "感谢每一位参与者和支持者"},
]

var _scroll: Control
var _hint: Label
var _offset := 0.0 # 已上移的像素
var _total := 0.0 # 名单总高
var _max_offset := 0.0 # 最后一行停留在屏幕内时的最大偏移
var _done := false
var _sfx_muted := false # 进入前 SFX 总线是否已静音：退出时按原状态恢复
var _lyric_now: Label
var _lyric_next: Label
var _divider: ColorRect
var _enso: Enso
var _enso_word: Label # 墨圈里的极淡「留白」二字
var _shown_kind := "" # 当前题跋形态：title / verse，避免每帧重设字体与文本
var _shown_idx := -1 # 已渲染的词句下标
var _dx := 0.0 # 画布比 1280 宽时整体右移的偏移（手机 20:9 用），保证整版居中
var _closing := false
var _opened_ms := 0.0 # 打开时刻：放过「点开致谢」那一下的触摸，否则面板刚开就被自己关掉


func _ready() -> void:
	layer = 12
	_build()
	_enter_audio()
	set_process(true)
	# 计时放在最后：加载字体/纹理要一会儿，而安卓「点开致谢」那一手的触摸事件
	# 是在本函数返回后才派发过来的，必须从可以交互的时刻开始算宽限。
	_opened_ms = float(Time.get_ticks_msec())


func _exit_tree() -> void:
	BGM.stop_solo()
	var sfx := AudioServer.get_bus_index("SFX")
	if sfx >= 0:
		AudioServer.set_bus_mute(sfx, _sfx_muted)


## 致谢期间只留卷终曲：普通 BGM 暂停（保留进度），音效总线静音；退出时恢复。
func _enter_audio() -> void:
	BGM.play_solo(CREDITS_MUSIC)
	var sfx := AudioServer.get_bus_index("SFX")
	if sfx >= 0:
		_sfx_muted = AudioServer.is_bus_mute(sfx)
		AudioServer.set_bus_mute(sfx, true)


func _process(delta: float) -> void:
	_lyric_tick() # 名单停住后歌词仍随音乐继续走
	if _done:
		return
	_offset = minf(_offset + SCROLL_SPEED * delta, _max_offset)
	_scroll.position.y = -_offset
	if _offset >= _max_offset:
		_finish()


func _input(event: InputEvent) -> void:
	# 返回：Esc（桌面）/ 轻点（手机）。手机上全屏遮罩是 MOUSE_FILTER_STOP，点击会被它吃掉，
	# 到不了 _unhandled_input，所以必须在这里接住。
	var back := event.is_action_pressed("ui_cancel")
	if not back and _is_back_tap(event):
		back = true
	if back:
		get_viewport().set_input_as_handled()
		_close()
		return
	# 播完后滚轮上下复查（仅桌面；手机靠点按/拖动浏览，见 _gui_input 无需处理）
	if not _done or not (event is InputEventMouseButton) or not event.pressed:
		return
	var wheel := event as InputEventMouseButton
	var step := 0.0
	match wheel.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			step = -WHEEL_STEP
		MOUSE_BUTTON_WHEEL_DOWN:
			step = WHEEL_STEP
		_:
			return
	get_viewport().set_input_as_handled()
	_offset = clampf(_offset + step, 0.0, _max_offset)
	_scroll.position.y = -_offset


## 手机没有 Esc：轻点屏幕任意处返回（--touch-preview 时也接受鼠标左键，方便桌面验证）
## 打开后的 300ms 内不认点击：安卓会把「点开致谢」这一下拆成模拟鼠标 + 触摸两个事件，
## 触摸那份要等面板建好才派发过来，不设宽限就会刚打开就自我关闭，表现为点了没反应。
func _is_back_tap(event: InputEvent) -> bool:
	if float(Time.get_ticks_msec()) - _opened_ms < 300.0:
		return false
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).pressed
	if OS.has_feature("mobile") or OS.get_cmdline_args().has("--touch-preview"):
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			return mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
	return false


func _close() -> void:
	if _closing:
		return
	_closing = true
	var s := AudioStreamPlayer.new()
	s.bus = "SFX"
	get_tree().root.add_child(s)
	s.stream = SFX_BACK
	s.play()
	s.finished.connect(s.queue_free, CONNECT_ONE_SHOT)
	queue_free()


## 播完只停止自动滚动，保留结尾供玩家静态查看；Esc 仍可随时返回。
func _finish() -> void:
	_done = true
	_offset = clampf(_offset, 0.0, _max_offset)
	_scroll.position.y = -_offset
	_hint.text = "轻点屏幕返回" if OS.has_feature("mobile") else "滚轮上下查看 · 按 Esc 返回"


func _build() -> void:
	_dx = maxf(0.0, (get_viewport().get_visible_rect().size.x - 1280.0) * 0.5)
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
	# 子节点已经各自 +_dx 定位，这里不能再右移一次，否则正文列会压到右侧题跋上（错位）
	_scroll.position = Vector2.ZERO
	add_child(_scroll)

	var y := START_Y
	for e in CREDITS:
		y += _add(str(e["t"]), str(e["s"]), y)
	_total = y
	_max_offset = maxf(0.0, _total - END_BOTTOM_Y)

	# 固定提示：不随名单滚动
	_hint = Label.new()
	_hint.text = "按 Esc 返回" if not OS.has_feature("mobile") else "轻点屏幕返回"
	_hint.position = Vector2(920 + _dx, 676)
	_hint.size = Vector2(320, 24)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.add_theme_color_override("font_color", Color(DIM.r, DIM.g, DIM.b, 0.55))
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)
	_build_lyrics()


## 右侧题跋：淡墨竖线 + 两列竖排歌词 + 朱文款印；间奏时在同一片留白里画墨圈
func _build_lyrics() -> void:
	_divider = ColorRect.new()
	_divider.color = Color(PAPER.r, PAPER.g, PAPER.b, 0.12)
	_divider.position = Vector2(LYRIC_DIVIDER_X + _dx, 112)
	_divider.size = Vector2(1, 402)
	_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_divider)

	# 间奏过场：一管墨在空处缓画一个不合口的圈，圈里再浮出极淡的「留白」
	_enso = Enso.new()
	_enso.position = Vector2(1082 + _dx, 152)
	_enso.size = Vector2(176, 176)
	_enso.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_enso)

	_enso_word = Label.new()
	_enso_word.text = _vertical("留白")
	_enso_word.position = Vector2(74, 58)
	_enso_word.size = Vector2(28, 60)
	_enso_word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_enso_word.add_theme_font_override("font", TITLE_FONT)
	_enso_word.add_theme_font_size_override("font_size", 22)
	_enso_word.add_theme_constant_override("line_spacing", 4)
	_enso_word.add_theme_color_override("font_color", Color(0.90, 0.86, 0.78, 0.55))
	_enso_word.modulate.a = 0.0
	_enso_word.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_enso.add_child(_enso_word)

	_lyric_now = _make_lyric_column(LYRIC_NOW_X + _dx, Color(0.93, 0.90, 0.84, 0.92))
	_lyric_next = _make_lyric_column(LYRIC_NEXT_X + _dx, Color(0.72, 0.70, 0.66, 0.78))
	_build_seal()
	_show_title(0.0) # 人声未起时先亮歌名


func _make_lyric_column(x: float, color: Color) -> Label:
	var l := Label.new()
	l.position = Vector2(x, LYRIC_TOP)
	l.size = Vector2(LYRIC_W, LYRIC_BLOCK_H)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", BODY_FONT)
	l.add_theme_font_size_override("font_size", LYRIC_FONT_SIZE)
	l.add_theme_constant_override("line_spacing", 2)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


## 朱文印：只留红框与红字，透底不压纸色；整体轻转一点，像手盖上去的
func _build_seal() -> void:
	var stamp := Control.new()
	stamp.position = Vector2(LYRIC_SEAL_X + _dx, LYRIC_SEAL_Y)
	stamp.size = Vector2(36, 36)
	stamp.pivot_offset = Vector2(18, 18)
	stamp.rotation = -0.06
	stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stamp)

	var box := Panel.new()
	box.position = Vector2.ZERO
	box.size = stamp.size
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = Color(0.68, 0.19, 0.14, 0.88)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(2)
	box.add_theme_stylebox_override("panel", sb)
	stamp.add_child(box)

	var word := Label.new()
	word.text = "款"
	word.position = Vector2.ZERO
	word.size = stamp.size
	word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	word.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	word.add_theme_font_override("font", TITLE_FONT)
	word.add_theme_font_size_override("font_size", 20)
	word.add_theme_color_override("font_color", Color(0.68, 0.19, 0.14, 0.88))
	word.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stamp.add_child(word)


## 一句一行，按字竖排；原文的空格留成一格空白，读起来有句读停顿
func _vertical(text: String) -> String:
	var rows := PackedStringArray()
	for ch in text:
		rows.append("" if ch == " " else ch)
	return "\n".join(rows)


## 切字体：歌名沿用标题体，词句换成准备好的另一款（庞门正道粗书体）
func _apply_lyric_style(title: bool) -> void:
	for l in [_lyric_now, _lyric_next]:
		l.add_theme_font_override("font", TITLE_FONT if title else BODY_FONT)
		l.add_theme_font_size_override("font_size", TITLE_FONT_SIZE if title else LYRIC_FONT_SIZE)
		l.add_theme_constant_override("line_spacing", 6 if title else 2)


## 竖排一列：统一从顶部起笔；字多时逐级缩字号，保证不压到下方印章
func _render_column(l: Label, x: float, text: String, title: bool) -> void:
	l.position.x = x
	l.position.y = LYRIC_TOP
	var rows := _vertical(text)
	var base := TITLE_FONT_SIZE if title else LYRIC_FONT_SIZE
	for s in range(base, base - 4, -1):
		l.add_theme_font_size_override("font_size", s)
		l.text = rows
		if l.get_combined_minimum_size().y <= LYRIC_BLOCK_H:
			break


## 每帧都读独占曲的真实播放位置：循环回到 0 秒时歌名会自动重新出现
func _lyric_tick() -> void:
	if _lyric_now == null:
		return
	_apply_lyric_position(BGM.solo_position())


## 题跋的唯一入口：给一个播放位置就能还原整幅字
func _apply_lyric_position(pos: float) -> void:
	if _lyric_now == null:
		return
	if pos < TITLE_END:
		_show_title(pos)
	else:
		_show_verse(pos)


func _show_title(pos: float) -> void:
	if _shown_kind != "title":
		_shown_kind = "title"
		_apply_lyric_style(true)
		_render_column(_lyric_now, LYRIC_NOW_X, TITLE_NOW, true)
		_render_column(_lyric_next, LYRIC_NEXT_X, TITLE_NEXT, true)
	var a := clampf(pos / TITLE_FADE_IN, 0.0, 1.0)
	a -= clampf((pos - (TITLE_END - LYRIC_FADE_OUT)) / LYRIC_FADE_OUT, 0.0, 1.0)
	a = clampf(a, 0.0, 1.0)
	_lyric_now.modulate.a = a
	_lyric_next.modulate.a = a * 0.8
	_divider.modulate.a = a
	_enso.set_state(0.0, 0.0)
	_enso_word.modulate.a = 0.0


func _show_verse(pos: float) -> void:
	var idx := _cue_index(pos)
	if _shown_kind != "verse" or _shown_idx != idx:
		_shown_kind = "verse"
		_shown_idx = idx
		_apply_lyric_style(false)
		_render_column(_lyric_now, LYRIC_NOW_X, str(CREDITS_LYRICS[idx]), false)
		var nxt := str(CREDITS_LYRICS[idx + 1]) if idx + 1 < CREDITS_LYRICS.size() else ""
		_render_column(_lyric_next, LYRIC_NEXT_X, nxt, false) # 末句之后左列留空，只留最后一句
	var presence := _lyric_presence(pos)
	var a := _cue_alpha(pos, idx) * presence
	_lyric_now.modulate.a = a
	_lyric_next.modulate.a = a * 0.78
	_divider.modulate.a = presence
	_update_enso(pos)


## 当前句下标：最后一个已经到点的开口时刻
func _cue_index(pos: float) -> int:
	var idx := 0
	for i in LYRIC_CUES.size():
		if pos >= LYRIC_CUES[i]:
			idx = i
	return idx


## 下一句开口前 0.35s 收墨，到点换词后再用 0.25s 浮上来
func _cue_alpha(pos: float, idx: int) -> float:
	var cue: float = LYRIC_CUES[idx]
	var a := 1.0
	if pos < cue + LYRIC_FADE_IN:
		a = (pos - cue) / LYRIC_FADE_IN
	if idx + 1 < LYRIC_CUES.size():
		var nxt: float = LYRIC_CUES[idx + 1]
		if pos >= nxt - LYRIC_FADE_OUT:
			a = minf(a, (nxt - pos) / LYRIC_FADE_OUT)
	return clampf(a, 0.0, 1.0)


## 长间奏把词让出去，空出画墨圈的位置；2:17 人声回来时再浮现
func _lyric_presence(pos: float) -> float:
	if pos < INTERLUDE_START:
		return 1.0
	if pos < INTERLUDE_START + INTERLUDE_FADE:
		return 1.0 - (pos - INTERLUDE_START) / INTERLUDE_FADE
	if pos < INTERLUDE_END:
		return 0.0
	return 1.0


func _update_enso(pos: float) -> void:
	var s := 0.0
	var p := 0.0
	if pos >= INTERLUDE_START and pos <= INTERLUDE_END:
		if pos < INTERLUDE_START + ENSO_FADE_IN:
			s = (pos - INTERLUDE_START) / ENSO_FADE_IN
		elif pos < ENSO_DRAW_END:
			s = 1.0
			p = (pos - INTERLUDE_START - ENSO_FADE_IN) / (ENSO_DRAW_END - INTERLUDE_START - ENSO_FADE_IN)
		elif pos < INTERLUDE_END - ENSO_FADE_OUT:
			s = 1.0
			p = 1.0
		else:
			s = maxf(0.0, (INTERLUDE_END - pos) / ENSO_FADE_OUT)
			p = 1.0
	_enso.set_state(p, s)
	_enso_word.modulate.a = clampf((p - 0.62) / 0.38, 0.0, 1.0) * s * 0.55


## 间奏墨圈：一管墨自左下起笔，绕过一圈却不合口，收笔时点一小团墨
class Enso extends Control:
	var progress := 0.0
	var strength := 0.0
	var _last_p := -1.0
	var _last_s := -1.0

	func set_state(p: float, s: float) -> void:
		if is_equal_approx(p, _last_p) and is_equal_approx(s, _last_s):
			return
		_last_p = p
		_last_s = s
		progress = p
		strength = s
		queue_redraw()

	func _draw() -> void:
		if strength <= 0.01:
			return
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.42
		var a0 := -2.1
		var sweep := TAU * 0.92 * progress
		draw_arc(c, r, a0, a0 + sweep, 72, Color(0.90, 0.86, 0.78, 0.52 * strength), 3.4, true)
		if sweep > TAU * 0.42:
			draw_arc(c, r + 4.5, a0 + 0.22, a0 + minf(sweep, TAU * 0.72), 72,
				Color(0.90, 0.86, 0.78, 0.20 * strength), 2.0, true)
		if progress > 0.03:
			var tip := c + Vector2(cos(a0), sin(a0)) * r
			draw_circle(tip, 2.4, Color(0.90, 0.86, 0.78, 0.5 * strength))


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
	l.position = Vector2(COL_X + _dx, y + gap)
	l.size = Vector2(COL_W, h)
	_scroll.add_child(l)
	return gap + h + 8.0


## 按字体实测量宽估行数：正文有折行，不能用固定行高
func _text_height(text: String, font_size: int) -> float:
	var w := BODY_FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var lines := maxi(1, int(ceil(w / COL_W)))
	return float(lines) * float(font_size) * 1.5
