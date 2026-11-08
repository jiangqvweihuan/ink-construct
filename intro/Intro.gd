extends Control

## 启动开场：Boot Splash（纯色 #F7F5F0）→ 本体 OGV 视频（含音效）→ 原主场景。
##
## 视频由 D:\chatfin\yeturn-logo\yeturn-intro-final-v2.mp4 一次性转码为 OGV（Theora + Vorbis），
## 运行时只读不转码。任何加载/播放异常都直接放行到主场景，绝不停在开场。

const Settings = preload("res://scripts/ui/settings.gd")
const VIDEO_PATH := "res://intro/yeturn_intro.ogv"
const FALLBACK_SCENE := "res://scenes/ui/mode_select.tscn"
const PAPER := Color(0.968627, 0.960784, 0.941176) # #F7F5F0，与 boot splash 和清屏色一致
const SKIP_DELAY := 0.25 # 启动瞬间的按键（例如连点进入）不允许跳过
const FADE_TIME := 0.26 # 收尾淡出时长
const VOLUME_DB := -3.0

var _video: VideoStreamPlayer
var _mask: ColorRect
var _finished := false
var _started_at := 0.0 # 毫秒时间戳


func _ready() -> void:
	_started_at = Time.get_ticks_msec()
	# 开场就开始按玩家的显示设置铺满屏幕，避免先按小窗口播一段再跳全屏
	Settings.apply_display()
	_build()
	if Settings.intro_skip_enabled():
		_leave("设置里已关闭开场")
		return
	if not _load_stream():
		return # _load_stream 内部已提示并放行
	_video.finished.connect(_on_video_finished)
	_video.play()
	_arm_watchdog()


## 纯色底 + 视频 + 转场遮罩，全部代码构建，场景文件只保留根节点。
func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg := ColorRect.new()
	bg.color = PAPER
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_video = VideoStreamPlayer.new()
	# expand=false 时视频按原分辨率（1920×1080）绘制，画布只有 1280×720，
	# 结果只剩左上角 2/3×2/3，右下被裁掉。必须 expand=true 才会缩放到控件大小。
	# 视频 16:9、画布 1280×720 也是 16:9，等比不拉伸；非 16:9 屏幕由 stretch/aspect=keep 留边。
	_video.expand = true
	_video.loop = false
	_video.autoplay = false
	_video.volume_db = VOLUME_DB
	_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_video)
	_fit_video()
	get_viewport().size_changed.connect(_fit_video)

	_mask = ColorRect.new()
	_mask.color = Color(PAPER, 0.0)
	_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_mask)
	_mask.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## 视频按 16:9 等比铺满整屏（cover）：手机 20:9 时左右也能填满，多出的上下两截被屏幕裁掉。
## 之前是按短边等比缩放，20:9 下会留出大片左右空边，被反馈成「开场左右空白太多」。
func _fit_video() -> void:
	if _video == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var w := vp.x
	var h := w * 9.0 / 16.0
	if h < vp.y: # 屏幕比 16:9 更窄时才改由高度撑满
		h = vp.y
		w = h * 16.0 / 9.0
	_video.position = Vector2((vp.x - w) * 0.5, (vp.y - h) * 0.5)
	_video.size = Vector2(w, h)


## 载入视频；失败时提示并直接进主场景，返回是否可继续播放。
func _load_stream() -> bool:
	if not ResourceLoader.exists(VIDEO_PATH):
		_leave("开场视频缺失：%s" % VIDEO_PATH)
		return false
	var res := load(VIDEO_PATH)
	if res == null or not (res is VideoStream):
		_leave("开场视频解析失败：%s" % VIDEO_PATH)
		return false
	_video.stream = res
	if _video.stream == null:
		_leave("开场视频无法绑定到播放器：%s" % VIDEO_PATH)
		return false
	return true


## 解码卡死时兜底：按视频时长 + 2 秒收尾，避免永远停在开场。
func _arm_watchdog() -> void:
	var length := _video.get_stream_length()
	var wait := length + 2.0 if length > 0.0 else 10.0
	await get_tree().create_timer(wait).timeout
	if not _finished:
		_leave("开场视频播放超时（%.1fs）" % wait)


func _on_video_finished() -> void:
	_finish()


func _unhandled_input(event: InputEvent) -> void:
	if _finished:
		return
	if OS.has_feature("mobile"):
		return # 手机：任何触摸都不跳过，logo 必须完整播完（避免启动时的触摸/模拟鼠标事件把开场吃掉）
	if (Time.get_ticks_msec() - _started_at) / 1000.0 < SKIP_DELAY:
		return
	var skip := false
	if event is InputEventKey:
		var k := event as InputEventKey
		skip = k.pressed and not k.echo
	elif event is InputEventMouseButton:
		skip = (event as InputEventMouseButton).pressed
	elif event is InputEventJoypadButton:
		skip = (event as InputEventJoypadButton).pressed
	if not skip:
		return
	get_viewport().set_input_as_handled()
	_finish()


## 自然播完与手动跳过共用同一条收尾路径，避免重复切场景。
func _finish() -> void:
	if _finished:
		return
	_finished = true
	if _video != null:
		_video.stop()
	var tween := create_tween()
	tween.tween_property(_mask, "color:a", 1.0, FADE_TIME)
	await tween.finished
	_change_scene()


## 异常/关闭开场时直接放行：不淡出、不等待。
func _leave(reason: String) -> void:
	if _finished:
		return
	_finished = true
	push_warning("开场跳过：%s" % reason)
	if _video != null:
		_video.stop()
	# _ready 期间场景树正在挂载节点，直接切场景会撞上 remove_child 的忙碌态。
	await get_tree().process_frame
	_change_scene()


func _change_scene() -> void:
	var path := _return_scene()
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("开场结束后无法进入主场景：%s（错误码 %d）" % [path, err])


## 原主场景记录在项目设置 intro/return_scene，不写死主菜单。
func _return_scene() -> String:
	var path := str(ProjectSettings.get_setting("intro/return_scene", ""))
	if path == "" or not ResourceLoader.exists(path):
		path = FALLBACK_SCENE
	return path
