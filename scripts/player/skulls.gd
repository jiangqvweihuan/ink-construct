extends RefCounted

## 换头形态表（Skul 核心机制）：每个形态自带骨架、缩放、动画名映射、普攻段、技能表、HUD 技能顺序。
## 新增形态 = 往 SKULLS 加一项，并把 spine 三件套丢进 art/characters/player/skulls/<id>/。
##
## scale 的算法：像素探针量出骨架在 scale=1 时的墨迹高度，scale = 128 / 原始高度，
## 让所有形态在游戏里视觉上一样高（128px），不然换头会突然变大变小。
##   c021 骨架 324.8px -> 0.394
##   c023 骨架 270px   -> 0.474

const Skins := preload("res://scripts/systems/skins.gd")

const DEFAULT_ID := "c021"

## 形态强度顺序（由弱到强）：选角界面 / 化身谱按此排列，解锁条件也按同一梯度递增
## 解锁门槛：c013 击杀 20 → c023 击杀 60 → z000 通关 1 次 → z003 通关 3 次 + 击杀 150 → z002 通关 5 次 + 击杀 300
const ORDER := ["c021", "c013", "c023", "z000", "z003", "z002", "z001"]

const SKULLS := {
	"c021": {
		"label": "绯刃", # 代称：红缨双匕 + 面纱长裙的女刺客造型
		"name": "冷红绫",
		"data": "res://art/characters/player/c021_data.tres",
		"portrait": "res://art/characters/portraits/c021.png",
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
			{"anim": "atk01", "lock": 0.55, "hits": [0.34], "damage": 1, "range": 100.0, "lunge": 110.0, "cast_sfx": "assassin_basic_attack"},
			{"anim": "atk02", "lock": 0.50, "hits": [0.14], "damage": 1, "range": 85.0, "lunge": 110.0, "cast_sfx": "assassin_basic_attack"},
			# atk03 是回身横扫：匕尖甩到原点左侧 92px，判 both（前后都算命中）
			# 第二段加重到 2 伤：绯刃普攻单段最低，整套由 4 伤提到 5 伤补持续输出。
			{"anim": "atk03", "lock": 1.30, "hits": [{"at": 0.26, "damage": 1}, {"at": 0.72, "damage": 2, "range": 75.0}], "damage": 1, "range": 95.0, "lunge": 120.0, "both": true, "cast_sfx": "assassin_basic_attack"},
		],
		"skills": {
			# K 穿影突刺（第 19 号 skill01，1.567s）：0.75~1.28s 隐身前冲穿过敌人，1.30s 现身一刀。
			# speed 1.4 提速去掉"顿感"，blink_speed 同步 ×1.4 保持原位移距离；invincible 整段无敌
			# （对齐影殇 O 的位移技规则）。时刻表仍按动画秒标定，提速后自动对齐。
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
			# U 掷匕·缚（第 25 号 skill02-cankao，2.05s）：远程投掷一柄飞刃（1.43s 出手），
			# 命中后定身 3 秒（期间敌人不能移动但可以出手），并从命中点分裂出第二把继续飞。
			# 无 blink / teleport：位移只靠动画本身的根骨后跃（root_motion），不会出现闪现或残影。
			"skill02-cankao": {
				"action": "skill_ult", "cooldown": 9.0, "projectile_sfx": "assassin_projectile",
				"root_motion": true, # 动画 1.2~1.42s 把根骨后挪约 430 骨架像素（≈170 世界像素）：节点跟着挪，收招后停在那里
				"hits": [{
					"at": 1.43, "damage": 3, "sfx": "skill_blade",
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
				"anim": "skill01", "lock": 1.883, "cancel": 0.0, "lunge": 110.0, "cast_sfx": "weapon_blade",
				"hits": [
					{"at": 0.75, "damage": 2, "range": 372.0, "pull": 80.0, "sfx": "hit_heavy"},
					{"at": 1.68, "damage": 3, "range": 145.0},
				],
			},
		],
		"skills": {
			# 唯一技能（K 位）：转鞭，skill02 4.167s；永久修炼「静守·初」解锁起手霸体。
			# 0.15~3.0s 每 0.5s 对前后方 130px 内所有敌人各打 1 点（both=前后都转）；
			# 3.6s 最后一记超远甩鞭 R1051 -> 500px，伤害 2→5。
			# 中毒挂"长鞭剑命中"而非只挂尾端：转鞭每一跳（tick）与尾端甩鞭都带 poison，
			# 全程任意一下打中都会让目标中毒（4 秒，每 0.5 秒扣 1 点；不叠层，重复命中只刷新时长）
			# ranged_guard：转鞭期间免疫敌方投射物并原路弹回（工程暂无敌方投射物，接口已预埋）
			"skill02": {
				"action": "skill", "cooldown": 9.0, "loop_sfx": "weapon_blade",
				"ranged_guard": true,
				"tick": {"from": 0.15, "to": 3.0, "interval": 0.5, "range": 130.0, "height": 140.0, "damage": 1, "both": true, "poison": 4.0},
				"hits": [{"at": 3.6, "range": 500.0, "height": 150.0, "damage": 5, "sfx": "skill_blade", "poison": 4.0}],
			},
		},
		"hud_skills": ["skill02"],
	},
	# ---------- 烬生：Z001，以命换火的狂战士。J 三段斩 / K 焚骨三叩 / L 烬灭 / I 余烬 / O 焚影 / P 燎原 ----------
	"z001": {
		"label": "烬生",
		"name": "赤烬",
		"hero": true,
		"data": "res://art/characters/player/skulls/z001/z001_data.tres",
		"portrait": "res://art/characters/portraits/z001.png",
		"scale": 0.48, # 骨架约 267px -> 128px，与镇岳同档
		"body_radius": 30.0,
		"anim": {
			"idle": "stand", # 123
			"run": "run", # 69
			"dash": "autorush", # 28（兜底；实际走下面的随机双闪）
			"air": "jump02_mid", # 53
			"hurt": "atked", # 22（≤4 伤不播，仅作兜底）
			"hurt_heavy": "atked_heavy", # 27
			"fall": "atked_fall_end", # 26
			"getup": "getup", # 50
			"low_idle": "weak", # 126
			"dead": "dead", # 48
			"dead_hold": "dead",
			"jump_mid": "jump02_mid", # 53
			"jump_down": "jump03_down", # 56
			"jump_land": "jump03_end", # 57
		},
		# 跳跃无起跳过渡：离地直接进上升姿态（53），下落 56，落地 57
		"jump_no_start": true,
		# 闪避：28 autorush（0.167s × 760）与 47 dash_front（0.5s × 260）随机，
		# 两者位移都在 127~130px，随机只换演出不换机动性
		"dash_pool": {
			"move": [
				{"anim": "autorush", "time": 0.167, "speed": 760.0},
				{"anim": "dash_front", "time": 0.5, "speed": 260.0},
			],
			"move_cd": 0.5,
		},
		# 受击阈值：≤4 伤无硬直（player.gd 专用分支），≥5 伤走 27 → 26 → 50 整条链
		"hurt_tiers": {"heavy": 999, "knockdown": 5},
		"knock_chain": ["atked_heavy", "atked_fall_end", "getup"],
		"low_hp_ratio": 0.2,
		# J 普攻：动画 2（"3"，2.233s）三段 2 / 2 / 3，末段挂 10 秒易伤。
		# 命中时刻对齐剪影峰值（0.38/0.94/1.82s），射程按峰值伸展 88/121/110px 标定。
		"attacks": [
			{
				"anim": "3", "lock": 2.233, "lunge": 90.0, "cast_sfx": "weapon_sword",
				"hits": [
					{"at": 0.38, "damage": 2, "range": 90.0, "height": 110.0, "sfx": "hit_heavy"},
					{"at": 0.94, "damage": 2, "range": 125.0, "height": 110.0, "sfx": "hit_heavy"},
					{"at": 1.82, "damage": 3, "range": 115.0, "height": 110.0, "sfx": "hit_heavy",
						"vulnerable": {"ratio": 0.25, "time": 10.0}},
				],
			},
		],
		"skills": {
			# K 焚骨三叩：动画 6（atk03）连播 3 次，每轮双峰 0.12/0.22s 各 1 伤，合计 6 伤。
			# 剪影峰值 184px，射程取 170；只判身前（动画没有回身段）。
			"burn_k": {
				"action": "skill", "cooldown": 6.0, "anim": "atk03", "repeat": 3,
				"repeat_hits": [
					{"at": 0.12, "damage": 1},
					{"at": 0.22, "damage": 1},
				],
				"range": 170.0, "height": 110.0,
				"sfx": "hit_heavy", "cast_sfx": "weapon_sword",
			},
			# L 烬灭斩：动画 86（skill23）蓄力猛击，5 伤 + 已损生命 20%（Boss 10%）额外伤害。
			# 落刀峰值在 1.21s、剪影 151px，命中与射程同步到 1.21s / 150px。
			"burn_l": {
				"action": "skill_sweep", "cooldown": 8.0, "anim": "skill23", "poise": true,
				"hits": [{
					"at": 1.21, "range": 150.0, "height": 120.0, "damage": 5,
					"execute": {"normal": 0.2, "boss": 0.1}, "sfx": "skill_blade",
				}],
			},
			# I 余烬重燃：动画 68 / 92 随机，整段播完前把生命恢复至满值
			"burn_i": {
				"action": "skill_i", "cooldown": 25.0, "poise": true,
				"pool": ["mie_03", "skill12_02"], "align_max": true,
				"heal_full": true, "hits": [],
			},
			# O 焚影掠：动画 73（skill03）向前闪身约 240px；路径小怪秒杀，精英 / Boss 固定 8 伤。
			# 现身处斩击在 0.95s、剪影 137px，命中与射程对齐为 0.95s / 150px。
			"burn_o": {
				"action": "skill_o", "cooldown": 9.0, "anim": "skill03",
				"blink_from": 0.15, "blink_to": 0.75, "blink_speed": 400.0, "phase": true,
				"hits": [{
					"at": 0.95, "range": 150.0, "height": 140.0, "path": true, "damage": 8,
					"dash_kill": {"elite_damage": 8}, "sfx": "skill_blade",
				}],
			},
			# P 烬火燎原：动画 95（skill14_02）正前方 280px 大范围 12 伤 + 5 秒眩晕。
			# 火线在 0.34s 起燃，命中对齐该帧；范围由同步播放的巨型斩焰特效覆盖。
			"burn_p": {
				"action": "skill_p", "cooldown": 18.0, "anim": "skill14_02", "poise": true,
				"hits": [{
					"at": 0.34, "range": 280.0, "height": 150.0, "damage": 12,
					"stun": 5.0, "sfx": "skill_boom",
				}],
			},
		},
		"hud_skills": ["burn_k", "burn_l", "burn_i", "burn_o", "burn_p"],
	},
	# ---------- 镇岳：C013，长柄狼牙棒，动作全是挥砸，出手重、收招慢 ----------
	"c013": {
		"label": "镇岳",
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
		# 倒地链（镇岳专用）：6 重受击 → 3 浮空重受击 → 5 倒地 → 9 起身，段与段按动画真实时长无缝接续，
		# 起身段整段无敌；播放期间全程 State.HURT，结束回 IDLE/FALL
		"knock_chain": ["atked_heavy", "atked_air_heavy", "atked_fall_end", "getup"],
		# 探针实测（已乘 0.487）：skill02_01 后侧 156@0.13，skill02_03 后侧 185@0.26
		# 狼牙棒挥砸的落点在原点后方，所以普攻/挥砸类判 both，动画扫到哪边都能命中
		# 两段普攻（第 16 号 + 第 18 号）：数值比原来 1/1/2 整体抬一档 -> 2 / 3
		"attacks": [
			{"anim": "skill02_01", "lock": 0.44, "hits": [0.13], "damage": 2, "range": 156.0, "lunge": 120.0, "both": true, "cast_sfx": "monk_basic_attack"},
			{"anim": "skill02_03", "lock": 0.47, "hits": [0.26], "damage": 3, "range": 185.0, "lunge": 130.0, "both": true, "cast_sfx": "monk_basic_attack"},
		],
		"skills": {
			# K 横扫（skill01 1.85s，动画不变）：两段挥棒
			# 0.60s 第一段：前后 198px 全扫，3 伤 + 击退 620（撞人 1 伤）+ 落点定身 2 秒
			# 1.66s 第二段：不打伤害，给自己挂金钟罩（免疫 1 次攻击，8 秒没挨打就自己散）
			"skill01": {
				"action": "skill", "cooldown": 3.5, "cast_sfx": "monk_bell_quake",
				"hits": [
					{"at": 0.60, "range": 198.0, "height": 110.0, "damage": 3, "sfx": "skill_fist", "both": true,
						"knockback": {"force": 620.0, "impact": 1}, "root": 2.0},
					{"at": 1.66, "self_shield": {"hits": 1, "time": 8.0}, "sfx": "skill_boom"},
				],
			},
			# L 横扫（skill03 1.5s，动画不变）：伤害 1→3；命中晕眩 2 秒（不能移动也不能出手，立即打断起手）
			"skill03": {
				"action": "skill_sweep", "cooldown": 5.0,
				"sfx_events": [{"at": 0.80, "sfx": "monk_vajra_wrath"}],
				"hits": [{"at": 0.87, "range": 191.0, "height": 110.0, "damage": 3, "sfx": "voice_fan_hit", "stun": 2.0}],
			},
			# 全程举棒蓄力，3.05s 才砸下来：砸地只回血、不打伤害
			# 定山：蓄力期间自身霸体 + 反伤（挨打把伤害弹回攻击者），砸地回 2 血——站桩挨打换血的坦克循环
			"skill02": {
				"action": "skill_ult", "cooldown": 9.0, "cast_sfx": "monk_meditation",
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
		"portrait": "res://art/characters/portraits/z000.png",
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
					{"at": 0.16, "range": 170.0, "height": 120.0, "damage": 1, "bleed": 1, "both": true, "sfx": "voice_fan_hit"},
					{"at": 0.34, "range": 170.0, "height": 120.0, "damage": 1, "bleed": 1, "both": true, "sfx": "voice_fan_hit"},
					{"at": 0.50, "range": 170.0, "height": 120.0, "damage": 1, "bleed": 1, "both": true, "sfx": "voice_fan_hit"}]},
			# L 月华斩：第 64 / 58 号随机，两套动作都只按挥剑落点做近战判定。
			# 命中叠 1 层流血并附加 5 秒易伤（后续承伤 +25%），末端同时喷出火焰特效。
			"skill02-": {"action": "skill_sweep", "cooldown": 8.0, "poise": true,
				"pool": ["skill02-", "skill12"],
				"hit_at": {"skill02-": 1.20, "skill12": 0.62},
				"range": {"skill02-": 210.0, "skill12": 240.0},
				"height": 130.0, "damage": 5, "bleed": 1, "sfx": "skill_blade",
				"vulnerable": {"ratio": 0.25, "time": 5.0}},
			# U 飞脚：第 50 号，超高击飞（无视霸体，连 Boss 也能挑起来）
			"skill04": {"action": "skill_ult", "cooldown": 10.0, "poise": true,
				"hits": [{"at": 0.48, "range": 110.0, "height": 120.0, "damage": 3, "sfx": "hit_heavy",
					"launch": {"vx": 200.0, "vy": 780.0, "ignore_armor": true}}]},
			# I 觉醒：第 54 / 57 / 70 号随机，释放期间霸体；动画播完起算 12s 觉醒窗口（O/P 解锁）
			"skill08": {"action": "skill_i", "cooldown": 20.0, "poise": true, "align_max": true, "cast_sfx": "swordsman_swift_slash",
				"pool": ["skill08", "skill11", "skill09_02"],
				"awaken_time": 12.0, "hits": []},
			# O 剑域三段（觉醒限定，第 55 号）：多段眩晕 → 横斩超远击退 + 流血 → 祈祷回血 + 加伤
			"skill09": {"action": "skill_o", "cooldown": 14.0, "poise": true, "require_buff": true,
				"hits": [
					{"at": 0.8, "range": 110.0, "height": 120.0, "damage": 1, "stun": 0.8, "both": true, "sfx": "voice_fan_hit"},
					{"at": 1.3, "range": 110.0, "height": 120.0, "damage": 1, "stun": 0.8, "both": true, "sfx": "voice_fan_hit"},
					{"at": 1.8, "range": 110.0, "height": 120.0, "damage": 1, "stun": 0.8, "both": true, "sfx": "voice_fan_hit"},
					{"at": 3.0, "range": 260.0, "height": 130.0, "damage": 4, "sfx": "skill_blade", "bleed": 2,
						"knockback": {"force": 900.0, "impact": 0, "ignore_armor": true}},
					{"at": 5.2, "heal_ratio": 0.25, "self_buff": {"damage": 1, "time": 6.0}, "sfx": "voice_skill_cast"}]},
			# P 翻滚踢（觉醒限定，第 77 号）：0.20~0.55s 向前约 200px 且无敌穿身。
			# 末段踢击 5 伤 + 小击飞；实际造成伤害后追加 3 秒眩晕与目标专属受击特效，命中返还 50% 冷却。
			"skill20_03": {"action": "skill_p", "cooldown": 8.0, "poise": true, "require_buff": true,
				"blink_from": 0.20, "blink_to": 0.55, "blink_speed": 571.0, "refund_ratio": 0.5,
				"hits": [{"at": 0.85, "range": 110.0, "height": 110.0, "damage": 5, "sfx": "skill_fist",
					"launch": {"vx": 100.0, "vy": 300.0}}]},
		},
		"hud_skills": ["atk04", "skill02-", "skill04", "skill08", "skill09", "skill20_03"],
	},
	# ---------- 绛弦：Z002，黑衣琵琶乐师。四段普攻 + 魔音 / 魅惑 / 癫狂，六技能 ----------
	"z002": {
		"label": "绛弦",
		"name": "苏挽音",
		"hero": true,
		"data": "res://art/characters/enemies/z002/z002_data.tres",
		"portrait": "res://art/characters/portraits/z002.png",
		"scale": 0.415, # 骨架约 308.6px -> 128px，与其他英雄同高
		"body_radius": 30.0,
		"anim": {
			"idle": "block", # 31
			"run": "run4", # 66
			"dash": "dash02_front", # 48
			"air": "jump_up",
			"hurt": "atked", # 23
			"hurt_heavy": "atked",
			"getup": "getup", # 独立起身：27 号实际停在躺姿，不能直接切待机
			"dead": "atked_fall_end",
			"dead_hold": "dead",
			"jump_start": "jump_start", # 60
			"jump_mid": "jump_up", # 61
			"jump_down": "jump_mid", # 59
			"jump_land": "jump_end", # 58
		},
		"dash_time": 0.5,
		"dash_speed": 300.0,
		# 仅实际伤害严格大于 3 才倒地：23 -> 28 -> 27 -> 独立起身（起身整段无敌）。
		"hurt_tiers": {"heavy": 999, "knockdown": 4},
		"knock_chain": ["atked", "atked_fall_end-", "atked_fall_end", "getup"],
		"attacks": [
			{"anim": "atk01", "lock": 0.433, "hits": [{"at": 0.24, "damage": 1, "range": 105.0}], "lunge": 70.0, "cast_sfx": ""},
			{"anim": "atk02", "lock": 0.467, "hits": [{"at": 0.25, "damage": 2, "range": 115.0}], "lunge": 75.0, "cast_sfx": ""},
			{"anim": "atk03", "lock": 0.300, "hits": [{"at": 0.16, "damage": 2, "range": 120.0}], "lunge": 80.0, "cast_sfx": ""},
			{"anim": "atk04", "lock": 1.200, "damage": 3, "lunge": 0.0, "cast_sfx": "",
				"hits": [{"at": 0.82, "damage": 3, "projectile": {"speed": 600.0, "range": 430.0, "style": "magic_sound", "frenzy": 12.0, "projectile_sfx": "pipa_basic_wave"}}]},
		],
		"skills": {
			# K 踏弦：67 / 95 随机。跟随素材根位移，只位移、无伤害，全程无敌并穿身。
			"run-": {"action": "skill", "cooldown": 2.5, "speed": 1.4, "invincible": true, "root_motion": true, "phase": true, "cast_sfx": "pipa_string_step",
				"pool": ["run-", "skill13_02-cankao"], "hits": []},
			# L 黍离：73 / 74 随机，各自在曲终发穿透魔音；翻倍癫狂且至少 12 秒，释放即回 3。
			"skill03": {"action": "skill_sweep", "cooldown": 8.0, "pool": ["skill03", "skill04"], "cast_sfx": "pipa_taiyu",
				"hit_at": {"skill03": 0.68, "skill04": 0.84}, "range": {"skill03": 0.0, "skill04": 0.0},
				"height": 100.0, "damage": 3, "heal": 3, "sfx": "voice_skill_cast",
				"projectile": {"speed": 650.0, "range": 520.0, "pierce": true, "style": "magic_sound", "frenzy_double": true}},
			# U 摄心 / 众生同狂：同一配置、同一冷却；觉醒后只换演出与命中逻辑。
			"skill13-": {"action": "skill_ult", "cooldown": 16.0, "cast_sfx": "pipa_mind_snare",
				"hits": [{"at": 0.72, "charm": true, "sfx": "voice_skill_cast"}],
				"awaken": {"anim": "skill10", "invincible": true,
					"hits": [{"at": 5.35, "damage": 1, "full_screen": true, "height": 9999.0, "frenzy": 12.0, "frenzy_empower": true, "sfx": "skill_boom"}]}},
			# I 红尘劫：霸体而非无敌；曲终恢复已损生命一半并进入 8 秒觉醒。
			"skill07_02": {"action": "skill_i", "cooldown": 24.0, "poise": true, "awaken_time": 8.0, "hits": [], "cast_sfx": "pipa_mortal_tribulation"},
			# O 八音断识：八个演奏节点各发一颗火弹；伤害递减与六感只在真实碰撞后结算。
			"skill10_03": {"action": "skill_o", "cooldown": 1.0, "poise": true, "require_buff": true, "once_per_awaken": true,
				"cast_sfx": "", "projectile_sfx": "pipa_eight_tones",
				"hits": [
					{"at": 0.55, "damage": 4, "projectile": {"speed": 650.0, "range": 2000.0, "pierce": false, "scale": 0.75, "fx_scale": 0.35, "pipa_wave": true}},
					{"at": 0.95, "damage": 4, "projectile": {"speed": 650.0, "range": 2000.0, "pierce": false, "scale": 0.75, "fx_scale": 0.35, "pipa_wave": true}},
					{"at": 1.35, "damage": 4, "projectile": {"speed": 650.0, "range": 2000.0, "pierce": false, "scale": 0.75, "fx_scale": 0.35, "pipa_wave": true}},
					{"at": 1.75, "damage": 4, "projectile": {"speed": 650.0, "range": 2000.0, "pierce": false, "scale": 0.75, "fx_scale": 0.35, "pipa_wave": true}},
					{"at": 2.15, "damage": 4, "projectile": {"speed": 650.0, "range": 2000.0, "pierce": false, "scale": 0.75, "fx_scale": 0.35, "pipa_wave": true}},
					{"at": 2.55, "damage": 4, "projectile": {"speed": 650.0, "range": 2000.0, "pierce": false, "scale": 0.75, "fx_scale": 0.35, "pipa_wave": true}},
					{"at": 2.95, "damage": 4, "projectile": {"speed": 650.0, "range": 2000.0, "pierce": false, "scale": 0.75, "fx_scale": 0.35, "pipa_wave": true}},
					{"at": 3.65, "damage": 4, "sfx": "skill_boom", "projectile": {"speed": 650.0, "range": 2000.0, "pierce": false, "scale": 0.75, "fx_scale": 0.35, "pipa_wave": true}}]},
			# P 心魔引：第 100 号动画完整播放 5.333 秒；4.60 秒音效结束后再引爆全房状态。
			"skill09": {"action": "skill_p", "cooldown": 22.0, "poise": true, "require_buff": true, "cast_sfx": "pipa_inner_demon",
				"pool": ["skill16_02-"], "hits": [{"at": 4.60, "mind_detonate": true, "sfx": "skill_boom"}]},
		},
		"hud_skills": ["run-", "skill03", "skill13-", "skill07_02", "skill10_03", "skill09"],
	},
	# 青笠 c012 已下掉玩家形态（动画撑不起招式，强度垫底），转生为精英怪——
	# 见 scripts/enemies/enemy_types.gd c012；绛弦 z002 位于剑仙与影殇之间。
	# ---------- 影殇：Z003，轻功剑客。普攻三段随机池 + 六技能（K/L/U/I/O/P，O/P 觉醒限定） ----------
	"z003": {
		"label": "影殇",
		"name": "将去未还",
		"hero": true, # 英雄级主角：K/L/U 普通技 + I 觉醒 + O/P 觉醒技（规范见 PROGRESS.md）
		"data": "res://art/characters/player/skulls/z003/z003_data.tres",
		"portrait": "res://art/characters/portraits/z003.png",
		"scale": 0.431, # 骨架 297.1px -> 128px
		"anim": {
			"idle": "stand",
			"run": "run",
			"dash": "autorush", # 0.083s 冲刺姿态帧，dash 时间短正好一闪而过
			"air": "jump", # 轻功跳跃动画兼滞空姿态
			"hurt": "atked", # 第 22 号：1 点伤害轻受击
			"hurt_heavy": "atked_heavy", # 第 27 号：2 点伤害重受击
			"low_idle": "weak", # 第 128 号：残血待机（血量比例 ≤ 20%，与绯刃同界限）
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
				"range": {"skill03": 150.0, "skill09": 135.0},
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
			# K 崩云·斩影（atk03_03/atk04_02 随机，编号 #15/#17）：蓄力期间霸体。
			# 两段都是双手蓄力大斩，hit_at 标"刀刃扫出"的中段（出手即判定不拖泥）。
			# speed 0.8 慢放：原速太赶，蓄力顿挫感出不来——慢放后实长 1.21/1.44s。
			# scar（独门机制）：刀痕留在蓄力起点 0.55 秒后自主回响第二刀——
			# 向前挥斩时刀痕正好封住身后的退路，回响命中还返还 1 秒冷却。
			"skill14_02": {
				"action": "skill", "cooldown": 7.0, "poise": true, "speed": 0.8,
				"pool": ["atk03_03", "atk04_02"],
				"scar": {"delay": 0.55, "damage": 2, "bleed": 1, "refund": 1.0, "range_scale": 1.15},
				"hit_at": {"atk03_03": 0.34, "atk04_02": 0.53},
				"range": {"atk03_03": 180.0, "atk04_02": 180.0},
				"height": 110.0, "damage": 4, "both": true, "sfx": "z003_k_thrust", "sfx_on_release": true,
			},
			# L 冲拳（skill02 0.883s）：不动剑的武德拳，伤害低冷却短；
			# 击退机制：命中把敌人往攻击方向轰飞，撞到同伴双方吃组合伤害、撞墙自己再吃一下
			"skill02": {
				"action": "skill_sweep", "cooldown": 3.0, "poise": true,
				"hits": [{"at": 0.71, "range": 95.0, "height": 90.0, "damage": 1, "sfx": "z003_l_hit",
					"knockback": {"force": 620.0, "impact": 1}}],
			},
			# U 拍地时停（skill06 1.567s）：0.5s 掌落大地，定住当前场景所有敌人——
			# 杂兵 10s / 精英 8s / Boss 5s；无视霸体，连 Boss 技能前摇都打断（规则级控制）
			"skill06": {
				"action": "skill_ult", "cooldown": 16.0, "poise": true, "full_cast_sfx": "jiangqu_silence",
				"stop": {"at": 0.5, "mob": 10.0, "elite": 8.0, "boss": 5.0},
				"hits": [],
			},
			# I 觉醒（skill10）：爆气强化——立刻回血 + 限时全伤害提升；0.25 倍慢放，约 0.5 秒原动画完整展示 2 秒。
			"skill10": {
				"action": "skill_i", "cooldown": 20.0, "poise": true, "align_max": true, "speed": 0.25,
				"pool": ["skill10"], "cast_sfx": "z003_awaken",
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
				"action": "skill_o", "cooldown": 10.0, "poise": true, "invincible": true, "require_buff": true, "cast_sfx": "jiangqu_hibiscus_slash",
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
				"action": "skill_p", "cooldown": 30.0, "poise": true, "require_buff": true, "full_cast_sfx": "z003_p_cast",
				"full_cast_volume_db": 8.0, # 笑声原本太轻，单独提高这一条完整施法音
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
	return Skins.player_profile(id, profile)


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
