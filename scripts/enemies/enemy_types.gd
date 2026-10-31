extends RefCounted

## 敌人形态表：一个 AI 框架（scripts/enemies/c016.gd）驱动不同模型的敌人。
## 形态差异（骨架 / 缩放 / 动作名 / 招式 / 判定范围 / 命中时刻 / 血量 / 抗性）全在这里，
## 新增敌人只需加一项 + 一个只改 type_id 的 tscn。

const DEFAULT_ID := "c016"

const TYPES := {
	# ---------- 普通刀客：小怪，四种招式；三刀蓄势、升龙贴身，轻击就打断 ----------
	"c016": {
		"label": "刀客",
		"data": "res://art/characters/enemies/c016/c016_data.tres",
		"scale": 0.32, # 骨架 348px -> 约 111px
		"body_radius": 30.0,
		"elite": false,
		"anim": {"idle": "stand", "patrol": "run", "chase": "speed_run", "hurt": "atked", "dead": "dead"},
		"attacks": ["skill01", "skill02", "skill03", "skill04"],
		# 亡命三刀：三次伸展峰值 0.36 / 0.88 / 1.33；前两刀只给受击反馈，末刀才扣血。
		"hit_at": {"skill01": [0.36, 0.88, 1.33], "skill02": 1.01, "skill03": 0.87, "skill04": 0.84},
		"ranges": {"skill01": [125.0, 100.0, 144.0], "skill02": 400.0, "skill03": 109.0, "skill04": 164.0},
		"feedback_only": {"skill01": [0, 1]},
		"damage": {"skill03": 2},
		# 升龙刀：追击中 100~260px 可直接起手，先瞬到身前 72px，保留 0.87s 飞行前摇供闪避。
		"blink_strike": {"anim": "skill03", "min": 100.0, "max": 260.0, "offset": 72.0},
		# 普攻为主：特殊招式有独立冷却与触发窗口，不在近身池里等权随机。
		"attack_rules": {
			"skill01": {"weight": 6.0},
			"skill02": {"trigger": "distance", "min": 180.0, "max": 400.0, "cooldown": 8.0, "random": false},
			"skill03": {"cooldown": 12.0, "random": false},
			"skill04": {"weight": 1.0, "max": 164.0, "cooldown": 6.0},
		},
		# 高伤倒地：第 1 → 2 → 5 → 10 号动画；链中照常吃伤害，但不重触发其他受击动画。
		"knock_at": 2,
		"knock_chain": ["atked", "atked_air", "atked_fall_end", "getup"],
		"regen": {"interval": 5.0, "amount": 1}, # 山民：每 5 秒恢复 1 点，不超过生命上限
		"hp": 6,
		"patrol_speed": 60.0,
		"chase_speed": 150.0,
		"patrol_range": 120.0,
		"idle_time": 1.0,
		"detect_range": 240.0,
		"lose_range": 340.0,
		"attack_range": 180.0,
		"keep_dist": 95.0,
		"attack_cooldown": 1.8,
		"attack_lunge": 300.0,
		"hit_height": 90.0,
		"hurt_time": 0.3,
		"armor": 0, # 伤害低于这个值不会打断出手（0 = 任何轻击都硬直）
		"telegraph": false,
		"pick": "random", # random = 够得着的招里随机挑；nearest = 挑刚好够得着的最近一招
		"dead_min": 1.2, # 尸体至少停留多久再淡出
		"bar_w": 44.0,
		"bar_y": -120.0,
		"number_y": -105.0,
	},
	# ---------- 黑袍剑客：Z002，招式最全的普通怪，三段快剑 ----------
	"z002": {
		"label": "黑袍剑客",
		"data": "res://art/characters/enemies/z002/z002_data.tres",
		"scale": 0.36, # 骨架 308.6px -> 约 111px
		"body_radius": 30.0,
		"elite": false,
		"anim": {"idle": "stand", "patrol": "run", "chase": "speed_run", "hurt": "atked", "dead": "atked_fall_end"},
		"attacks": ["atk01", "atk02", "atk03"],
		# 探针实测（scale=1 峰值 -> ×0.36）：atk01 后侧 200@0.24、atk02 后侧 217@0.23、atk03 后侧 183@0.24
		# 黑袍剑客的剑从头到尾收在身侧/背后，剑锋扫向原点左侧，所以三招都判 both
		"hit_at": {"atk01": 0.24, "atk02": 0.23, "atk03": 0.24},
		"ranges": {"atk01": 72.0, "atk02": 78.0, "atk03": 57.0},
		"both": {"atk01": true, "atk02": true, "atk03": true},
		"hp": 6,
		"patrol_speed": 60.0,
		"chase_speed": 150.0,
		"patrol_range": 120.0,
		"idle_time": 1.0,
		"detect_range": 240.0,
		"lose_range": 340.0,
		"attack_range": 125.0,
		"keep_dist": 75.0,
		"attack_cooldown": 1.8,
		"attack_lunge": 300.0,
		"hit_height": 90.0,
		"hurt_time": 0.3,
		"armor": 0,
		"telegraph": false,
		"pick": "random",
		"dead_min": 0.8, # dead 只有 0.083s，靠兜底才看得见尸体
		"bar_w": 44.0,
		"bar_y": -120.0,
		"number_y": -105.0,
	},
	# ---------- 蛮兵：C017，慢速重身，巨斧横扫，骨架很高（502px） ----------
	"c017": {
		"label": "蛮兵",
		"data": "res://art/characters/enemies/c017/c017_data.tres",
		"scale": 0.221, # 骨架 502.9px -> 约 111px
		"body_radius": 36.0, # 蛮兵块头大，挨打面宽一档
		"elite": false,
		"anim": {"idle": "stand", "patrol": "walk2", "chase": "run", "hurt": "def_break", "dead": "atked_fall_end"},
		"attacks": ["skill01", "skill03_1", "skill03_2"],
		# 探针实测：skill01 后侧 509@0.52、skill03_1 后侧 586@0.62、skill03_2 前侧 649@0.38
		"hit_at": {"skill01": 0.52, "skill03_1": 0.62, "skill03_2": 0.38},
		"ranges": {"skill01": 112.0, "skill03_1": 116.0, "skill03_2": 143.0},
		# 巨斧横扫有半圈在身后，判 both
		"both": {"skill01": true, "skill03_1": true},
		"hp": 8,
		"patrol_speed": 40.0,
		"chase_speed": 105.0,
		"patrol_range": 90.0,
		"idle_time": 1.2,
		"detect_range": 230.0,
		"lose_range": 330.0,
		"attack_range": 145.0,
		"keep_dist": 90.0,
		"attack_cooldown": 2.4,
		"attack_lunge": 240.0,
		"hit_height": 95.0,
		"hurt_time": 0.4,
		"armor": 0, # 没有 atked 动作，受击用 def_break
		"telegraph": false,
		"pick": "random",
		"dead_min": 0.8,
		"bar_w": 46.0,
		"bar_y": -120.0,
		"number_y": -105.0,
	},
	# ---------- 刺客：C035，血薄但快，贴脸连刺 ----------
	"c035": {
		"label": "刺客",
		"data": "res://art/characters/enemies/c035/c035_data.tres",
		"scale": 0.422, # 骨架 262.9px -> 约 111px
		"body_radius": 28.0, # 刺客精瘦，挨打面窄一档
		"elite": false,
		"anim": {"idle": "stand", "patrol": "run", "chase": "speed_run", "hurt": "atked", "dead": "atked_fall_end"},
		"attacks": ["skill01", "skill02"],
		# 探针实测：skill01 前侧 280@0.94、skill02 前侧 306@1.38
		"hit_at": {"skill01": 0.94, "skill02": 1.38},
		"ranges": {"skill01": 118.0, "skill02": 129.0},
		"hp": 4,
		"patrol_speed": 90.0,
		"chase_speed": 195.0,
		"patrol_range": 150.0,
		"idle_time": 0.7,
		"detect_range": 300.0,
		"lose_range": 420.0,
		"attack_range": 150.0,
		"keep_dist": 80.0,
		"attack_cooldown": 1.5,
		"attack_lunge": 360.0,
		"hit_height": 85.0,
		"hurt_time": 0.25,
		"armor": 0,
		"telegraph": false,
		"pick": "random",
		"dead_min": 0.8,
		"bar_w": 40.0,
		"bar_y": -120.0,
		"number_y": -105.0,
	},
	# ---------- 精英 · 大剑骑士：C037，慢但重，一刀顶三刀 ----------
	"c037": {
		"label": "大剑骑士",
		"data": "res://art/characters/enemies/c037/c037_data.tres",
		"scale": 0.405, # 骨架 365.7px -> 约 148px
		"body_radius": 40.0,
		"elite": true,
		"anim": {"idle": "stand", "patrol": "run", "chase": "speed_run", "hurt": "atked_heavy", "dead": "atked_fall_end"},
		"attacks": ["skill01", "skill03", "skill05", "skill06"],
		# 探针实测（×0.405）：skill01 后侧 406@1.17、skill03 后侧 414@1.01、skill05 前侧 434@1.88、skill06 前侧 391@0.69
		"hit_at": {"skill01": 1.17, "skill03": 1.01, "skill05": 1.88, "skill06": 0.69},
		"ranges": {"skill01": 164.0, "skill03": 168.0, "skill05": 176.0, "skill06": 159.0},
		# 大剑横抡带大片身后弧线，判 both
		"both": {"skill01": true, "skill03": true},
		"hp": 24,
		"patrol_speed": 45.0,
		"chase_speed": 100.0,
		"patrol_range": 150.0,
		"idle_time": 1.4,
		"detect_range": 480.0,
		"lose_range": 640.0,
		"attack_range": 220.0,
		"keep_dist": 110.0,
		"attack_cooldown": 2.4,
		"attack_lunge": 220.0,
		"hit_height": 110.0,
		"hurt_time": 0.35,
		"armor": 2, # 轻击不打断
		"telegraph": true,
		"pick": "nearest",
		"dead_min": 0.8,
		"bar_w": 64.0,
		"bar_y": -170.0,
		"number_y": -180.0,
	},
	# ---------- 精英 · 双镰：C018，双持快刀，出手密集 ----------
	"c018": {
		"label": "双镰",
		"data": "res://art/characters/enemies/c018/c018_data.tres",
		"scale": 0.575, # 骨架 274.3px -> 约 148px（实测 0.54 时只有 134px，略补）
		"body_radius": 36.0,
		"elite": true,
		"anim": {"idle": "stand", "patrol": "run", "chase": "run", "hurt": "atked_heavy", "dead": "atked_fall_end"},
		"attacks": ["skill01", "skill02", "skill03"],
		# 探针实测：skill01 后侧 363@0.60、skill02 后侧 363@0.73、skill03 后侧 380@0.83
		"hit_at": {"skill01": 0.60, "skill02": 0.73, "skill03": 0.83},
		"ranges": {"skill01": 209.0, "skill02": 154.0, "skill03": 218.0},
		# 双持镰刀左右开弓，前后都扫得到，判 both
		"both": {"skill01": true, "skill02": true, "skill03": true},
		"hp": 18,
		"patrol_speed": 60.0,
		"chase_speed": 135.0,
		"patrol_range": 160.0,
		"idle_time": 1.2,
		"detect_range": 420.0,
		"lose_range": 560.0,
		"attack_range": 230.0,
		"keep_dist": 100.0,
		"attack_cooldown": 1.9,
		"attack_lunge": 300.0,
		"hit_height": 105.0,
		"hurt_time": 0.3,
		"armor": 1,
		"telegraph": true,
		"pick": "nearest",
		"dead_min": 0.8,
		"bar_w": 64.0,
		"bar_y": -175.0,
		"number_y": -185.0,
	},
	# ---------- 精英 · 青笠剑客：C012，前玩家形态下放进敌人池；快剑游侠，两连击 + 跳斩 ----------
	"c012": {
		"label": "青笠剑客",
		"data": "res://art/characters/enemies/c012/c012_data.tres",
		"scale": 0.563, # 骨架 262.9px -> 约 148px（精英身高）
		"body_radius": 36.0,
		"elite": true,
		# dead 是 0 秒空姿态，倒地用 atked_fall_end（与 z002 同款处理）
		"anim": {"idle": "stand", "patrol": "run", "chase": "speed_run", "hurt": "atked", "dead": "atked_fall_end"},
		# skill01（1.317s）= 普攻两连击：0.80s 前刺 306px、1.21s 回刺 246px（探针 scale=1 峰值）
		# skill02（1.617s）= 跳斩：腾空跃起劈落，0.89s 峰值 289px，伤害翻倍
		"attacks": ["skill01", "skill02"],
		"hit_at": {"skill01": [0.80, 1.21], "skill02": 0.89},
		# ×0.563：两连击 172 / 138，跳斩 163；ranges 与 hit_at 按段一一对应
		"ranges": {"skill01": [172.0, 138.0], "skill02": 163.0},
		"damage": {"skill02": 2}, # 跳斩伤害翻倍
		"poise_atk": {"skill02": true}, # 跳斩出手即霸体：腾空后必须让他劈下来
		"lunge_mul": {"skill02": 2.0}, # 跳斩跨步前冲更远
		"hop": {"skill02": 260.0}, # 跳斩腾空（视觉配合动画，重力自然落地）
		# 背水：血量跌破一半狂暴——出手更密、追得更紧，弥补他底子偏弱
		"enrage": {"below": 0.5, "cd": 0.65, "speed": 1.2},
		"hp": 20,
		"patrol_speed": 65.0,
		"chase_speed": 170.0, # 快剑游侠，比别的精英追得紧
		"patrol_range": 150.0,
		"idle_time": 0.8,
		"detect_range": 460.0,
		"lose_range": 620.0,
		"attack_range": 175.0,
		"keep_dist": 90.0,
		"attack_cooldown": 1.7,
		"attack_lunge": 300.0,
		"hit_height": 100.0,
		"hurt_time": 0.3,
		"armor": 1, # 轻击不打断
		"telegraph": true,
		"pick": "random", # 两招范围接近，nearest 会让跳斩永远压过两连击；随机各出一半
		"dead_min": 0.8,
		"bar_w": 64.0,
		"bar_y": -175.0,
		"number_y": -185.0,
	},
}


static func get_type(id: String) -> Dictionary:
	var type: Dictionary = TYPES.get(id, TYPES[DEFAULT_ID])
	return type
