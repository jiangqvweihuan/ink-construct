extends RefCounted

## Boss 形态表：与 enemy_types.gd 同构，但每个 Boss 额外带「阶段」与「冲锋技」配置。
## Boss 专属规则：体型远大于小怪、全程霸体不硬直、血量阈值切阶段（可播变身动画、
## 变身期间无敌）、死后尸体停留更久、头顶不挂小血条（HUD 大血条代之）。
## ranges / hit_at 均由 scenes/tests/range_probe.tscn 实测骨架像素 × 本形态 scale 得出。

const DEFAULT_ID := "_debug"

## 一局随机登场哪一个 Boss（_debug 仅供 boss_test 冒烟，不进随机池）
const ROSTER := ["c009", "c015a1", "c001", "c008", "c032"]

const BOSSES := {
	# ---------- 调试占位：墨堂守将（c037 骨架放大版），验证阶段/变身/冲锋/结算全链路 ----------
	"_debug": {
		"label": "墨堂守将",
		"data": "res://art/characters/enemies/c037/c037_data.tres",
		"scale": 0.62, # 骨架 365.7px -> 约 227px，比精英大一半
		"body_radius": 55.0,
		"anim": {"idle": "stand", "patrol": "run", "chase": "speed_run", "hurt": "atked_heavy", "dead": "atked_fall_end"},
		"hp": 52,
		"patrol_speed": 50.0,
		"chase_speed": 110.0,
		"patrol_range": 160.0,
		"idle_time": 1.2,
		"detect_range": 9999.0, # Boss 全程锁定玩家，不脱战
		"lose_range": 9999.0,
		"attack_range": 270.0,
		"keep_dist": 140.0,
		"attack_cooldown": 2.4, # 阶段 1 的节奏（后续阶段由 stages 覆盖）
		"attack_lunge": 240.0,
		"hit_height": 150.0,
		"hurt_time": 0.3,
		"armor": 99, # 全程霸体：任何伤害都打不断（boss.gd 覆写 take_damage，不会进 HURT）
		"telegraph": true,
		"pick": "nearest",
		"dead_min": 2.0,
		"number_y": -230.0,
		# 阶段：血量比例跌破阈值就依次进下一段，招式池/节奏/速度整体换血
		"stage_at": [0.68, 0.38],
		"stages": [
			{"attacks": ["skill01", "skill03", "skill06"], "attack_cooldown": 2.4, "chase_speed": 110.0},
			{"attacks": ["skill01", "skill03", "skill06", "skill05"], "attack_cooldown": 1.8, "chase_speed": 130.0, "transform": "transform", "stagger": 0.6},
			{"attacks": ["skill03", "skill05", "skill06"], "attack_cooldown": 1.35, "chase_speed": 155.0, "transform": "transform", "stagger": 0.5},
		],
		# 判定范围 = 动画伸展像素 × 本形态 scale（c037 探针骨架像素 406/414/434/391 × 0.62）
		"ranges": {"skill01": 252.0, "skill03": 257.0, "skill05": 269.0, "skill06": 242.0},
		"hit_at": {"skill01": 1.17, "skill03": 1.01, "skill05": 1.88, "skill06": 0.69},
		# 大剑横抡的身后弧线也要能判定
		"both": {"skill01": true, "skill03": true},
		# 冲锋技：退远后横向撞穿全场，撞墙大硬直 = 玩家输出窗口（_debug 借 c037 的动画验证机制）
		"charge": {"anim_run": "speed_run", "anim_stop": "stand", "anim_stun": "stun",
			"speed": 640.0, "hit_w": 130.0, "hit_h": 150.0, "stun_time": 1.8,
			"cooldown": 7.0, "min_dist": 430.0, "damage": 2},
		# 特效配置：hit=受击 / enter=登场 / transform=变身 / charge_trail=冲锋拖尾 / charge_wall=撞墙
		"fx": {"hit": {"name": "ink_claw", "scale": 0.4},
			"charge_trail": {"name": "speedline", "scale": 1.0, "interval": 0.1, "off_y": 100.0},
			"charge_wall": {"name": "crack", "scale": 0.5}},
	},
	# ---------- 墨霆 · 机关巨兽与失心操控者（C009）：独立六招，无旧阶段池与通用冲锋 ----------
	"c009": {
		"label": "墨霆",
		"data": "res://art/characters/enemies/bosses/c009/c009_data.tres",
		"scale": 0.55,
		"body_radius": 100.0,
		# 动画 3/4：受击 def_break、追击 run；动画 5 skill01 只用于 Boss 房先导。
		"anim": {"idle": "stand", "patrol": "run", "chase": "run", "hurt": "def_break", "dead": "atked_fall_end"},
		"hp": 120,
		"patrol_speed": 0.0,
		"chase_speed": 155.0,
		"patrol_range": 0.0,
		"idle_time": 0.0,
		"detect_range": 9999.0,
		"lose_range": 9999.0,
		"attack_range": 427.0,
		"keep_dist": 0.0,
		"attack_cooldown": 0.24, # 只作收招间隔；奋挥本身无独立冷却。
		"attack_lunge": 0.0,
		"hit_height": 190.0,
		"hurt_time": 0.85,
		"armor": 99,
		"telegraph": true,
		"pick": "nearest",
		"dead_min": 2.2,
		"number_y": -365.0,
		"stage_at": [],
		"stages": [
			{"attacks": ["skill03", "skill04", "skill05", "skill06", "skill08", "skill02-01"], "attack_cooldown": 0.24, "chase_speed": 155.0},
		],
		"intro": {"anim": "skill01", "loop": false},
		"move_pool": {"skill08": ["skill08", "skill08-cankao"]},
		"ranges": {"skill03": 427.0, "skill04": 371.0, "skill05": 366.0,
			"skill06": 370.0, "skill08": 350.0, "skill08-cankao": 350.0, "skill02-01": 1920.0},
		"hit_at": {"skill03": [0.63, 1.53, 2.61], "skill04": [1.62, 2.48, 2.92, 3.36],
			"skill05": 1.62, "skill06": 1.48, "skill08": 1.28, "skill08-cankao": 1.28, "skill02-01": 0.85},
		"damage": {"skill03": [1, 1, 3], "skill04": 2, "skill05": 2, "skill06": 5,
			"skill08": 4, "skill08-cankao": 4, "skill02-01": 1},
		"attack_rules": {
			"skill03": {"cooldown": 0.0, "max": 427.0},
			"skill04": {"cooldown": 30.0, "random": false},
			"skill05": {"cooldown": 35.0, "trigger": "distance", "min": 430.0},
			"skill06": {"cooldown": 25.0, "max": 390.0},
			"skill08": {"cooldown": 40.0, "trigger": "distance", "min": 520.0},
			"skill02-01": {"cooldown": 16.0, "trigger": "distance", "min": 340.0},
		},
		"fx": {"hit": {"name": "ink_claw", "scale": 0.5}, "enter": {"name": "tiger", "scale": 1.1}},
	},
	# ---------- 焚鼎 · 紫焰锁链巨汉（C015_a1）：独立四招、炎骨觉醒与怒焰 ----------
	"c015a1": {
		"label": "焚鼎",
		"data": "res://art/characters/enemies/bosses/c015a1/c015a1_data.tres",
		"scale": 0.5,
		"body_radius": 90.0,
		"anim": {"idle": "stand", "patrol": "run", "chase": "run", "hurt": "def_break", "dead": "atked_fall_end"},
		"hp": 68,
		"patrol_speed": 0.0,
		"chase_speed": 95.0,
		"patrol_range": 0.0,
		"idle_time": 0.0,
		"detect_range": 9999.0,
		"lose_range": 9999.0,
		"attack_range": 466.0,
		"keep_dist": 0.0,
		"attack_cooldown": 0.24,
		"attack_lunge": 0.0,
		"hit_height": 190.0,
		"hurt_time": 0.35,
		"armor": 99,
		"telegraph": true,
		"pick": "nearest",
		"dead_min": 2.2,
		"number_y": -400.0,
		"stage_at": [],
		"stages": [
			{"attacks": ["skill01", "skill02", "skill3", "skill05"], "attack_cooldown": 0.24, "chase_speed": 95.0},
		],
		"intro": {"anim": "stand", "loop": true},
		"ranges": {"skill01": 300.0, "skill02": 340.0, "skill3": 466.0, "skill05": 110.0},
		"hit_at": {"skill01": 0.72, "skill02": [1.17, 1.89, 2.61], "skill3": 0.9, "skill05": 0.9},
		"damage": {"skill01": 2, "skill02": [1, 1, 2], "skill3": 3, "skill05": 3},
		"attack_rules": {
			"skill01": {"cooldown": 0.0, "max": 330.0},
			"skill02": {"cooldown": 20.0, "max": 370.0},
			"skill3": {"cooldown": 25.0, "max": 480.0},
			"skill05": {"cooldown": 30.0, "awakened": true},
		},
		"fx": {"hit": {"name": "ink_claw", "scale": 0.5},
			"enter": {"name": "fire_pillar", "scale": 0.7},
			"transform": {"name": "fire_pillar", "scale": 0.55}},
	},
	# ---------- 武车 · 双马战车（C001）：耐久波次型 Boss，只保留武撞与召唤 ----------
	"c001": {
		"label": "武车",
		"data": "res://art/characters/enemies/bosses/c001/c001_data.tres",
		"scale": 0.5,
		"body_radius": 300.0,
		"anim": {"idle": "stand", "patrol": "stand", "chase": "stand", "hurt": "atked_heavy", "dead": "atked_fall_end"},
		"hp": 5,
		"patrol_speed": 0.0,
		"chase_speed": 0.0,
		"patrol_range": 0.0,
		"idle_time": 0.2,
		"detect_range": 9999.0,
		"lose_range": 9999.0,
		"attack_range": 0.0,
		"keep_dist": 0.0,
		"attack_cooldown": 0.0,
		"attack_lunge": 0.0,
		"hit_height": 190.0,
		"hurt_time": 0.3,
		"armor": 99,
		"telegraph": true,
		"pick": "nearest",
		"dead_min": 2.4,
		"number_y": -390.0,
		"stage_at": [],
		"stages": [{"attacks": ["skill01"]}],
		"ranges": {"skill01": 0.0},
		"hit_at": {"skill01": 0.0},
		"charge": {"anim_run": "speed_run", "anim_stop": "stop"},
		"fx": {"hit": {"name": "ink_claw", "scale": 0.5},
			"enter": {"name": "speedline", "scale": 1.6, "off_y": -170.0},
			"charge_wall": {"name": "crack", "scale": 0.8}},
	},
	# ---------- 碎岳 · 墨甲巨汉（C008）：重装压场型 Boss，探针身高 674.3px ----------
	"c008": {
		"label": "碎岳",
		"data": "res://art/characters/enemies/bosses/c008/c008_data.tres",
		"scale": 0.55, # 674.3px -> 约 371px，与墨霆同级的墨甲巨汉
		"body_radius": 95.0,
		# 骨架 dead/stun 为 0 帧空动画：倒地借 atked_fall_end，受击/变身借 def_break
		"anim": {"idle": "stand", "patrol": "run", "chase": "run", "hurt": "def_break", "dead": "atked_fall_end"},
		"hp": 64,
		"patrol_speed": 45.0,
		"chase_speed": 85.0,
		"patrol_range": 150.0,
		"idle_time": 1.3,
		"detect_range": 9999.0,
		"lose_range": 9999.0,
		"attack_range": 300.0,
		"keep_dist": 160.0,
		"attack_cooldown": 2.5,
		"attack_lunge": 220.0,
		"hit_height": 150.0,
		"hurt_time": 0.35,
		"armor": 99,
		"telegraph": true,
		"pick": "nearest",
		"dead_min": 2.4,
		"number_y": -390.0,
		"stage_at": [0.65, 0.35],
		"stages": [
			{"attacks": ["skill01", "skill03"], "attack_cooldown": 2.5, "chase_speed": 85.0},
			{"attacks": ["skill01", "skill03", "skill3"], "attack_cooldown": 1.9, "chase_speed": 105.0, "transform": "def_break", "stagger": 0.6},
			# 三阶段觉醒：巨突刺（974px 全屏级突进）入池，节奏全面提速
			{"attacks": ["skill04", "skill3", "skill01"], "attack_cooldown": 1.5, "chase_speed": 125.0, "transform": "def_break", "stagger": 0.5},
		],
		# 探针实测 @scale1：skill01 409@1.19（重劈）、skill03/skill3 494@0.71（双侧旋转扫）、
		# skill04 974@0.92（巨突刺）；skill02 峰值在 0 帧（贴身砸地无前伸），不进招式池（×0.55）
		"ranges": {"skill01": 225.0, "skill03": 272.0, "skill3": 272.0, "skill04": 536.0},
		"hit_at": {"skill01": 1.19, "skill03": 0.71, "skill3": 0.71, "skill04": 0.92},
		# 旋转扫击前后都够得到
		"both": {"skill03": true, "skill3": true},
		# 冲锋：run 奔冲 + def_break 急停/撞墙（骨架 stun 为空帧）
		"charge": {"anim_run": "run", "anim_stop": "def_break", "anim_stun": "def_break",
			"speed": 620.0, "hit_w": 150.0, "hit_h": 160.0, "stun_time": 1.8,
			"cooldown": 6.5, "min_dist": 430.0, "damage": 2},
		# 特效：登场/变身脚下地裂，冲锋拖速度线，撞墙地裂爆炸
		"fx": {"hit": {"name": "ink_claw", "scale": 0.5},
			"enter": {"name": "crack", "scale": 0.9},
			"transform": {"name": "crack", "scale": 0.7},
			"charge_trail": {"name": "speedline", "scale": 1.2, "interval": 0.1, "off_y": 165.0},
			"charge_wall": {"name": "crack", "scale": 0.7}},
	},
	# ---------- 鸣钟 · 墨甲钟馗（C032）：三段变身型 Boss，探针身高 388.6px ----------
	"c032": {
		"label": "鸣钟",
		"data": "res://art/characters/enemies/bosses/c032/c032_data.tres",
		"scale": 1.15, # 388.6px（含枪尖）-> 约 447px，身形比碎岳瘦但落差不再弱一档
		"body_radius": 75.0, # 瘦高个，半径别给过头
		# 骨架 dead/stun 为空动画（0.083 / 0 帧）：倒地借 atked_fall_end，受击借 atked_heavy
		"anim": {"idle": "stand", "patrol": "run", "chase": "run", "hurt": "atked_heavy", "dead": "atked_fall_end"},
		"hp": 68,
		"patrol_speed": 50.0,
		"chase_speed": 100.0,
		"patrol_range": 160.0,
		"idle_time": 1.2,
		"detect_range": 9999.0,
		"lose_range": 9999.0,
		"attack_range": 320.0,
		"keep_dist": 170.0,
		"attack_cooldown": 2.4,
		"attack_lunge": 220.0,
		"hit_height": 150.0,
		"hurt_time": 0.3,
		"armor": 99,
		"telegraph": true,
		"pick": "nearest",
		"dead_min": 2.4,
		"number_y": -390.0,
		"stage_at": [0.65, 0.35],
		# 本骨架自带 transform / transform1 / transform2 三套变身，P2 用 transform、P3 用 transform1
		"stages": [
			{"attacks": ["skill05", "skill02"], "attack_cooldown": 2.4, "chase_speed": 100.0},
			{"attacks": ["skill01", "skill05", "skill02"], "attack_cooldown": 1.9, "chase_speed": 120.0, "transform": "transform", "stagger": 0.6},
			{"attacks": ["skill03", "skill04", "skill01"], "attack_cooldown": 1.5, "chase_speed": 140.0, "transform": "transform1", "stagger": 0.5},
		],
		# 探针实测 @scale1：skill01 357@2.00、skill02 263@0.72、skill03 477@2.47（长扫）、
		# skill04 323@2.16、skill05 349@0.64（快招）；剪影峰值全在原点右侧，无需 both（×1.15）
		"ranges": {"skill01": 411.0, "skill02": 302.0, "skill03": 549.0, "skill04": 371.0, "skill05": 401.0},
		"hit_at": {"skill01": 2.00, "skill02": 0.72, "skill03": 2.47, "skill04": 2.16, "skill05": 0.64},
		# 冲锋：speed_run 高速奔跑 + stand 急停蓄力，撞墙借倒地姿势（骨架 stun 为空帧）
		"charge": {"anim_run": "speed_run", "anim_stop": "stand", "anim_stun": "atked_fall_end",
			"speed": 640.0, "hit_w": 140.0, "hit_h": 150.0, "stun_time": 1.8,
			"cooldown": 6.5, "min_dist": 430.0, "damage": 2},
		# 特效：变身动画自带大范围聚气演出，外部特效只作点缀
		"fx": {"hit": {"name": "ink_claw", "scale": 0.45},
			"enter": {"name": "pillar", "scale": 1.1},
			"transform": {"name": "pillar", "scale": 1.0},
			"charge_trail": {"name": "speedline", "scale": 1.2, "interval": 0.1, "off_y": 175.0},
			"charge_wall": {"name": "crack", "scale": 0.65}},
	},
}


static func get_boss(id: String) -> Dictionary:
	var boss: Dictionary = BOSSES.get(id, BOSSES[DEFAULT_ID])
	return boss
