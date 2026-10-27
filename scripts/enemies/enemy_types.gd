extends RefCounted

## 敌人形态表：一个 AI 框架（scripts/enemies/c016.gd）驱动不同模型的敌人。
## 形态差异（骨架 / 缩放 / 动作名 / 招式 / 判定范围 / 命中时刻 / 血量 / 抗性）全在这里，
## 新增敌人只需加一项 + 一个只改 type_id 的 tscn。

const DEFAULT_ID := "c016"

const TYPES := {
	# ---------- 普通刀客：小怪，5 种挥砍，轻击就打断 ----------
	"c016": {
		"label": "刀客",
		"data": "res://art/characters/enemies/c016/c016_data.tres",
		"scale": 0.32, # 骨架 348px -> 约 111px
		"elite": false,
		"anim": {"idle": "stand", "patrol": "run", "chase": "speed_run", "hurt": "atked", "dead": "dead"},
		"attacks": ["skill01", "skill02", "skill03", "skill04", "skill05"],
		# 出手后多少秒判定命中，按动画里武器完全伸到最远端的时刻（range_probe 逐帧标定）
		"hit_at": {"skill01": 1.33, "skill02": 1.01, "skill03": 0.87, "skill04": 0.84, "skill05": 1.46},
		# 判定范围 = 动画里武器伸到的真实像素（×世界缩放）：钩子甩满 400px，砍刀 144px……
		"ranges": {"skill01": 144.0, "skill02": 400.0, "skill03": 109.0, "skill04": 164.0, "skill05": 155.0},
		"hp": 3,
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
		"bones": 1,
		"dead_min": 1.2, # 尸体至少停留多久再淡出
		"bar_w": 44.0,
		"bar_y": -120.0,
		"number_y": -105.0,
	},
	# ---------- 精英 · 游魂弓手：C023 模型，弓箭 + 3 段远程斩/射 ----------
	"c023": {
		"label": "游魂弓手",
		"data": "res://art/characters/enemies/c023/c023_data.tres",
		"scale": 0.55, # 骨架 270px -> 约 148px，比玩家略高，一眼是精英
		"elite": true,
		"anim": {"idle": "stand", "patrol": "run", "chase": "speed_run", "hurt": "atked_heavy", "dead": "atked_fall_end"},
		"attacks": ["2", "skill01", "skill02"],
		# range_probe 实测（骨架像素 @scale1 -> ×0.55）："2" 194@0.55s，skill01 790@0.71s，skill02 1054@3.54s
		"hit_at": {"2": 0.55, "skill01": 0.71, "skill02": 3.54},
		"ranges": {"2": 107.0, "skill01": 435.0, "skill02": 580.0},
		"hp": 10,
		"patrol_speed": 45.0,
		"chase_speed": 105.0,
		"patrol_range": 160.0,
		"idle_time": 1.4,
		"detect_range": 560.0, # 远距离斩击：看见 560 内就锁定
		"lose_range": 760.0, # 脱战要比攻击距离更远，否则 435/580 的长斩永远用不出来
		"attack_range": 560.0,
		"keep_dist": 150.0,
		"attack_cooldown": 2.6,
		"attack_lunge": 180.0,
		"hit_height": 110.0,
		"hurt_time": 0.35,
		"armor": 2, # 轻击（damage<2）不打断，重击才硬直
		"telegraph": true,
		"pick": "nearest",
		"bones": 3,
		"dead_min": 0.8, # dead 动画只有 0.083s，必须靠这个兜底才看得见尸体
		"bar_w": 64.0,
		"bar_y": -170.0,
		"number_y": -180.0,
	},
	# ---------- 黑袍剑客：Z002，招式最全的普通怪，三段快剑 ----------
	"z002": {
		"label": "黑袍剑客",
		"data": "res://art/characters/enemies/z002/z002_data.tres",
		"scale": 0.36, # 骨架 308.6px -> 约 111px
		"elite": false,
		"anim": {"idle": "stand", "patrol": "run", "chase": "speed_run", "hurt": "atked", "dead": "atked_fall_end"},
		"attacks": ["atk01", "atk02", "atk03"],
		# 探针实测（scale=1 峰值 -> ×0.36）：atk01 后侧 200@0.24、atk02 后侧 217@0.23、atk03 后侧 183@0.24
		# 黑袍剑客的剑从头到尾收在身侧/背后，剑锋扫向原点左侧，所以三招都判 both
		"hit_at": {"atk01": 0.24, "atk02": 0.23, "atk03": 0.24},
		"ranges": {"atk01": 72.0, "atk02": 78.0, "atk03": 57.0},
		"both": {"atk01": true, "atk02": true, "atk03": true},
		"hp": 3,
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
		"bones": 1,
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
		"elite": false,
		"anim": {"idle": "stand", "patrol": "walk2", "chase": "run", "hurt": "def_break", "dead": "atked_fall_end"},
		"attacks": ["skill01", "skill03_1", "skill03_2"],
		# 探针实测：skill01 后侧 509@0.52、skill03_1 后侧 586@0.62、skill03_2 前侧 649@0.38
		"hit_at": {"skill01": 0.52, "skill03_1": 0.62, "skill03_2": 0.38},
		"ranges": {"skill01": 112.0, "skill03_1": 116.0, "skill03_2": 143.0},
		# 巨斧横扫有半圈在身后，判 both
		"both": {"skill01": true, "skill03_1": true},
		"hp": 4,
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
		"bones": 1,
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
		"elite": false,
		"anim": {"idle": "stand", "patrol": "run", "chase": "speed_run", "hurt": "atked", "dead": "atked_fall_end"},
		"attacks": ["skill01", "skill02"],
		# 探针实测：skill01 前侧 280@0.94、skill02 前侧 306@1.38
		"hit_at": {"skill01": 0.94, "skill02": 1.38},
		"ranges": {"skill01": 118.0, "skill02": 129.0},
		"hp": 2,
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
		"bones": 1,
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
		"elite": true,
		"anim": {"idle": "stand", "patrol": "run", "chase": "speed_run", "hurt": "atked_heavy", "dead": "atked_fall_end"},
		"attacks": ["skill01", "skill03", "skill05", "skill06"],
		# 探针实测（×0.405）：skill01 后侧 406@1.17、skill03 后侧 414@1.01、skill05 前侧 434@1.88、skill06 前侧 391@0.69
		"hit_at": {"skill01": 1.17, "skill03": 1.01, "skill05": 1.88, "skill06": 0.69},
		"ranges": {"skill01": 164.0, "skill03": 168.0, "skill05": 176.0, "skill06": 159.0},
		# 大剑横抡带大片身后弧线，判 both
		"both": {"skill01": true, "skill03": true},
		"hp": 12,
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
		"bones": 3,
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
		"elite": true,
		"anim": {"idle": "stand", "patrol": "run", "chase": "run", "hurt": "atked_heavy", "dead": "atked_fall_end"},
		"attacks": ["skill01", "skill02", "skill03"],
		# 探针实测：skill01 后侧 363@0.60、skill02 后侧 363@0.73、skill03 后侧 380@0.83
		"hit_at": {"skill01": 0.60, "skill02": 0.73, "skill03": 0.83},
		"ranges": {"skill01": 209.0, "skill02": 154.0, "skill03": 218.0},
		# 双持镰刀左右开弓，前后都扫得到，判 both
		"both": {"skill01": true, "skill02": true, "skill03": true},
		"hp": 9,
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
		"bones": 3,
		"dead_min": 0.8,
		"bar_w": 64.0,
		"bar_y": -175.0,
		"number_y": -185.0,
	},
}


static func get_type(id: String) -> Dictionary:
	var type: Dictionary = TYPES.get(id, TYPES[DEFAULT_ID])
	return type
