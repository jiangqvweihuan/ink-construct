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
		"anim": {"idle": "stand", "patrol": "run", "chase": "speed_run", "hurt": "atked_heavy", "dead": "atked_fall_end"},
		"hp": 26,
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
		"bones": 10,
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
	# ---------- 墨霆 · 巨兽骑手（C009）：冲锋型 Boss，探针身高 628.6px ----------
	"c009": {
		"label": "墨霆",
		"data": "res://art/characters/enemies/bosses/c009/c009_data.tres",
		"scale": 0.55, # 628.6px -> 约 345px，近两倍玩家身高
		# 骨架无 hurt/dead 实动画（stun/dead 均为 0 帧）：倒地用 atked_fall_end，受击位借 def_break
		"anim": {"idle": "stand", "patrol": "run", "chase": "run", "hurt": "def_break", "dead": "atked_fall_end"},
		"hp": 30,
		"patrol_speed": 60.0,
		"chase_speed": 130.0,
		"patrol_range": 180.0,
		"idle_time": 1.0,
		"detect_range": 9999.0,
		"lose_range": 9999.0,
		"attack_range": 300.0,
		"keep_dist": 170.0,
		"attack_cooldown": 2.3,
		"attack_lunge": 260.0,
		"hit_height": 150.0,
		"hurt_time": 0.3,
		"armor": 99,
		"telegraph": true,
		"pick": "nearest",
		"bones": 10,
		"dead_min": 2.2,
		"number_y": -365.0,
		"stage_at": [0.65, 0.35],
		"stages": [
			{"attacks": ["skill01", "skill06", "skill07"], "attack_cooldown": 2.3, "chase_speed": 130.0},
			{"attacks": ["skill01", "skill03", "skill06", "skill08"], "attack_cooldown": 1.8, "chase_speed": 150.0, "transform": "def_break", "stagger": 0.6},
			# 三阶段觉醒：雷纹在胸口炸开（off_y 抬到躯干高度）
			{"attacks": ["skill03", "skill04", "skill05", "skill02"], "attack_cooldown": 1.4, "chase_speed": 175.0, "transform": "def_break", "stagger": 0.5,
				"fx": {"name": "thunder", "scale": 2.2, "off_y": -170.0}},
		],
		# 探针实测 @scale1：skill01 563@1.75、skill03 776@1.61、skill04 674@2.38、
		# skill05 665@3.12、skill06 554@1.61、skill07 486@0.13、skill08 554@0.15、skill02 537@0.68（×0.55）
		"ranges": {"skill01": 310.0, "skill03": 427.0, "skill04": 371.0, "skill05": 366.0,
			"skill06": 305.0, "skill07": 267.0, "skill08": 305.0, "skill02": 295.0},
		"hit_at": {"skill01": 1.75, "skill03": 1.61, "skill04": 2.38, "skill05": 3.12,
			"skill06": 1.61, "skill07": 0.6, "skill08": 0.7, "skill02": 0.68},
		# 冲锋：run 奔跑 + def_break 当急停/撞墙姿势（骨架 stun 为空帧，借格挡崩解的踉跄 pose）
		"charge": {"anim_run": "run", "anim_stop": "def_break", "anim_stun": "def_break",
			"speed": 640.0, "hit_w": 150.0, "hit_h": 160.0, "stun_time": 1.8,
			"cooldown": 6.5, "min_dist": 430.0, "damage": 2},
		# 特效：登场/变身虎首地裂，冲锋拖水墨速度线，撞墙地裂爆炸
		"fx": {"hit": {"name": "ink_claw", "scale": 0.5},
			"enter": {"name": "tiger", "scale": 1.1},
			"transform": {"name": "tiger", "scale": 0.9},
			"charge_trail": {"name": "speedline", "scale": 1.3, "interval": 0.1, "off_y": 155.0},
			"charge_wall": {"name": "crack", "scale": 0.65}},
	},
	# ---------- 焚鼎 · 紫焰锁链巨汉（C015_a1）：重装长臂型 Boss，探针身高 765.7px ----------
	"c015a1": {
		"label": "焚鼎",
		"data": "res://art/characters/enemies/bosses/c015a1/c015a1_data.tres",
		"scale": 0.5, # 765.7px -> 约 383px，三 Boss 里最高
		"anim": {"idle": "stand", "patrol": "run", "chase": "run", "hurt": "def_break", "dead": "atked_fall_end"},
		"hp": 34,
		"patrol_speed": 40.0,
		"chase_speed": 95.0,
		"patrol_range": 150.0,
		"idle_time": 1.3,
		"detect_range": 9999.0,
		"lose_range": 9999.0,
		"attack_range": 460.0, # 锁链臂极长，远程就开始起手
		"keep_dist": 200.0,
		"attack_cooldown": 2.6,
		"attack_lunge": 200.0,
		"hit_height": 150.0,
		"hurt_time": 0.35,
		"armor": 99,
		"telegraph": true,
		"pick": "nearest",
		"bones": 10,
		"dead_min": 2.2,
		"number_y": -400.0,
		"stage_at": [0.7, 0.4],
		"stages": [
			{"attacks": ["skill01", "skill3"], "attack_cooldown": 2.6, "chase_speed": 95.0},
			{"attacks": ["skill01", "skill3", "skill4", "skill02"], "attack_cooldown": 2.1, "chase_speed": 110.0, "transform": "def_break", "stagger": 0.6},
			# skill04（3.0s 紫焰升腾）当三阶段觉醒演出；觉醒后周期性封锁火区：聚气预警 -> 火柱喷发
			{"attacks": ["skill3", "skill02", "skill05", "skill03-01", "skill03-02"], "attack_cooldown": 1.6, "chase_speed": 130.0, "transform": "skill04", "stagger": 0.5,
				"fire_zones": {"count": 3, "radius": 110.0, "warn": 0.7, "interval": 4.5, "damage": 1}},
		],
		# 探针实测 @scale1：skill01 554@0.74、skill3/skill4 932@0.82（锁链横扫）、skill02 706@1.89（回身砸）、
		# skill05 568@0.66（回身）、skill03-01 469@1.26、skill03-02 434@0.74（×0.5）
		"ranges": {"skill01": 277.0, "skill3": 466.0, "skill4": 466.0, "skill02": 353.0,
			"skill05": 284.0, "skill03-01": 235.0, "skill03-02": 217.0},
		"hit_at": {"skill01": 0.74, "skill3": 0.82, "skill4": 0.82, "skill02": 1.89,
			"skill05": 0.66, "skill03-01": 1.26, "skill03-02": 0.74},
		# 锁链臂会抡到身后：skill02 / skill05 命中时武器在原点后方，前后都算命中
		"both": {"skill02": true, "skill05": true},
		# 特效：登场/变身紫焰火柱从脚下喷发（无冲锋，P3 封锁火区见 stages 配置）
		"fx": {"hit": {"name": "ink_claw", "scale": 0.5},
			"enter": {"name": "fire_pillar", "scale": 0.7},
			"transform": {"name": "fire_pillar", "scale": 0.55}},
	},
	# ---------- 武车 · 双马战车（C001）：冲撞节奏型 Boss，探针身高 742.9px、身宽 1423px ----------
	"c001": {
		"label": "武车",
		"data": "res://art/characters/enemies/bosses/c001/c001_data.tres",
		"scale": 0.5, # 742.9px -> 约 371px 高、711px 宽，小半个房间的钢铁巨物
		"anim": {"idle": "stand", "patrol": "run", "chase": "run", "hurt": "atked_heavy", "dead": "dead"},
		"hp": 32,
		"patrol_speed": 50.0,
		"chase_speed": 110.0,
		"patrol_range": 160.0,
		"idle_time": 1.2,
		"detect_range": 9999.0,
		"lose_range": 9999.0,
		"attack_range": 320.0, # 中距离由冲锋接管，近战只打贴身
		"keep_dist": 180.0,
		"attack_cooldown": 2.6,
		"attack_lunge": 200.0,
		"hit_height": 150.0,
		"hurt_time": 0.3,
		"armor": 99,
		"telegraph": true,
		"pick": "nearest",
		"bones": 10,
		"dead_min": 2.4,
		"number_y": -390.0,
		"stage_at": [0.6],
		"stages": [
			{"attacks": ["skill03", "skill01"], "attack_cooldown": 2.6, "chase_speed": 110.0},
			# zhuanshen（1.4s 双马转身）当二阶段演出：战车调头，节奏全面提速
			# transform_flip：演出是掉头，播完引擎朝向跟着翻转，否则 idle 会把车瞬间翻回去
			{"attacks": ["skill01", "skill01-", "skill03"], "attack_cooldown": 1.9, "chase_speed": 135.0, "transform": "zhuanshen", "transform_flip": true, "stagger": 0.5},
		],
		# 探针实测 @scale1：skill01/skill01- 1154@1.97（长枪横扫）、skill03 峰值在 0 帧（车体本身 817 宽），
		# 取挥击中段 1.0s 结算，range 按车体实测宽度 817 × 0.5 = 409
		"ranges": {"skill01": 577.0, "skill01-": 577.0, "skill03": 409.0},
		"hit_at": {"skill01": 1.97, "skill01-": 1.96, "skill03": 1.0},
		# 战车车体横跨原点两侧，扫到身后也要判定
		"both": {"skill03": true},
		# 战车灵魂技：speed_run 冲锋 / stop 急停蓄力 / stop 兼撞墙自晕（stun 为空帧）
		"charge": {"anim_run": "speed_run", "anim_stop": "stop", "anim_stun": "stop",
			"speed": 780.0, "hit_w": 170.0, "hit_h": 160.0, "stun_time": 2.4,
			"cooldown": 5.0, "min_dist": 400.0, "damage": 2},
		# 特效：入场/转身拉速度线，冲锋拖更密的速度线，撞墙地裂爆炸
		"fx": {"hit": {"name": "ink_claw", "scale": 0.5},
			"enter": {"name": "speedline", "scale": 1.6, "off_y": -170.0},
			"transform": {"name": "speedline", "scale": 1.2, "off_y": -170.0},
			"charge_trail": {"name": "speedline", "scale": 1.5, "interval": 0.08, "off_y": 160.0},
			"charge_wall": {"name": "crack", "scale": 0.8}},
	},
	# ---------- 碎岳 · 墨甲巨汉（C008）：重装压场型 Boss，探针身高 674.3px ----------
	"c008": {
		"label": "碎岳",
		"data": "res://art/characters/enemies/bosses/c008/c008_data.tres",
		"scale": 0.55, # 674.3px -> 约 371px，与墨霆同级的墨甲巨汉
		# 骨架 dead/stun 为 0 帧空动画：倒地借 atked_fall_end，受击/变身借 def_break
		"anim": {"idle": "stand", "patrol": "run", "chase": "run", "hurt": "def_break", "dead": "atked_fall_end"},
		"hp": 32,
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
		"bones": 10,
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
		# 骨架 dead/stun 为空动画（0.083 / 0 帧）：倒地借 atked_fall_end，受击借 atked_heavy
		"anim": {"idle": "stand", "patrol": "run", "chase": "run", "hurt": "atked_heavy", "dead": "atked_fall_end"},
		"hp": 34,
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
		"bones": 10,
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
