extends Node

## 全局 BGM 管理器（autoload 名 BGM，跨场景常驻）
## 两条 AudioStreamPlayer 交替播放，切换时交叉淡化；输出走 Music 总线，
## 音量由 设置面板 / Settings.music_volume 统一控制。
## 曲目表改 TRACKS 即可，运行时调用 BGM.play_bgm("menu") / BGM.play_bgm("battle")。
## 同名曲目重复调用不会重头播（切场景回来不打断当前曲子）。

const TRACKS := {
	"menu": "res://audio/music/home.wav",       # 御风引 · 仙风篇（素材库 home）
	"menu_02": "res://audio/music/menu_02.wav",
	"battle": "res://audio/music/battle.wav",   # 破阵 · 侠气篇（素材库 battle）
	"boss": "res://audio/music/boss.wav",
}
const FADE := 0.9     # 交叉淡化时长（秒）
const SILENT_DB := -42.0 # 淡出目标音量，相当于静音

var _players: Array[AudioStreamPlayer] = []
var _fades: Dictionary = {} # 播放器索引 -> 当前淡化；切换代际时先取消旧回调
var _active := -1 # 当前正在播放的播放器索引，-1 表示还没有曲子在放
var _current := "" # 当前曲目名，防同名重播
var _menu_rng := RandomNumberGenerator.new()
var _solo: AudioStreamPlayer # 独占曲目（致谢等）：普通 BGM 让位时使用
var _solo_paused: Array[AudioStreamPlayer] = [] # 被暂停的普通 BGM，退出独占时恢复
var _voice: AudioStreamPlayer # 旁白 / 剧情音轨：独立通道，可整体掐断，不碰点击与战斗音效


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # 暂停菜单弹出时 BGM 不中断
	_menu_rng.randomize()
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.volume_db = SILENT_DB
		add_child(p)
		_players.append(p)
	_voice = AudioStreamPlayer.new()
	_voice.bus = "SFX" # 旁白走音效总线，跟随玩家的音效音量
	add_child(_voice)


## 播放指定曲目（带交叉淡化）。同名曲目已在播则直接返回，不重头播。
func play_bgm(track: String) -> void:
	if track == "menu":
		track = "menu_02" if _menu_rng.randi() % 2 == 0 else "menu"
	if track == _current:
		return
	var path = TRACKS.get(track)
	if path == null:
		push_error("BGM: 未知曲目 " + track)
		return
	var stream = load(path)
	if stream == null:
		push_error("BGM: 加载失败 " + path)
		return
	# OGG/MP3 用 stream.loop = true；WAV 的循环在导入参数里开（.import: edit/loop_mode=2 Forward），
	# 导入器会把 loop 区间烘焙进资源——运行时别手动设 loop_end（WAV 已压缩成 QOA 算不出帧数，
	# 设 0 会让循环区间为空、曲子进循环即静音）
	if stream is AudioStreamOggVorbis or stream is AudioStreamMP3:
		stream.loop = true
	_current = track

	var from := _active
	var next := (1 - _active) if _active >= 0 else 0
	_active = next
	_cancel_fade(next)
	if from >= 0:
		_cancel_fade(from)

	var p := _players[next]
	p.stream = stream
	p.volume_db = SILENT_DB
	p.play()

	var tw_in := create_tween()
	_fades[next] = tw_in
	tw_in.tween_property(p, "volume_db", 0.0, FADE)

	if from >= 0:
		var old := _players[from]
		var tw_out := create_tween()
		_fades[from] = tw_out
		tw_out.tween_property(old, "volume_db", SILENT_DB, FADE)
		tw_out.tween_callback(_stop_player.bind(from))


func _cancel_fade(i: int) -> void:
	var tween: Tween = _fades.get(i)
	if tween != null and tween.is_valid():
		tween.kill()
	_fades.erase(i)


func _stop_player(i: int) -> void:
	if i >= 0 and i < _players.size():
		_players[i].stop()


## 独占曲目（致谢等）：暂停普通 BGM（保留播放进度），只播这一首；结束调 stop_solo 恢复。
## gain_db 是这首曲目单独的增益偏移（不写入用户音量设置），用来压掉混音偏响的曲子。
func play_solo(path: String, gain_db: float = 0.0) -> void:
	stop_solo()
	var stream = load(path)
	if stream == null:
		push_error("BGM: 独占曲目加载失败 " + path)
		return
	if stream is AudioStreamOggVorbis or stream is AudioStreamMP3:
		stream.loop = true
	if _solo == null:
		_solo = AudioStreamPlayer.new()
		_solo.bus = "Music"
		add_child(_solo)
	for p in _players:
		if p.playing:
			_solo_paused.append(p)
			p.stream_paused = true
	_solo.stream = stream
	_solo.volume_db = gain_db
	_solo.play()


## 独占曲目当前播放位置（秒）：循环播放时由引擎自动回到 0，歌词可按真实人声对轴。
func solo_position() -> float:
	return _solo.get_playback_position() if _solo != null and _solo.playing else 0.0


## 退出独占：停掉独占曲，普通 BGM 从原进度继续（音量与曲目状态都不动）。
func stop_solo() -> void:
	if _solo != null and _solo.playing:
		_solo.stop()
	for p in _solo_paused:
		if is_instance_valid(p):
			p.stream_paused = false
	_solo_paused.clear()


## 播放一段旁白（剧情音轨）：独立播放器，同一时间只留一段，重复调用先停旧的再从头播。
func play_voice(path: String, volume_db: float = 0.0) -> void:
	stop_voice()
	var stream = load(path)
	if stream == null:
		push_error("BGM: 旁白加载失败 " + path)
		return
	_voice.stream = stream
	_voice.volume_db = volume_db
	_voice.play()


## 立刻掐掉旁白（选定模式 / 进对局时调用）。只动旁白通道，BGM 与任何音效都不受影响。
func stop_voice() -> void:
	if _voice == null:
		return
	if _voice.playing:
		_voice.stop()
	_voice.stream = null


## 旁白是否正在播放（测试与流程判断用）。
func voice_playing() -> bool:
	return _voice != null and _voice.playing
