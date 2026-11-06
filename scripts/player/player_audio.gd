extends RefCounted

## 玩家音效通道：短音 / 第四段声波 / 循环技能音共用一份预载缓存。
## 由 player.gd 持有并保留同名的转发函数，外部调用点不变。

const SFX_BASE := "res://audio/sfx/"
const SFX_PRECACHE := [
	"weapon_sword",   # 普攻起手（挥剑嗖）
	"voice_sword_hit",# 普攻命中（咔劈肉）
	"voice_skill_cast",# 技能起手通用（嗡）
	"hit_heavy",      # skill01 突刺命中
	"skill_fist",     # skill03 第一段平刺
	"voice_fan_hit",  # skill03 第二段横扫
	"skill_blade",    # skill04 长连段（落叶镖）
	"hit_fist",       # 玩家受伤
	"dash_step",      # 冲刺脚步（踏地）
	"skill_boom",     # 金钟罩上罩（镇岳 K 第二段）
	"gold",           # 金钟罩挡下攻击（金属清响）
	"weapon_blade",
	"assassin_basic_attack",
	"assassin_projectile",
	"monk_basic_attack",
	"monk_bell_quake",
	"monk_vajra_wrath",
	"monk_meditation",
	"swordsman_swift_slash",
	"jiangqu_silence",
	"jiangqu_hibiscus_slash",
	"z003_k_thrust",
	"z003_l_hit",
	"z003_awaken",
	"z003_p_cast",
	"z003_night",
	"pipa_eight_tones",
	"pipa_inner_demon",
	"pipa_basic_wave",
	"pipa_sorrow",
	"pipa_mind_snare",
	"pipa_taiyu",
	"pipa_mortal_tribulation",
	"pipa_string_step",
	"golden_bell_block",
	"heal",
	"player_footstep",
	"player_hurt_sharp",
	"player_hurt_blunt",
]

var sfx_player: AudioStreamPlayer
var wave_player: AudioStreamPlayer # 第四段声波独立播放，移动和其他音效不会将其截断
var cache: Dictionary = {}

var _host: Node
var _loop_player: AudioStreamPlayer
var _loop_active := false


func _init(host: Node) -> void:
	_host = host
	sfx_player = _channel()
	wave_player = _channel()
	_loop_player = _channel()
	_loop_player.finished.connect(_on_loop_finished)
	for n in SFX_PRECACHE:
		var r: Resource = null
		for ext in ["wav", "mp3"]:
			var path: String = SFX_BASE + n + "." + ext
			if ResourceLoader.exists(path):
				r = load(path)
				break
		if r != null:
			cache[n] = r
		else:
			push_error("Player SFX not found: " + SFX_BASE + n + ".[wav|mp3]")


func _channel() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "SFX"
	_host.add_child(p)
	return p


func play(sfx_name: String) -> void:
	var s = cache.get(sfx_name)
	if s != null:
		sfx_player.stream = s
		sfx_player.play()


## 完整施法音独占临时通道，收招和其他短音都不会把它截断。
func play_full(sfx_name: String, volume_db := 0.0) -> AudioStreamPlayer:
	var source = cache.get(sfx_name)
	if source == null:
		return null
	var p := AudioStreamPlayer.new()
	p.bus = "SFX"
	p.volume_db = volume_db
	_host.add_child(p)
	p.stream = source
	p.finished.connect(p.queue_free)
	p.play()
	return p


func play_wave(sfx_name: String) -> void:
	var s = cache.get(sfx_name)
	if s != null:
		wave_player.stream = s
		wave_player.play()


func start_loop(sfx_name: String) -> void:
	stop_loop()
	var source = cache.get(sfx_name)
	if source == null:
		return
	_loop_active = true
	_loop_player.stream = source
	_loop_player.play()


func stop_loop() -> void:
	_loop_active = false
	if is_instance_valid(_loop_player):
		_loop_player.stop()
		_loop_player.stream = null


func _on_loop_finished() -> void:
	if _loop_active and is_instance_valid(_loop_player):
		_loop_player.play()
