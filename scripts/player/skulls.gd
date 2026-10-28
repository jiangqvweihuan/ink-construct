extends RefCounted

## 换头形态表（Skul 核心机制）：每个形态自带骨架、缩放、动画名映射、普攻段、技能表、HUD 技能顺序。
## 新增形态 = 往 SKULLS 加一项，并把 spine 三件套丢进 art/characters/player/skulls/<id>/。
##
## scale 的算法：像素探针量出骨架在 scale=1 时的墨迹高度，scale = 128 / 原始高度，
## 让所有形态在游戏里视觉上一样高（128px），不然换头会突然变大变小。
##   c021 骨架 324.8px -> 0.394
##   c023 骨架 270px   -> 0.474

const DEFAULT_ID := "c021"

const SKULLS := {
	"c021": {
		"label": "双刺", # 代称：红缨双匕 + 面纱长裙的女刺客造型
		"name": "冷红绫",
		"data": "res://art/characters/player/c021_data.tres",
		"scale": 0.394,
		"anim": {
			"idle": "stand",
			"run": "run",
			"dash": "dash_front",
			"air": "floated",
			"hurt": "atked",
			"dead": "dead",
			"getup": "getup",
		},
		# 每段普攻：lock=锁定总时长，hits=命中时刻（动画秒），range=正前方判定距离，lunge=前冲速度
		"attacks": [
			{"anim": "atk01", "lock": 0.55, "hits": [0.34], "damage": 1, "range": 100.0, "lunge": 110.0},
			{"anim": "atk02", "lock": 0.50, "hits": [0.14], "damage": 1, "range": 85.0, "lunge": 110.0},
			# atk03 是回身横扫：匕尖甩到原点左侧 92px，判 both（前后都算命中）
			{"anim": "atk03", "lock": 1.30, "hits": [0.26, 0.72], "damage": 1, "range": 95.0, "lunge": 120.0, "both": true},
		],
		"skills": {
			"skill01": {
				"action": "skill", "cooldown": 3.0,
				"hits": [{"at": 1.30, "range": 100.0, "height": 90.0, "damage": 2, "path": true, "sfx": "hit_heavy"}],
				"blink_from": 0.75, "blink_to": 1.28, "blink_speed": 520.0,
			},
			"skill03": {
				"action": "skill_sweep", "cooldown": 5.0,
				"hits": [
					{"at": 1.00, "range": 75.0, "height": 90.0, "damage": 1, "sfx": "skill_fist", "both": true},
					{"at": 2.05, "range": 88.0, "height": 110.0, "damage": 1, "sfx": "voice_fan_hit", "both": true},
				],
			},
			"skill04": {
				"action": "skill_ult", "cooldown": 9.0,
				"hits": [
					{"at": 1.30, "range": 82.0, "height": 100.0, "damage": 1, "sfx": "skill_blade"},
					{"at": 1.90, "range": 97.0, "height": 100.0, "damage": 1, "sfx": "skill_blade"},
					{"at": 2.90, "range": 72.0, "height": 110.0, "damage": 1, "sfx": "skill_blade"},
				],
			},
		},
		"hud_skills": ["skill01", "skill03", "skill04"],
	},
	"c023": {
		"label": "梅剑", # 代称：黑袍白发 + 梅花枝长剑
		"name": "白疏影",
		"data": "res://art/characters/player/skulls/c023/c023_data.tres",
		"scale": 0.474,
		"anim": {
			"idle": "stand",
			"run": "run",
			"dash": "speed_run", # 没有 dash 动画，疾走当冲刺
			"air": "floated",
			"hurt": "atked",
			"dead": "dead",
			"getup": "getup",
		},
		# 骨架 17 个动画里能实战的只有 skill01（第 13 个）和 skill02（第 14 个）；
		# "2" 是持剑站姿、animation 只有 0.383s，都撑不起招式。定位改为"数值怪"：
		# 普攻 = skill01 两段（鞭击拉回 + 前刺），唯一技能 = skill02 放 K 位。
		# skill01（1.883s）探针实测 ×0.474：0.75s 鞭梢甩到 786px -> 372px；
		# 1.68s 前刺 R297~306 -> 约 145px。两段伤害分开算（鞭 2 / 刺 3）。
		# lock 锁满整段动画且 cancel=0：普攻间隔就是动画时长，播完才能接招或移动。
		"attacks": [
			{
				"anim": "skill01", "lock": 1.883, "cancel": 0.0, "lunge": 110.0,
				"hits": [
					{"at": 0.75, "damage": 2, "range": 372.0, "pull": 80.0, "sfx": "hit_heavy"},
					{"at": 1.68, "damage": 3, "range": 145.0},
				],
			},
		],
		"skills": {
			# 唯一技能（K 位）：转鞭，skill02 4.167s。
			# 起手即霸体；0.15~3.0s 每 0.5s 对前后方 130px 内所有敌人各打 1 点（both=前后都转）；
			# 3.6s 最后一记超远甩鞭 R1051 -> 500px，伤害 2。
			# ranged_guard：转鞭期间免疫敌方投射物并原路弹回（工程暂无敌方投射物，接口已预埋）
			"skill02": {
				"action": "skill", "cooldown": 9.0,
				"poise": true,
				"ranged_guard": true,
				"tick": {"from": 0.15, "to": 3.0, "interval": 0.5, "range": 130.0, "height": 140.0, "damage": 1, "both": true},
				"hits": [{"at": 3.6, "range": 500.0, "height": 150.0, "damage": 2, "sfx": "skill_blade"}],
			},
		},
		"hud_skills": ["skill02"],
	},
	# ---------- 力僧：C013，长柄狼牙棒，动作全是挥砸，出手重、收招慢 ----------
	"c013": {
		"label": "力僧",
		"name": "定山",
		"data": "res://art/characters/player/skulls/c013/c013_data.tres",
		"scale": 0.487, # 骨架 262.9px -> 128px
		"anim": {
			"idle": "stand",
			"run": "run",
			"dash": "speed_run", # 没有 dash 动画，疾走当冲刺
			"air": "floated",
			"hurt": "atked",
			"dead": "dead",
			"getup": "getup",
		},
		# 探针实测（已乘 0.487）：skill04 前 115@0.35，skill02_01 后侧 156@0.13，skill02_03 后侧 185@0.26
		# 狼牙棒挥砸的落点在原点后方，所以普攻/挥砸类判 both，动画扫到哪边都能命中
		"attacks": [
			{"anim": "skill04", "lock": 0.62, "hits": [0.34], "damage": 1, "range": 117.0, "lunge": 110.0},
			{"anim": "skill02_01", "lock": 0.44, "hits": [0.13], "damage": 1, "range": 156.0, "lunge": 120.0, "both": true},
			{"anim": "skill02_03", "lock": 0.47, "hits": [0.26], "damage": 2, "range": 185.0, "lunge": 130.0, "both": true},
		],
		"skills": {
			"skill01": {
				"action": "skill", "cooldown": 3.5,
				"hits": [{"at": 0.60, "range": 198.0, "height": 110.0, "damage": 2, "sfx": "skill_fist", "both": true}],
			},
			"skill03": {
				"action": "skill_sweep", "cooldown": 5.0,
				"hits": [{"at": 0.87, "range": 191.0, "height": 110.0, "damage": 1, "sfx": "voice_fan_hit"}],
			},
			# 全程举棒蓄力，3.05s 才砸下来：砸地只回血、不打伤害
			# 定山：蓄力期间自身霸体 + 反伤（挨打把伤害弹回攻击者），砸地回 2 血——站桩挨打换血的坦克循环
			"skill02": {
				"action": "skill_ult", "cooldown": 9.0,
				"poise": true,
				"reflect": true,
				"hits": [
					{"at": 3.12, "heal": 2, "sfx": "skill_blade"},
				],
			},
		},
		"hud_skills": ["skill01", "skill03", "skill02"],
	},
	# ---------- 剑仙：Z000，持剑的远程剑客，招式最全（92 个动画），挥剑放剑气 ----------
	"z000": {
		"label": "剑仙",
		"name": "洛惊鸿",
		"data": "res://art/characters/player/skulls/z000/z000_data.tres",
		"scale": 0.448, # 骨架 285.7px -> 128px
		"anim": {
			"idle": "stand",
			"run": "run",
			"dash": "dash_front",
			"air": "floated",
			"hurt": "atked",
			"dead": "dead",
			"getup": "getup",
		},
		# 剑仙是真远程：每次挥剑甩出一道剑气（projectile），不再用身前近战判定
		"attacks": [
			{"anim": "atk01", "lock": 0.42, "hits": [0.22], "damage": 1, "lunge": 120.0, "projectile": {"speed": 500.0, "range": 400.0}},
			{"anim": "atk02", "lock": 0.48, "hits": [0.20], "damage": 1, "lunge": 110.0, "projectile": {"speed": 500.0, "range": 400.0}},
			{"anim": "atk03", "lock": 0.36, "hits": [0.27], "damage": 1, "lunge": 110.0, "projectile": {"speed": 520.0, "range": 420.0}},
		],
		"skills": {
			"skill01": {
				"action": "skill", "cooldown": 3.0,
				"hits": [{"at": 0.54, "damage": 2, "sfx": "hit_heavy", "projectile": {"speed": 540.0, "range": 440.0}}],
			},
			"skill02": {
				"action": "skill_sweep", "cooldown": 5.0,
				"hits": [{"at": 0.91, "damage": 1, "sfx": "skill_fist", "projectile": {"speed": 540.0, "range": 440.0}}],
			},
			"skill04": {
				"action": "skill_ult", "cooldown": 9.0,
				"hits": [
					{"at": 0.30, "damage": 1, "sfx": "skill_blade", "projectile": {"speed": 560.0, "range": 460.0}},
					{"at": 0.67, "damage": 1, "sfx": "skill_blade", "projectile": {"speed": 560.0, "range": 460.0}},
				],
			},
		},
		"hud_skills": ["skill01", "skill02", "skill04"],
	},
	# 青笠 c012 已下掉玩家形态（动画撑不起招式，强度垫底），转生为精英怪——
	# 见 scripts/enemies/enemy_types.gd c012；第 5 席等新素材填补
}


static func get_profile(id: String) -> Dictionary:
	var profile: Dictionary = SKULLS.get(id, SKULLS[DEFAULT_ID])
	return profile


static func ids() -> Array:
	return SKULLS.keys()
