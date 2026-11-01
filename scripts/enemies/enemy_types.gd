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
		"hit_effects": {"skill03": {"launch_velocity_y": -420.0}}, # 实伤后短击飞：约 0.42 秒、最高 44px
		# 升龙刀：追击中 100~260px 可直接起手，先瞬到身前 72px，保留 0.87s 飞行前摇供闪避。
		"blink_strike": {"anim": "skill03", "min": 100.0, "max": 260.0, "offset": 72.0},
		# 首招是唯一普攻；特殊招有独立冷却与触发窗口，近身合规技能就绪优先。
		"attack_rules": {
			"skill01": {"weight": 6.0},
			"skill02": {"trigger": "distance", "min": 180.0, "max": 400.0, "cooldown": 9.6, "random": false},
			"skill03": {"cooldown": 14.4, "random": false},
			"skill04": {"weight": 1.0, "max": 164.0, "cooldown": 7.2},
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
		"attack_rules": {"atk02": {"cooldown": 7.2}, "atk03": {"cooldown": 9.6}},
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
	# ---------- 蛮兵：C017，慢行霸体重斧；三招以开天为主，追击三斧后力竭 ----------
	"c017": {
		"label": "蛮兵",
		"data": "res://art/characters/enemies/c017/c017_data.tres",
		"scale": 0.258, # 骨架 502.9px -> 约 130px：最大杂兵，仍低于精英约 148px
		"body_radius": 42.0, # 体型与受击宽度同步放大
		"elite": false,
		"anim": {"idle": "stand", "patrol": "walk2", "chase": "walk2", "hurt": "def_break", "dead": "atked_fall_end"},
		"chase_anim_speed": 1.2,
		"attacks": ["skill01", "skill02", "skill03_2", "skill03_3"],
		# 逐帧复核：开天斧刃 0.64s 扫入身前（前侧 314），旧 1.20s 是后段举斧；其余按新体型换算。
		"hit_at": {"skill01": 0.64, "skill02": 1.58, "skill03_2": [0.36, 0.80], "skill03_3": 0.20},
		"ranges": {"skill01": 81.0, "skill02": 152.0, "skill03_2": [167.0, 161.0], "skill03_3": 150.0},
		"damage": {"skill01": 2, "skill02": 2, "skill03_2": 1, "skill03_3": 2},
		"hit_effects": {"skill02": {"jump_seal": 8.0}},
		"hit_knockback": Vector2(140.0, 0.0), # 蛮力：每段实伤都短击退，不附加浮空
		"super_armor": true, # 普通控制免疫；ignore_armor 与时停仍可穿透
		"attack_chain": {"skill03_2": {"anim": "skill03_3", "recovery": 3.0}},
		"advance": {"skill03_2": 85.0}, # 前两劈边慢步推进边落斧，收尾大劈原地完成
		"blink_strike": {"anim": "skill03_2", "min": 120.0, "max": 260.0, "offset": 0.0},
		"attack_rules": {
			"skill01": {"weight": 7.0},
			"skill02": {"weight": 1.0, "max": 164.0, "cooldown": 10.8},
			"skill03_2": {"cooldown": 19.2, "random": false},
			"skill03_3": {"random": false},
		},
		"hp": 8,
		"patrol_speed": 40.0,
		"chase_speed": 52.0,
		"patrol_range": 90.0,
		"idle_time": 1.2,
		"detect_range": 230.0,
		"lose_range": 330.0,
		"attack_range": 164.0,
		"keep_dist": 94.0,
		"attack_cooldown": 2.6,
		"attack_lunge": 0.0,
		"hit_height": 111.0,
		"hurt_time": 0.4,
		"armor": 0,
		"telegraph": false,
		"pick": "random",
		"dead_min": 0.8,
		"bar_w": 54.0,
		"bar_y": -140.0,
		"number_y": -123.0,
	},
	# ---------- 刺客：C035，镖去叠割伤，偷袭绕背，阴影放大身后直伤 ----------
	"c035": {
		"label": "刺客",
		"data": "res://art/characters/enemies/c035/c035_data.tres",
		"scale": 0.422, # 骨架 262.9px -> 约 111px
		"body_radius": 28.0, # 刺客精瘦，挨打面窄一档
		"elite": false,
		"anim": {"idle": "stand", "patrol": "run", "chase": "speed_run", "hurt": "atked", "dead": "atked_fall_end"},
		"attacks": ["dart", "sneak"],
		"move_anims": {"dart": "skill02", "sneak": "skill01"}, # 镖去用 12 号，偷袭用 11 号，逻辑判定完全独立
		# 定格复核：镖去 skill02 取 0.50/1.36s（254/306px），偷袭 skill01 取 0.94s（280px）；×0.422 = 107/129/118。
		"hit_at": {"dart": [0.50, 1.36], "sneak": 0.94},
		"ranges": {"dart": [107.0, 129.0], "sneak": 118.0},
		"damage": {"dart": 1, "sneak": 2},
		# 同一次镖去的第二段只穿过第一段造成的受击无敌；整招实伤后只挂一组 3/6 秒割伤。
		"hit_effects": {"dart": {"cut": true, "pierce_hurt_invincible": true}},
		"blink_strike": {"anim": "sneak", "min": 100.0, "max": 260.0, "offset": 72.0, "behind": true},
		"lunge_mul": {"sneak": 0.0}, # 绕背后原地演出，避免前冲穿过目标导致背刺方向翻转
		"backstab": true,
		"attack_rules": {
			"dart": {"weight": 1.0},
			"sneak": {"cooldown": 14.4, "random": false},
		},
		"knock_at": 2,
		"knock_chain": ["atked", "atked_air", "atked_fall_end", "getup"],
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
	# ---------- 精英 · 青魇剑主：C037，亭台礼剑与魔剑反噬并存 ----------
	"c037": {
		"label": "青魇剑主",
		"data": "res://art/characters/enemies/c037/c037_data.tres",
		"scale": 0.405, # 骨架 365.7px -> 约 148px
		"body_radius": 40.0,
		"elite": true,
		"anim": {"idle": "stand", "patrol": "run", "chase": "speed_run", "hurt": "atked_heavy", "dead": "atked_fall_end"},
		"attacks": ["skill01", "skill03", "cangjian"],
		"move_pool": {"cangjian": ["skill05", "skill06", "skill01-cankao"]},
		# 亭台剑逐帧三段：0.49/1.18/1.49；首段前半秒半速演出，真实首击约 0.98 秒。
		"hit_at": {
			"skill01": [0.49, 1.18, 1.49], "skill03": 1.01,
			"skill05": [0.40, 1.20, 1.88], "skill06": [0.28, 0.69, 1.62],
			"skill01-cankao": [0.47, 1.18, 1.47], "jijian": [],
		},
		"ranges": {
			"skill01": [130.0, 164.0, 164.0], "skill03": 168.0,
			"skill05": [128.0, 96.0, 176.0], "skill06": [131.0, 162.0, 164.0],
			"skill01-cankao": [130.0, 164.0, 161.0], "jijian": 0.0,
		},
		"both": {"skill01": true, "skill03": true},
		"damage": {"skill01": [1, 1, 2], "skill03": 2, "cangjian": [1, 2, 3], "jijian": 0},
		"hit_effects": {
			"skill01": {"pierce_hurt_invincible": true},
			"skill03": {"stacking_damage": true, "knockback": Vector2(420.0, -50.0)},
			"cangjian": {"pierce_hurt_invincible": true},
		},
		"segment_effects": {"cangjian": [{}, {}, {"cut": true}]},
		"opening_slow": {"skill01": {"until": 0.50, "scale": 0.50}},
		"limit": {"move": "jijian", "pool": ["skill04", "skill04-cankao"], "below": 0.5},
		"death_burst": {"getup": "getup", "anim": "transform", "damage": 3, "range": 480.0, "height": 240.0, "lunge": 96.0},
		"attack_rules": {"skill01": {"weight": 5.0}, "skill03": {"weight": 1.0, "cooldown": 7.2}, "cangjian": {"weight": 2.0, "cooldown": 9.6}},
		"knock_at": 5,
		"knock_strict": true,
		"knock_chain": ["atked_heavy", "atked_fall_end", "getup"],
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
		"armor": 2,
		"telegraph": true,
		"pick": "random",
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
		# 定格逐段标定：镰舞 0.30/0.60s 各展开一次；镰碎只在 0.73s 落镰侧结算；绽花取 0.83s 上挑。
		"hit_at": {"skill01": [0.30, 0.60], "skill02": 0.73, "skill03": 0.83},
		"ranges": {"skill01": [107.0, 156.0], "skill02": 146.0, "skill03": 112.0},
		"back_ranges": {"skill01": [174.0, 209.0], "skill03": 218.0},
		"both": {"skill01": true, "skill03": true},
		"damage": {"skill01": 2, "skill02": 5, "skill03": 0},
		"hit_effects": {
			"skill01": {"bleed": 1, "pierce_hurt_invincible": true},
			"skill02": {"lifesteal_from_damage": true},
			"skill03": {"effect_only": true, "bloom": true, "max_hp_loss": 2, "lift_height": 120.0},
		},
		"attack_rules": {
			"skill02": {"cooldown": 9.6},
			"skill03": {"cooldown": 14.4},
		},
		"bloodthirst": {
			"below": 0.30, "idle": "swim", "move": "walk",
			"patrol_speed": 30.0, "chase_speed": 52.0,
			"damage_delta": -1, "lifesteal": 1,
		},
		"knock_at": 5,
		"knock_strict": true, # 精英高伤倒地：严格大于 5，5 伤本身不触发
		"knock_chain": ["atked_heavy", "atked_fall_end", "getup"],
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
	# ---------- 精英 · 青笠剑客：C012，双剑斩养剑意，旋斩封闪，三层凝华同步分身 ----------
	"c012": {
		"label": "青笠剑客",
		"data": "res://art/characters/enemies/c012/c012_data.tres",
		"scale": 0.563, # 骨架 262.9px -> 约 148px（精英身高）
		"body_radius": 36.0,
		"elite": true,
		"anim": {"idle": "stand", "patrol": "run", "chase": "speed_run", "hurt": "atked", "dead": "atked_fall_end"},
		# 13 号双剑斩：0.80s 起剑前刺、1.21s 低位平刺；14 号旋斩：0.89s 腾空展开剑刃。
		"attacks": ["skill01", "skill02"],
		"hit_at": {"skill01": [0.80, 1.21], "skill02": 0.89},
		"ranges": {"skill01": [172.0, 138.0], "skill02": 163.0},
		"damage": {"skill01": [1, 2], "skill02": 2},
		# 首段先按旧剑意结算再叠层；第二段与旋斩都享受当前剑意，层数永不消耗。
		"segment_effects": {"skill01": [
			{"sword_intent": 1, "pierce_hurt_invincible": true},
			{"bleed": 1, "pierce_hurt_invincible": true},
		]},
		"hit_effects": {"skill02": {"sword_intent": 1, "dash_seal": 8.0, "pierce_hurt_invincible": true}},
		"attack_rules": {"skill02": {"cooldown": 12.0}},
		"poise_atk": {"skill02": true},
		"lunge_mul": {"skill02": 2.0},
		"hop": {"skill02": 260.0},
		"knock_at": 5,
		"knock_strict": true,
		"knock_chain": ["atked", "atked_fall_end", "getup"],
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
