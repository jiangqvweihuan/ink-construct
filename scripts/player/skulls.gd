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
	# 见 scripts/enemies/enemy_types.gd c012；第 5 席由银夜 z003 填补（见下）
	# ---------- 银夜：Z003，轻功剑客。普攻三段随机池 + 五技能（K/L/U/I/O） ----------
	"z003": {
		"label": "银夜",
		"name": "将去未还",
		"data": "res://art/characters/player/skulls/z003/z003_data.tres",
		"scale": 0.431, # 骨架 297.1px -> 128px
		"anim": {
			"idle": "stand",
			"run": "run",
			"dash": "autorush", # 0.083s 冲刺姿态帧，dash 时间短正好一闪而过
			"air": "jump", # 轻功跳跃动画兼滞空姿态
			"hurt": "atked",
			"dead": "atked_fall_end", # 先播一遍倒地（0.833s）
			"dead_hold": "dead", # 再循环躺尸定格（dead 只有 0.083s，不循环会闪回 setup pose）
			"getup": "getup",
		},
		"body_radius": 30.0, # 标准体型
		"dash_anim_speed": 0.4, # autorush 只有 0.083s，慢放到 0.21s 填满冲刺窗口，不再一闪而过
		# 轻功：跳得明显更高 + 跃过顶点后空中滞留一小会（独门机制，其他形态没有）
		"qinggong": {"jump_mul": 1.32, "hover": 0.32},
		# 普攻三段连击，每段从随机池抽一种动画（段段时间内再按 J 接下一段）：
		# pool=动画池，hit_at/range 按抽中的动画逐帧标定（探针 ×0.431），lock=该动画真实时长
		# 段2 带击飞（launch）：敌人往空中飞起+硬直；段3 伤害最高
		"attacks": [
			{
				"pool": ["skill03", "skill09"], "damage": 1, "lunge": 130.0,
				"hit_at": {"skill03": 0.16, "skill09": 0.50},
				"range": {"skill03": 125.0, "skill09": 135.0},
			},
			{
				"pool": ["skill04", "skill08", "skill08-cankao"], "damage": 2, "lunge": 120.0,
				"hit_at": {"skill04": 0.26, "skill08": 0.45, "skill08-cankao": 0.74},
				"range": {"skill04": 100.0, "skill08": 105.0, "skill08-cankao": 145.0},
				"launch": {"vx": 150.0, "vy": 520.0}, # 击飞：往空中挑起，落地硬直
			},
			{
				"pool": ["skill05", "skill07"], "damage": 3, "lunge": 140.0,
				"hit_at": {"skill05": 0.15, "skill07": 0.16},
				"range": {"skill05": 135.0, "skill07": 128.0},
			},
		],
		"skills": {
			# K 蓄力斩（atk03_03/atk04_02/skill01 随机，编号 #15/#17/#70）：蓄力期间霸体。
			# 三段都是双手蓄力大斩，hit_at 标"刀刃扫出"时刻（出手即判定不拖泥）：
			# atk03_03/atk04_02 取扫出中段；skill01 是起手早挥（0.23s 左挥峰值 L320≈138px，
			# 之后是长收势），标起手斩出点 0.25s——判定跟上视觉，和短动画手感一致
			# speed 0.8 慢放：原速太赶，蓄力顿挫感出不来——慢放后实长 1.21/1.44/1.98s。
			# sword_qi：预留的远程剑气接口——以后这里填 {speed, range, damage} 就会在
			# 挥剑时刻发射剑气（走 projectile 管线），现在为 null 只发近战判定
			"skill14_02": {
				"action": "skill", "cooldown": 8.0, "poise": true, "speed": 0.8,
				"pool": ["atk03_03", "atk04_02", "skill01"],
				"sword_qi": null, # 接口预留：剑气配置（未实装）
				"hit_at": {"atk03_03": 0.34, "atk04_02": 0.53, "skill01": 0.25},
				"range": {"atk03_03": 165.0, "atk04_02": 165.0, "skill01": 161.0},
				"height": 100.0, "damage": 3, "both": true, "sfx": "skill_blade",
			},
			# L 冲拳（skill02 0.883s）：不动剑的武德拳，伤害低冷却短；
			# 击退机制：命中把敌人往攻击方向轰飞，撞到同伴双方吃组合伤害、撞墙自己再吃一下
			"skill02": {
				"action": "skill_sweep", "cooldown": 3.0, "poise": true,
				"hits": [{"at": 0.71, "range": 95.0, "height": 90.0, "damage": 1, "sfx": "skill_fist",
					"knockback": {"force": 620.0, "impact": 1}}],
			},
			# U 拍地时停（skill06 1.567s）：0.5s 掌落大地，定住当前场景所有敌人——
			# 杂兵 3s / 精英 2s / Boss 1s；无视霸体，连 Boss 技能前摇都打断（规则级控制）
			"skill06": {
				"action": "skill_ult", "cooldown": 14.0, "poise": true,
				"stop": {"at": 0.5, "mob": 3.0, "elite": 2.0, "boss": 1.0},
				"hits": [],
			},
			# I 觉醒（skill10/skill18_02/skill24_03 随机）：爆气强化——立刻回血 + 限时全伤害提升。
			# align_max：池内最长 2.3s（skill18_02），抽中短动画时慢放撑满，觉醒时长恒定
			"skill10": {
				"action": "skill_i", "cooldown": 20.0, "poise": true, "align_max": true,
				"pool": ["skill10", "skill18_02", "skill24_03"],
				"heal": 2, "buff_damage": 2, "buff_time": 8.0,
				"hits": [],
			},
			# O 位移斩杀（skill11/skill11-cankao/skill23_03 随机）：向前突进一整段，
			# 路径上所有敌人吃高伤。blink 窗口 0.15~0.90s × 800px/s = 600px，全程无敌。
			# phantom_anims：#87 动画自带位移 → 改为"释放残影"——本体原地不动，残影冲出
			# 600px 斩杀沿途敌人（hit_at 0.65 残影冲到峰值时结算，path 从原地扫到残影终点），
			# 尾声零混合瞬时切 stand：残影消散、本体原地现身
			"skill11": {
				"action": "skill_o", "cooldown": 12.0, "poise": true, "invincible": true,
				"pool": ["skill11", "skill11-cankao", "skill23_03"],
				"blink_from": 0.15, "blink_to": 0.90, "blink_speed": 800.0,
				"phantom_anims": ["skill11-cankao"],
				"hit_at": {"skill11": 0.95, "skill11-cankao": 0.65, "skill23_03": 0.95},
				"range": {"skill11": 90.0, "skill11-cankao": 90.0, "skill23_03": 90.0},
				"height": 110.0, "damage": 6, "path": true, "sfx": "hit_heavy",
			},
		},
		"hud_skills": ["skill14_02", "skill02", "skill06", "skill10", "skill11"],
		# 通关结算演出：从这三个里挑一个播一遍，之后保持待机（其他形态留空=只待机，接口预留）
		"victory": ["skill17_02", "skill17_02-", "skill17_02-cankao"],
	},
}


static func get_profile(id: String) -> Dictionary:
	var profile: Dictionary = SKULLS.get(id, SKULLS[DEFAULT_ID])
	return profile


static func ids() -> Array:
	return SKULLS.keys()
