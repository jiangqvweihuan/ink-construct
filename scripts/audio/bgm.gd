extends Node

## 全局 BGM 管理器（autoload 名 BGM，跨场景常驻）
## 两条 AudioStreamPlayer 交替播放，切换时交叉淡化；输出走 Music 总线，
## 音量由 设置面板 / Settings.music_volume 统一控制。
## 曲目表改 TRACKS 即可，运行时调用 BGM.play_bgm("menu") / BGM.play_bgm("battle")。
## 同名曲目重复调用不会重头播（切场景回来不打断当前曲子）。

const TRACKS := {
	"menu": "res://audio/music/home.wav",       # 御风引 · 仙风篇（素材库 home）
	"battle": "res://audio/music/battle.wav",   # 破阵 · 侠气篇（素材库 battle）
}
const FADE := 0.9     # 交叉淡化时长（秒）
const SILENT_DB := -42.0 # 淡出目标音量，相当于静音

var _players: Array[AudioStreamPlayer] = []
var _active := -1 # 当前正在播放的播放器索引，-1 表示还没有曲子在放
var _current := "" # 当前曲目名，防同名重播


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # 暂停菜单弹出时 BGM 不中断
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.volume_db = SILENT_DB
		add_child(p)
		_players.append(p)


## 播放指定曲目（带交叉淡化）。同名曲目已在播则直接返回，不重头播。
func play_bgm(track: String) -> void:
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

	var p := _players[next]
	p.stream = stream
	p.volume_db = SILENT_DB
	p.play()

	var tw_in := create_tween()
	tw_in.tween_property(p, "volume_db", 0.0, FADE)

	if from >= 0:
		var old := _players[from]
		var tw_out := create_tween()
		tw_out.tween_property(old, "volume_db", SILENT_DB, FADE)
		tw_out.tween_callback(_stop_player.bind(from))


func _stop_player(i: int) -> void:
	if i >= 0 and i < _players.size():
		_players[i].stop()
