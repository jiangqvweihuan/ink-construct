extends RefCounted

## 换头形态表（Skul 核心机制）：每个形态自带骨架、缩放、动画名映射、普攻段、技能表、HUD 技能顺序。
## 新增形态 = 往 SKULLS 加一项，并把 spine 三件套丢进 art/characters/player/skulls/<id>/。
##
## scale 的算法：像素探针量出骨架在 scale=1 时的墨迹高度，scale = 128 / 原始高度，
## 让所有形态在游戏里视觉上一样高（128px），不然换头会突然变大变小。
##   c021 骨架 324.8px -> 0.394
##   c023 骨架 270px   -> 0.474

const DEFAULT_ID := "c021"

## 形态强度顺序（由弱到强）：选角界面 / 化身谱按此排列，解锁条件也按同一梯度递增
const ORDER := ["c021", "c013", "c023", "z000", "z003"]

const SKULLS := {
	"c021": {
		"label": "双刺", # 代称：红缨双匕 + 面纱长裙的女刺客造型
		"name": "冷红绫",
		"data": "res://art/characters/player/c021_data.tres",
		"scale": 0.394,
		"anim": {
			"idle": "stand",
			"run": "run",
			"dash": "dash_front", # 第 14 号：0.5s 闪避动画，整段都是完美闪避判定
			"air": "floated",
			"hurt": "atked", # 第 6 号：轻击受击
			"hurt_heavy": "atked_heavy", # 第 11 号：重击受击
			"fall": "atked_fall_end", # 第 10 号：倒地（伤害过阈值）
			"getup": "getup", # 第 17 号：倒地后起身
			"low_idle": "weak", # 第 32 号：残血待机（< 20% 生命）
			"dead": "dead",
		},
		"body_radius": 30.0,
		# 闪避：整段动画（dash_front 0.5s）都算完美闪避；速度压到 340 保持位移不过分夸张
		"dash_time": 0.5,
		"dash_speed": 340.0,
		# 受击分档：1 伤=轻（atked）、≥2 伤=重（atked_heavy）、≥3 伤=倒地（atked_fall_end → getup）
		"hurt_tiers": {"heavy": 2, "knockdown": 3},
		# 残血待机：血量比例 ≤ 20% 时待机切 weak（其他形态可照抄这一组字段）
		"low_hp_ratio": 0.2,
		# 每段普攻：lock=锁定总时长，hits=命中时刻（动画秒），range=正前方判定距离，lunge=前冲速度
		"attacks": [
			{"anim": "atk01", "lock": 0.55, "hits": [0.34], "damage": 1, "range": 100.0, "lunge": 110.0},
			{"anim": "atk02", "lock": 0.50, "hits": [0.14], "damage": 1, "range": 85.0, "lunge": 110.0},
			# atk03 是回身横扫：匕尖甩到原点左侧 92px，判 both（前后都算命中）
			{"anim": "atk03", "lock": 1.30, "hits": [0.26, 0.72], "damage": 1, "range": 95.0, "lunge": 120.0, "both": true},
		],
		"skills": {
			# K 穿影突刺（第 19 号 skill01，1.567s）：0.75~1.28s 隐身前冲穿过敌人，1.30s 现身一刀。
			# speed 1.4 提速去掉"顿感"，blink_speed 同步 ×1.4 保持原位移距离；invincible 整段无敌
			# （对齐银夜 O 的位移技规则）。时刻表仍按动画秒标定，提速后自动对齐。
			"skill01": {
				"action": "skill", "cooldown": 3.0, "speed": 1.4, "invincible": true,
				"hits": [{"at": 1.30, "range": 100.0, "height": 90.0, "damage": 2, "path": true, "sfx": "hit_heavy"}],
				"blink_from": 0.75, "blink_to": 1.28, "blink_speed": 730.0,
			},
			# L 罗刹旋舞（第 28 号 skill5-，2.583s）：原地无敌的高额多段斩，时长按动画走。
			# 四段命中时刻来自 range_probe 峰值（0.79/1.33/1.80/2.25s，属双向旋转斩，both）。
			# 特殊机制·裂帛：每次命中叠一层流血（每层每秒 1 伤，最多 5 层，持续 5 秒）——
			# 打肉山/Boss 时越砍越疼，符合"双匕割裂"的形象。
			"skill5-": {
				"action": "skill_sweep", "cooldown": 10.0, "invincible": true,
				"hits": [
					{"at": 0.79, "range": 125.0, "height": 110.0, "damage": 2, "both": true, "sfx": "skill_blade", "bleed": 1},
					{"at": 1.33, "range": 105.0, "height": 110.0, "damage": 2, "both": true, "sfx": "voice_fan_hit", "bleed": 1},
					{"at": 1.80, "range": 125.0, "height": 110.0, "damage": 2, "both": true, "sfx": "skill_fist", "bleed": 1},
					{"at": 2.25, "range": 90.0, "height": 110.0, "damage": 2, "both": true, "sfx": "hit_heavy", "bleed": 1},
				],
			},
			# U 掷匕·缚（第 25 号 skill02-cankao，2.05s）：远程投掷一把双刺（1.43s 出手），
			# 命中后定身 3 秒（期间敌人不能移动但可以出手），并从命中点分裂出第二把继续飞。
			# 无 blink / teleport：位移只靠动画本身的根骨后跃（root_motion），不会出现闪现或残影。
			"skill02-cankao": {
				"action": "skill_ult", "cooldown": 9.0,
				"root_motion": true, # 动画 1.2~1.42s 把根骨后挪约 430 骨架像素（≈170 世界像素）：节点跟着挪，收招后停在那里
				"hits": [{
					"at": 1.43, "damage": 2, "sfx": "skill_blade",
					"projectile": {"speed": 900.0, "range": 460.0, "root": 3.0, "split": 1, "style": "dagger"},
				}],
			},
		},
		"hud_skills": ["skill01", "skill5-", "skill02-cankao"],
	},
	"c023": {
		"label": "梅剑", # 代称：黑袍白发 + 梅花枝长剑
		"name": "白疏影",
		"data": "res://art/characters/player/skulls/c023/c023_data.tres",
		"scale": 0.474,
		"anim": {
			"idle": "stand",
			"run": "run",
			"dash": "speed_run", # 第 15 号：疾走当闪避（加速 1.6 倍压进 0.45s）
			"air": "floated",
			"hurt": "atked_air", # 第 4 号：1 点伤害的轻受击
			"hurt_heavy": "atked_air_heavy", # 第 5 号：2 点伤害的重受击
			"dead": "dead",
			"getup": "getup", # 第 11 号：起身
		},
		# 闪避：第 15 号 speed_run（0.717s）加速 1.6 倍压进 0.45s，整段都是完美闪避窗口。
		# 实测 380 速位移约 171px 太远（用户反馈），压到 270 速 → 约 120px，窗口不变、只收位移
		"dash_time": 0.45,
		"dash_speed": 270.0,
		"dash_anim_speed": 1.6,
		# 受击分档：1 伤=第 4 号；2 伤=第 5 号；≥3 伤走下面的倒地链
		"hurt_tiers": {"heavy": 2, "knockdown": 3},
		# 倒地链：5 重受击 → 7 倒地 → 11 起身（起身段整段无敌），段间按动画真实时长无缝接续
		"knock_chain": ["atked_air_heavy", "atked_fall_end", "getup"],
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
			# 3.6s 最后一记超远甩鞭 R1051 -> 500px，伤害 2→5。
			# 中毒挂"长鞭剑命中"而非只挂尾端：转鞭每一跳（tick）与尾端甩鞭都带 poison，
			# 全程任意一下打中都会让目标中毒（4 秒，每 0.5 秒扣 1 点；不叠层，重复命中只刷新时长）
			# ranged_guard：转鞭期间免疫敌方投射物并原路弹回（工程暂无敌方投射物，接口已预埋）
			"skill02": {
				"action": "skill", "cooldown": 9.0,
				"poise": true,
				"ranged_guard": true,
				"tick": {"from": 0.15, "to": 3.0, "interval": 0.5, "range": 130.0, "height": 140.0, "damage": 1, "both": true, "poison": 4.0},
				"hits": [{"at": 3.6, "range": 500.0, "height": 150.0, "damage": 5, "sfx": "skill_blade", "poison": 4.0}],
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
			"run": "speed_run", # 第 19 号：疾跑（替换原来的 run）
			"dash": "skill04", # 第 15 号：0.583s 闪避动画，整段都是完美闪避判定
			"air": "floated",
			"hurt": "atked", # 第 1 号：1 点伤害的轻受击
			"hurt_heavy": "atked_heavy", # 第 6 号：2 点伤害的重受击
			"getup": "getup", # 第 9 号：起身
			"dead": "dead",
		},
		# 闪避：动画 skill04 多长（0.583s），完美闪避窗口就多长；速度配合时长把距离压在 175px 左右
		"dash_time": 0.583,
		"dash_speed": 300.0,
		# 受击分档：1 伤=轻（第 1 号 atked）；2 伤=重（第 6 号 atked_heavy）；≥3 伤走下面的整条链
		"hurt_tiers": {"heavy": 2, "knockdown": 3},
		# 倒地链（力僧专用）：6 重受击 → 3 浮空重受击 → 5 倒地 → 9 起身，段与段按动画真实时长无缝接续，
		# 起身段整段无敌；播放期间全程 State.HURT，结束回 IDLE/FALL
		"knock_chain": ["atked_heavy", "atked_air_heavy", "atked_fall_end", "getup"],
		# 探针实测（已乘 0.487）：skill02_01 后侧 156@0.13，skill02_03 后侧 185@0.26
		# 狼牙棒挥砸的落点在原点后方，所以普攻/挥砸类判 both，动画扫到哪边都能命中
		# 两段普攻（第 16 号 + 第 18 号）：数值比原来 1/1/2 整体抬一档 -> 2 / 3
		"attacks": [
			{"anim": "skill02_01", "lock": 0.44, "hits": [0.13], "damage": 2, "range": 156.0, "lunge": 120.0, "both": true},
			{"anim": "skill02_03", "lock": 0.47, "hits": [0.26], "damage": 3, "range": 185.0, "lunge": 130.0, "both": true},
		],
		"skills": {
			# K 横扫（skill01 1.85s，动画不变）：两段挥棒
			# 0.60s 第一段：前后 198px 全扫，3 伤 + 击退 620（撞人 1 伤）+ 落点定身 2 秒
			# 1.66s 第二段：不打伤害，给自己挂金钟罩（免疫 1 次攻击，8 秒没挨打就自己散）
			"skill01": {
				"action": "skill", "cooldown": 3.5,
				"hits": [
					{"at": 0.60, "range": 198.0, "height": 110.0, "damage": 3, "sfx": "skill_fist", "both": true,
						"knockback": {"force": 620.0, "impact": 1}, "root": 2.0},
					{"at": 1.66, "self_shield": {"hits": 1, "time": 8.0}, "sfx": "skill_boom"},
				],
			},
			# L 横扫（skill03 1.5s，动画不变）：伤害 1→3；命中晕眩 2 秒（不能移动也不能出手，立即打断起手）
			"skill03": {
				"action": "skill_sweep", "cooldown": 5.0,
				"hits": [{"at": 0.87, "range": 191.0, "height": 110.0, "damage": 3, "sfx": "voice_fan_hit", "stun": 2.0}],
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
	# ---------- 剑仙：Z000，持剑的全能剑客（92 个动画），四段普攻 + 六技能（K/L/U/I/O/P） ----------
	"z000": {
		"label": "剑仙",
		"name": "洛惊鸿",
		"hero": true, # 英雄级主角：K/L/U 普通技 + I 觉醒 + O/P 觉醒技（规范见 PROGRESS.md）
		"data": "res://art/characters/player/skulls/z000/z000_data.tres",
		"scale": 0.448, # 骨架 285.7px -> 128px
		"body_radius": 30.0, # 标准体型
		"anim": {
			"idle": "stand",
			"run": "run",
			"dash": "dash_front", # 兜底（实际走下面的 dash_pool 双闪避）
			"air": "floated",
			"hurt": "atked", # 第 19 号：1 点伤害轻受击
			"hurt_heavy": "atked_heavy", # 第 24 号：2 点伤害重受击
			"fall": "2", # 第 2 号：倒地（1.85s，倒地+起身一体）
			"getup": "2", # 倒地链末段 = 第 2 号，整段无敌（防止无限倒地）
			"dead": "atked_fall_end", # dead 时长为 0，先用倒地动画再定格
			"dead_hold": "dead", # 第 dead 号是单帧定格，循环即躺尸姿势
			"jump_start": "jump_start", # 第 42 号：起跳一帧
			"jump_mid": "jump_mid", # 第 41 号：上升姿态（循环）
			"jump_down": "jump_down", # 第 39 号：下降姿态（循环）
			"jump_land": "jump_end", # 第 40 号：落地一帧
		},
		# 受击分档：1 伤=轻；2 伤=重；≥3 伤先重受击再整条倒地链（第 24 号 → 第 2 号），第 2 号整段无敌
		"hurt_tiers": {"heavy": 2, "knockdown": 3},
		"knock_chain": ["atked_heavy", "2"],
		# 双闪避：站定按闪避 = 第 88 号原地闪（零位移、整段完美闪避、冷却 1s）；
		# 移动中按闪避 = 第 25 / 35 号随机抽取（带约 120px 位移、冷却 0.45s）
		"dash_pool": {
			"still": {"anim": "speed_run_finish", "time": 0.717, "speed": 0.0, "cd": 1.0},
			"move": [
				{"anim": "autorush", "time": 0.167, "speed": 760.0},
				{"anim": "dash_front", "time": 0.483, "speed": 260.0},
			],
			"move_cd": 0.45,
		},
		# 四段普攻（探针 ×0.448 实测标定，全部近战、无剑气）：
		# 段1 第 4 号 1 伤；段2 第 5 号 1 伤；段3 第 62 号动画期间 4 次 1 伤且每次附眩晕；段4 第 67 号 2 伤 + 击飞
		"attacks": [
			{"anim": "atk01", "lock": 0.367, "hits": [{"at": 0.22, "damage": 1, "range": 180.0}], "lunge": 110.0},
			{"anim": "atk02", "lock": 0.433, "hits": [{"at": 0.28, "damage": 1, "range": 100.0, "both": true}], "lunge": 110.0},
			{"anim": "skill16", "lock": 1.300, "lunge": 90.0, "hits": [
				{"at": 0.25, "damage": 1, "range": 160.0, "both": true, "stun": 0.8},
				{"at": 0.56, "damage": 1, "range": 160.0, "both": true, "stun": 0.8},
				{"at": 0.74, "damage": 1, "range": 160.0, "both": true, "stun": 0.8},
				{"at": 0.93, "damage": 1, "range": 160.0, "both": true, "stun": 0.8}]},
			{"anim": "skill07_02", "lock": 1.433, "lunge": 130.0, "hits": [
				{"at": 1.20, "damage": 2, "range": 130.0, "both": true,
					"launch": {"vx": 150.0, "vy": 520.0}}]},
		],
		"skills": {
			# K 送出配件：第 7 / 18 号随机，身前高速旋转，快速 3 次伤害 + 流血
			"atk04": {"action": "skill", "cooldown": 6.0, "poise": true,
				"pool": ["atk04", "atk04_air"],
				"hits": [
					{"at": 0.16, "range": 170.0, "height": 120.0, "damage": 1, "bleed": 1, "both": true, "sfx": "skill_blade"},
					{"at": 0.34, "range": 170.0, "height": 120.0, "damage": 1, "bleed": 1, "both": true, "sfx": "skill_blade"},
					{"at": 0.50, "range": 170.0, "height": 120.0, "damage": 1, "bleed": 1, "both": true, "sfx": "skill_blade"}]},
			# L 月华斩：第 64 / 58 号随机，挥出巨大剑影（5 伤 / 700 速 / 900 射程 / 无限穿透 / 命中叠 1 层流血）
			"skill02-": {"action": "skill_sweep", "cooldown": 8.0, "poise": true,
				"pool": ["skill02-", "skill12"],
				"hit_at": {"skill02-": 1.20, "skill12": 0.62},
				"range": {"skill02-": 120.0, "skill12": 180.0},
				"height": 130.0, "damage": 5, "sfx": "skill_blade",
				"projectile": {"speed": 700.0, "range": 900.0, "pierce": true, "bleed": 1, "scale": 1.7}},
			# U 飞脚：第 50 号，超高击飞（无视霸体，连 Boss 也能挑起来）
			"skill04": {"action": "skill_ult", "cooldown": 10.0, "poise": true,
				"hits": [{"at": 0.48, "range": 110.0, "height": 120.0, "damage": 3, "sfx": "hit_heavy",
					"launch": {"vx": 200.0, "vy": 780.0, "ignore_armor": true}}]},
			# I 觉醒：第 54 / 57 / 70 号随机，释放期间霸体；动画播完起算 12s 觉醒窗口（O/P 解锁）
			"skill08": {"action": "skill_i", "cooldown": 20.0, "poise": true, "align_max": true,
				"pool": ["skill08", "skill11", "skill09_02"],
				"awaken_time": 12.0, "hits": []},
			# O 剑域三段（觉醒限定，第 55 号）：多段眩晕 → 横斩超远击退 + 流血 → 祈祷回血 + 加伤
			"skill09": {"action": "skill_o", "cooldown": 14.0, "poise": true, "require_buff": true,
				"hits": [
					{"at": 0.8, "range": 110.0, "height": 120.0, "damage": 1, "stun": 0.8, "sfx": "hit_heavy"},
					{"at": 1.3, "range": 110.0, "height": 120.0, "damage": 1, "stun": 0.8, "sfx": "hit_heavy"},
					{"at": 1.8, "range": 110.0, "height": 120.0, "damage": 1, "stun": 0.8, "sfx": "hit_heavy"},
					{"at": 3.0, "range": 260.0, "height": 130.0, "damage": 4, "sfx": "skill_blade", "bleed": 2,
						"knockback": {"force": 900.0, "impact": 0, "ignore_armor": true}},
					{"at": 5.2, "heal_ratio": 0.3, "self_buff": {"damage": 1, "time": 6.0}, "sfx": "voice_skill_cast"}]},
			# P 翻滚踢（觉醒限定，第 77 号）：0.20~0.55s 向前约 200px 且无敌穿身，末段踢击 2 伤 + 小击飞，命中返还 50% 冷却
			"skill20_03": {"action": "skill_p", "cooldown": 8.0, "poise": true, "require_buff": true,
				"blink_from": 0.20, "blink_to": 0.55, "blink_speed": 571.0, "refund_ratio": 0.5,
				"hits": [{"at": 0.85, "range": 110.0, "height": 110.0, "damage": 2, "sfx": "skill_fist",
					"launch": {"vx": 100.0, "vy": 300.0}}]},
		},
		"hud_skills": ["atk04", "skill02-", "skill04", "skill08", "skill09", "skill20_03"],
	},
	# 青笠 c012 已下掉玩家形态（动画撑不起招式，强度垫底），转生为精英怪——
	# 见 scripts/enemies/enemy_types.gd c012；第 5 席由银夜 z003 填补（见下）
	# ---------- 银夜：Z003，轻功剑客。普攻三段随机池 + 六技能（K/L/U/I/O/P，O/P 觉醒限定） ----------
	"z003": {
		"label": "银夜",
		"name": "将去未还",
		"hero": true, # 英雄级主角：K/L/U 普通技 + I 觉醒 + O/P 觉醒技（规范见 PROGRESS.md）
		"data": "res://art/characters/player/skulls/z003/z003_data.tres",
		"scale": 0.431, # 骨架 297.1px -> 128px
		"anim": {
			"idle": "stand",
			"run": "run",
			"dash": "autorush", # 0.083s 冲刺姿态帧，dash 时间短正好一闪而过
			"air": "jump", # 轻功跳跃动画兼滞空姿态
			"hurt": "atked", # 第 22 号：1 点伤害轻受击
			"hurt_heavy": "atked_heavy", # 第 27 号：2 点伤害重受击
			"low_idle": "weak", # 第 128 号：残血待机（血量比例 ≤ 20%，与双刺同界限）
			"dead": "atked_fall_end", # 第 26 号：先播一遍倒地（0.833s）
			"dead_hold": "dead", # 再循环躺尸定格（dead 只有 0.083s，不循环会闪回 setup pose）
			"getup": "getup", # 第 55 号：倒地链末段起身，整段无敌
		},
		"body_radius": 30.0, # 标准体型
		# 受击分档：1 伤=第 22 号轻受击；2 伤=第 27 号重受击；≥3 伤走倒地链（27 → 26 → 55 起身）
		"hurt_tiers": {"heavy": 2, "knockdown": 3},
		"knock_chain": ["atked_heavy", "atked_fall_end", "getup"],
		"low_hp_ratio": 0.2,
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
				"pool": ["skill04", "skill08"], "damage": 2, "lunge": 120.0,
				"hit_at": {"skill04": 0.26, "skill08": 0.45},
				"range": {"skill04": 100.0, "skill08": 105.0},
				"launch": {"vx": 150.0, "vy": 520.0}, # 击飞：往空中挑起，落地硬直
			},
			{
				"pool": ["skill05", "skill07"], "damage": 3, "lunge": 140.0,
				"hit_at": {"skill05": 0.15, "skill07": 0.16},
				"range": {"skill05": 135.0, "skill07": 128.0},
			},
		],
		"skills": {
			# K 蓄力斩（atk03_03/atk04_02 随机，编号 #15/#17）：蓄力期间霸体。
			# 两段都是双手蓄力大斩，hit_at 标"刀刃扫出"的中段（出手即判定不拖泥）。
			# speed 0.8 慢放：原速太赶，蓄力顿挫感出不来——慢放后实长 1.21/1.44s。
			# sword_qi：预留的远程剑气接口——以后这里填 {speed, range, damage} 就会在
			# 挥剑时刻发射剑气（走 projectile 管线），现在为 null 只发近战判定
			"skill14_02": {
				"action": "skill", "cooldown": 8.0, "poise": true, "speed": 0.8,
				"pool": ["atk03_03", "atk04_02"],
				"sword_qi": null, # 接口预留：剑气配置（未实装）
				"hit_at": {"atk03_03": 0.34, "atk04_02": 0.53},
				"range": {"atk03_03": 165.0, "atk04_02": 165.0},
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
			# I 觉醒（skill10）：爆气强化——立刻回血 + 限时全伤害提升。
			"skill10": {
				"action": "skill_i", "cooldown": 20.0, "poise": true, "align_max": true,
				"pool": ["skill10"],
				"heal": 2, "buff_damage": 2, "buff_time": 8.0,
				"hits": [],
			},
			# O 舜华斩·位移斩杀（觉醒限定，觉醒中才可释放；skill11/skill11-cankao/skill23_03 随机）：
			# 向前突进一整段，路径上所有敌人吃高伤。位移距离三动画统一 600px（以 skill11-cankao
			# 动画自带位移为准）：提速后 blink 0.15~0.90s × 800px/s = 600px——窗口压缩、突进更凌厉，
			# 距离不变。全程无敌；teleport_anims：#87 动画自带位移，原地播放、收招瞬间瞬移 600px
			#（不突兀），其 hit_at=99 收招帧补结算——瞬移后 path 从终点回扫整条位移路径。
			# 觉醒加持后数值：伤害 6→8、冷却 12→10、命中叠 2 层流血
			"skill11": {
				"action": "skill_o", "cooldown": 10.0, "poise": true, "invincible": true, "require_buff": true,
				"pool": ["skill11", "skill11-cankao", "skill23_03"],
				"blink_from": 0.15, "blink_to": 0.90, "blink_speed": 800.0,
				"teleport_anims": ["skill11-cankao"],
				"hit_at": {"skill11": 0.95, "skill11-cankao": 99.0, "skill23_03": 0.95},
				"range": {"skill11": 90.0, "skill11-cankao": 90.0, "skill23_03": 90.0},
				"height": 110.0, "damage": 8, "path": true, "bleed": 2, "sfx": "hit_heavy",
			},
			# P 觉醒·天倾（觉醒限定；第 115 号 sky_skill18_02 / 第 121 号 sky_skill24_03 随机，
			# 都是漂浮姿态）：全屏无差别 8 伤（无视距离/朝向/高度）；每房间首次释放额外加持
			# 本房全伤 +3——玩家实例随房间重建，_room_buff_used 天然一房一次，再放只剩伤害
			"sky_skill18_02": {
				"action": "skill_p", "cooldown": 25.0, "poise": true, "require_buff": true,
				"pool": ["sky_skill18_02", "sky_skill24_03"],
				"hit_at": {"sky_skill18_02": 1.20, "sky_skill24_03": 1.00},
				"range": {"sky_skill18_02": 0.0, "sky_skill24_03": 0.0},
				"height": 9999.0, "damage": 8, "full_screen": true,
				"room_buff": {"damage": 3}, "sfx": "skill_boom",
			},
		},
		"hud_skills": ["skill14_02", "skill02", "skill06", "skill10", "skill11", "sky_skill18_02"],
		# 通关结算演出：从这三个里挑一个播一遍，之后保持待机（其他形态留空=只待机，接口预留）
		"victory": ["skill17_02", "skill17_02-", "skill17_02-cankao"],
	},
}


static func get_profile(id: String) -> Dictionary:
	var profile: Dictionary = SKULLS.get(id, SKULLS[DEFAULT_ID])
	return profile


static func ids() -> Array:
	# 按强度顺序输出；以后新增形态若忘了写进 ORDER，也会补在末尾不至于漏掉
	var out: Array = []
	for id in ORDER:
		if SKULLS.has(id):
			out.append(id)
	for id in SKULLS:
		if not out.has(id):
			out.append(id)
	return out
