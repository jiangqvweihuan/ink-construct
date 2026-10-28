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
		# C023 没有 atk01~03，用 animation 当快速挥击
		"attacks": [
			{"anim": "animation", "lock": 0.42, "hits": [0.22], "damage": 1, "range": 125.0, "lunge": 110.0},
		],
		"skills": {
			# 鞭技按探针实测标定（scale=1 骨架峰值 ×0.474）：
			# skill01 鞭子甩到 786px@0.76s -> 372px，判定贴着鞭梢给
			"skill01": {
				"action": "skill", "cooldown": 4.0,
				"hits": [{"at": 0.76, "range": 370.0, "height": 130.0, "damage": 2, "sfx": "hit_heavy"}],
			},
			# skill02 长连段，最后一鞭甩满 1051px@3.53s -> 498px；前两段是近身连斩，范围递进
			"skill02": {
				"action": "skill_ult", "cooldown": 9.0,
				"hits": [
					{"at": 1.30, "range": 260.0, "height": 120.0, "damage": 1, "sfx": "skill_blade"},
					{"at": 2.30, "range": 340.0, "height": 120.0, "damage": 1, "sfx": "skill_blade"},
					{"at": 3.45, "range": 480.0, "height": 140.0, "damage": 1, "sfx": "skill_blade"},
				],
			},
		},
		"hud_skills": ["skill01", "skill02"],
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
				"reflect": 1,
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
	# ---------- 青笠：C012，青灰袍斗笠游侠，双剑近身刺击，出手快、突进远 ----------
	"c012": {
		"label": "青笠",
		"name": "顾沧洲",
		"data": "res://art/characters/player/skulls/c012/c012_data.tres",
		"scale": 0.487, # 骨架 262.9px -> 128px
		"anim": {
			"idle": "stand",
			"run": "run",
			"dash": "speed_run",
			"air": "floated",
			"hurt": "atked",
			"dead": "dead",
			"getup": "getup",
		},
		# 细剑只有一段"animation"（1.08s：下蹲蓄力 -> 前刺 -> 收剑）。
		# 探针逐帧看：0.78s 前身体还在蓄力，剑真正刺出最远在 0.95s（前伸 237px -> 115px），
		# 所以 lock 必须放到 1.05 让突刺播完，命中定在 0.95s
		"attacks": [
			{"anim": "animation", "lock": 1.05, "hits": [0.95], "damage": 1, "range": 120.0, "lunge": 170.0},
		],
		"skills": {
			# 突刺：原地刺出，判定比普攻更远
			"skill01": {
				"action": "skill", "cooldown": 3.0,
				"hits": [{"at": 0.80, "range": 150.0, "height": 110.0, "damage": 2, "sfx": "hit_heavy"}],
			},
			# 连突：跃起后两段穿刺（0.53s 前伸 271px -> 132px；1.41s 回刺 246px -> 120px）
			"skill02": {
				"action": "skill_ult", "cooldown": 8.0,
				"hits": [
					{"at": 0.55, "range": 132.0, "height": 120.0, "damage": 2, "sfx": "skill_blade"},
					{"at": 1.41, "range": 120.0, "height": 120.0, "damage": 1, "sfx": "skill_blade"},
				],
			},
		},
		"hud_skills": ["skill01", "skill02"],
	},
}


static func get_profile(id: String) -> Dictionary:
	var profile: Dictionary = SKULLS.get(id, SKULLS[DEFAULT_ID])
	return profile


static func ids() -> Array:
	return SKULLS.keys()
