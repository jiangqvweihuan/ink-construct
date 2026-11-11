extends RefCounted

## Boss 形态表：与 enemy_types.gd 同构，但每个 Boss 额外带「阶段」与「冲锋技」配置。
## Boss 专属规则：体型远大于小怪、全程霸体不硬直、血量阈值切阶段（可播变身动画、
## 变身期间无敌）、死后尸体停留更久、头顶不挂小血条（HUD 大血条代之）。
## ranges / hit_at 均由 scenes/tests/range_probe.tscn 实测骨架像素 × 本形态 scale 得出。

const Skins := preload("res://scripts/systems/skins.gd")

const DEFAULT_ID := "_debug"

## 一局随机登场哪一个 Boss（_debug 仅供 boss_test 冒烟，不进随机池）
const ROSTER := ["c009", "c015a1", "c001", "c008", "c032"]
## 图鉴额外收录：不属于五首领随机轮换的独立挑战首领。
## 只影响图鉴卡片，不参与 ROSTER 抽选、正史五首领统计与无尽跨层。
const CODEX_EXTRA := ["c019"]

static func codex_order() -> Array:
	var out: Array = ROSTER.duplicate()
	for id in CODEX_EXTRA:
		if not out.has(id):
			out.append(id)
	return out

static func is_codex_boss(id: String) -> bool:
	return codex_order().has(id)

## 正式房与试炼场共用同一场景 / 专属脚本来源，禁止两边各维护一份映射。
const DEFAULT_SCENE := "res://scenes/enemies/bosses/boss.tscn"
const SCENES := {
	"c009": "res://scenes/enemies/bosses/mo_ting.tscn",
	"c015a1": "res://scenes/enemies/bosses/fen_ding.tscn",
	"c001": "res://scenes/enemies/bosses/wu_che.tscn",
}
const SCRIPT_OVERRIDES := {
	"c008": "res://scripts/enemies/sui_yue.gd",
	"c032": "res://scripts/enemies/ming_zhong.gd",
	"c019": "res://scripts/enemies/c019.gd",
}

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
		"portrait": "res://art/characters/portraits/c009.png",
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
		# 焚鼎甩臂（skill02）落点在原点左侧：探针峰值 L≈334~354 与 340 吻合，判 both。
		"both": {"skill02": true},
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
		"intro": {"anim": "stand", "loop": true},
		"fx": {"hit": {"name": "ink_claw", "scale": 0.5},
			"enter": {"name": "speedline", "scale": 1.6, "off_y": -170.0},
			"charge_wall": {"name": "crack", "scale": 0.8}},
	},
	# ---------- 碎岳 · 邪佛（C008）：独立四招、佛曰金钟与佛眼夺被动 ----------
	"c008": {
		"label": "碎岳",
		"data": "res://art/characters/enemies/bosses/c008/c008_data.tres",
		"portrait": "res://art/characters/portraits/c008.png",
		"scale": 0.55,
		"body_radius": 95.0,
		# 保留原有受击、移动与倒地动画。
		"anim": {"idle": "stand", "patrol": "run", "chase": "run", "hurt": "def_break", "dead": "atked_fall_end"},
		"hp": 64,
		"patrol_speed": 0.0,
		"chase_speed": 95.0,
		"patrol_range": 0.0,
		"idle_time": 0.0,
		"detect_range": 9999.0,
		"lose_range": 9999.0,
		"attack_range": 536.0,
		"keep_dist": 0.0,
		"attack_cooldown": 0.24,
		"attack_lunge": 0.0,
		"hit_height": 190.0,
		"hurt_time": 0.35,
		"armor": 99,
		"telegraph": true,
		"pick": "nearest",
		"dead_min": 2.4,
		"number_y": -390.0,
		"stage_at": [],
		"stages": [{"attacks": ["skill04", "skill03", "skill02", "skill01"], "attack_cooldown": 0.24, "chase_speed": 95.0}],
		"intro": {"anim": "stand", "loop": true},
		# 用户动画编号：9=skill04 双臂，7=skill03 踢落，6=skill02 万佛手，5=skill01 佛眼。
		"ranges": {"skill04": 536.0, "skill03": 300.0, "skill02": 260.0, "skill01": 225.0},
		"hit_at": {"skill04": 0.92, "skill03": [0.71, 1.35], "skill02": [2.16, 2.61, 3.06, 3.51, 3.96], "skill01": 1.19},
		"damage": {"skill04": 3, "skill03": [2, 3], "skill02": [1, 1, 1, 1, 1], "skill01": 0},
		"attack_rules": {
			"skill04": {"cooldown": 0.0, "max": 560.0},
			"skill03": {"cooldown": 24.0, "max": 330.0},
			"skill02": {"cooldown": 30.0, "max": 290.0},
			"skill01": {"cooldown": 50.0, "max": 260.0},
		},
		"fx": {"hit": {"name": "ink_claw", "scale": 0.5}, "enter": {"name": "crack", "scale": 0.9}},
	},
	# ---------- 鸣钟 · 神骸女武神（C032）：根骨位移四招 + 英勇/格挡/圣光 ----------
	"c032": {
		"label": "鸣钟",
		"data": "res://art/characters/enemies/bosses/c032/c032_data.tres",
		"scale": 0.48, # 实战比标准玩家明显高一圈，但仍保持人形 Boss 体型
		"codex_scale": 0.62, # 独立图鉴倍率：不沿用巨型 Boss 的减半预览
		"body_radius": 30.0,
		"anim": {"idle": "stand", "patrol": "run", "chase": "speed_run", "hurt": "atked_heavy", "dead": "atked_fall_end"},
		"hp": 68,
		"patrol_speed": 50.0,
		"chase_speed": 150.0,
		"patrol_range": 160.0,
		"idle_time": 1.0,
		"detect_range": 9999.0,
		"lose_range": 9999.0,
		"attack_range": 270.0,
		"keep_dist": 270.0,
		"attack_cooldown": 3.2,
		"attack_lunge": 0.0,
		"hit_height": 140.0,
		"hurt_time": 0.5,
		"armor": 99,
		"telegraph": true,
		"pick": "nearest",
		"dead_min": 2.4,
		"number_y": -180.0,
		"stage_at": [],
		"stages": [{"attacks": ["skill05-cankao", "skill01-cankao", "skill03-cankao", "transform1"], "attack_cooldown": 3.2, "chase_speed": 150.0}],
		"intro": {"anim": "skill02", "loop": false},
		"ranges": {"skill05-cankao": 260.0, "skill01-cankao": 255.0, "skill03-cankao": 285.0, "skill04-cankao": 285.0, "transform1": 9999.0},
		"hit_at": {"skill05-cankao": 0.64, "skill01-cankao": [0.82, 1.58, 2.24, 2.94], "skill03-cankao": [0.52, 1.65, 2.95], "skill04-cankao": [0.52, 1.65, 2.95], "transform1": 4.32},
		"damage": {"skill05-cankao": 2, "skill01-cankao": [1, 1, 2, 2], "skill03-cankao": [1, 2, 3], "skill04-cankao": [1, 2, 3], "transform1": 4},
		"attack_rules": {
			"skill05-cankao": {"cooldown": 0.0, "max": 270.0},
			"skill01-cankao": {"cooldown": 24.0, "max": 250.0},
			"skill03-cankao": {"cooldown": 36.0, "max": 650.0},
			"skill04-cankao": {"cooldown": 36.0, "max": 650.0},
			"transform1": {"cooldown": 40.0, "max": 9999.0},
		},
		"move_pool": {"skill03-cankao": ["skill03-cankao", "skill04-cankao"]},
		"fx": {"hit": {"name": "ink_claw", "scale": 0.4}, "enter": {"name": "pillar", "scale": 0.65}},
	},
	# ---------- 剑冢 · 一阶段：守冢剑主，浮剑成阵，远距离压制 ----------
	"c019": {
		"label": "剑冢",
		"codex_sub": "首领 · 生命 32 → 36（双形态）",
		"codex_bonus": true, # 图鉴计数单列「番外首领」，不挤占正史 11 项
		"data": "res://art/characters/enemies/bosses/c019/c019_data.tres",
		"scale": 0.52, # 骨架 385.6px -> 约 200px
		"codex_scale": 0.62,
		"body_radius": 38.0,
		"anim": {"idle": "stand", "patrol": "run", "chase": "speed_run", "hurt": "atked_heavy", "dead": "atked_fall_end"},
		"hp": 32,
		"patrol_speed": 60.0,
		"chase_speed": 155.0,
		"patrol_range": 160.0,
		"idle_time": 0.8,
		"detect_range": 9999.0,
		"lose_range": 9999.0,
		"attack_range": 320.0,
		"keep_dist": 250.0,
		"attack_cooldown": 2.8,
		"attack_lunge": 0.0,
		"hit_height": 170.0,
		"hurt_time": 0.5,
		"armor": 99,
		"telegraph": true,
		"pick": "nearest",
		"dead_min": 2.4,
		"number_y": -230.0,
		"stage_at": [],
		"stages": [{"attacks": ["p1_thrust", "p1_rain", "p1_sweep", "p1_ring"], "attack_cooldown": 2.8, "chase_speed": 155.0}],
		# 图鉴：同一张「剑冢」卡片内合并展示二阶段四招，按钮切换对应骨架。
		"codex_forms": ["c019_sp"],
		# 剪影探针实测（0.52 缩放）：断岳 285；飞锋 282/303/336；剑幕 193/160；回锋阵 416/261/392。
		"ranges": {"p1_thrust": 285.0, "p1_rain": [280.0, 300.0, 335.0], "p1_sweep": [190.0, 160.0], "p1_ring": [410.0, 260.0, 390.0]},
		"hit_at": {"p1_thrust": 1.33, "p1_rain": [0.31, 0.92, 1.33], "p1_sweep": [0.41, 0.61], "p1_ring": [0.73, 0.94, 1.04]},
		"move_anims": {"p1_thrust": "skill06", "p1_rain": "skill01", "p1_sweep": "skill02", "p1_ring": "skill03"},
		"both": {"p1_sweep": true, "p1_ring": true},
		"damage": {"p1_thrust": 2, "p1_rain": [2, 2, 3], "p1_sweep": [2, 2], "p1_ring": [1, 1, 2]},
		"attack_rules": {
			"p1_thrust": {"cooldown": 0.0, "max": 300.0},
			"p1_rain": {"cooldown": 16.0, "max": 340.0},
			"p1_sweep": {"cooldown": 20.0, "max": 210.0},
			"p1_ring": {"cooldown": 28.0, "max": 420.0},
		},
		"fx": {"hit": {"name": "ink_claw", "scale": 0.32}, "enter": {"name": "pillar", "scale": 0.55}, "transform": {"name": "crack", "scale": 0.40}},
	},
	# ---------- 剑冢 · 二阶段：万刃归冢（同一 BOSS 的第二形态，不单独进随机池） ----------
	"c019_sp": {
		"label": "剑冢·万刃",
		"data": "res://art/characters/enemies/bosses/c019_sp/c019_sp_data.tres",
		"scale": 0.58, # 骨架包围盒 799px；站姿本体实测 426.7px -> 约 247px（一阶段约 202px）
		"codex_scale": 0.60,
		"body_radius": 60.0,
		"anim": {"idle": "stand", "patrol": "run", "chase": "speed_run", "hurt": "atked_heavy", "dead": "atked_fall_end"},
		"hp": 36,
		"patrol_speed": 60.0,
		"chase_speed": 170.0,
		"patrol_range": 160.0,
		"idle_time": 0.8,
		"detect_range": 9999.0,
		"lose_range": 9999.0,
		"attack_range": 220.0,
		"keep_dist": 140.0,
		"attack_cooldown": 2.1,
		"attack_lunge": 0.0,
		"hit_height": 230.0,
		"hurt_time": 0.5,
		"armor": 99,
		"telegraph": true,
		"pick": "nearest",
		"dead_min": 2.4,
		"number_y": -300.0,
		"stage_at": [],
		"stages": [{"attacks": ["p2_flash", "p2_rain", "p2_prison", "p2_combo"], "attack_cooldown": 2.1, "chase_speed": 170.0}],
		# 剪影探针实测（0.30 缩放）：焚锋 132；万刃 129；剑狱 206；百刃 84。
		# 实战放大到 0.58 后按 1.9333 倍等比换算，判定与刀光仍严格对齐。
		"ranges": {"p2_flash": 251.0, "p2_rain": 271.0, "p2_prison": 406.0, "p2_combo": [164.0, 164.0]},
		"hit_at": {"p2_flash": 0.32, "p2_rain": 2.25, "p2_prison": 2.48, "p2_combo": [1.05, 1.66]},
		"move_anims": {"p2_flash": "skill04_02", "p2_rain": "skill01", "p2_prison": "skill3", "p2_combo": "skill04_01"},
		"both": {"p2_prison": true},
		"damage": {"p2_flash": 2, "p2_rain": 4, "p2_prison": 3, "p2_combo": [1, 2]},
		"attack_rules": {
			# max 跟随实际刀光射程，避免近身招被 keep_dist(140) 卡成永不触发
			"p2_flash": {"cooldown": 0.0, "max": 260.0},
			"p2_rain": {"cooldown": 14.0, "max": 280.0},
			"p2_prison": {"cooldown": 24.0, "max": 416.0},
			"p2_combo": {"cooldown": 16.0, "max": 174.0},
		},
		"fx": {"hit": {"name": "ink_claw", "scale": 0.5}, "enter": {"name": "pillar", "scale": 0.5}, "transform": {"name": "crack", "scale": 0.40}},
	},
}


static func get_boss(id: String) -> Dictionary:
	var boss: Dictionary = BOSSES.get(id, BOSSES[DEFAULT_ID])
	return Skins.enemy_profile(id, boss)
