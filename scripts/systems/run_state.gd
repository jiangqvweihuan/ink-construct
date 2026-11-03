extends Node

## 一局（run）的状态：房间进度 + 跨房间带走的东西 + 局内强化等级。
## 局内循环：连续 3 个房间，每清一间免费选一次强化，三关全过进 Boss 房，斩杀 Boss 通关。

const BASE_HP := 8
const BossTypes := preload("res://scripts/enemies/boss_types.gd")

## 两种模式：冒险 = 三关 + Boss 通关；无尽 = 每层都是「三小关 + 一个 Boss」，Boss 倒下进下一层
const MODE_ADVENTURE := "adventure"
const MODE_ENDLESS := "endless"

## 五档问境：只调整普通怪数量与所有敌方攻击，不改敌人血量/速度；默认第二档「落笔」。
const DIFFICULTIES := [
	{"label": "濡墨", "seal": "壹", "desc": "墨意初濡，且试锋芒", "count": 0.8, "attack": -1},
	{"label": "落笔", "seal": "贰", "desc": "笔落惊风，攻守有度", "count": 1.0, "attack": 0},
	{"label": "惊锋", "seal": "叁", "desc": "锋鸣渐急，杀机四伏", "count": 1.2, "attack": 1},
	{"label": "狂澜", "seal": "肆", "desc": "墨浪倾天，险中求胜", "count": 1.45, "attack": 2},
	{"label": "无归", "seal": "伍", "desc": "此去无归，双雄连战", "count": 1.75, "attack": 3},
]

## 每个房间的波次配置；index 越大越难
const ROOMS := [
	{
		"label": "残卷山谷 · 外院",
		"waves": [
			{"count": 5, "hp": 4, "speed": 1.0},
			{"count": 6, "hp": 4, "speed": 1.02},
		],
	},
	{
		"label": "残卷山谷 · 中庭",
		"waves": [
			{"count": 6, "hp": 6, "speed": 1.0, "elite": 1},
			{"count": 7, "hp": 6, "speed": 1.05},
		],
	},
	{
		"label": "残卷山谷 · 墨堂",
		"waves": [
			{"count": 6, "hp": 6, "speed": 1.1, "elite": 1},
			{"count": 4, "hp": 8, "speed": 1.05, "elite": 1},
		],
	},
]

## Boss 房（三关全过后进入）：无波次，只有 Run.boss_id 指定的一只 Boss
const BOSS_ROOM := {"label": "残卷山谷 · 墨堂深处", "waves": []}

## 局内强化 · 通用池：全部是"能和机制搭话"的词条（不做纯数值移速），任何形态都吃得下。
const UPGRADES := {
	"damage": {"label": "锋锐", "desc": "全部伤害 +1", "max": 5, "icon": "icon_sword"},
	"cooldown": {"label": "静心", "desc": "技能冷却 -15%", "max": 3, "icon": "icon_undo"},
	"hp": {"label": "铁骨", "desc": "生命上限 +1，并回满", "max": 3, "icon": "icon_potion"},
	# 疾影：闪避时长 +20% —— 闪避距离与"完美闪避"判定窗口同步变长，回收闪避冷却 -10%
	"dash": {"label": "疾影", "desc": "闪避更远，完美闪避窗口更长", "max": 3, "icon": "icon_arrow_up"},
	# 掠影：完美闪避的收益直接加档（加伤与垫底无敌一起抬）
	"dodge": {"label": "掠影", "desc": "完美闪避赏伤 +1、无敌 +0.2 秒", "max": 2, "icon": "icon_medal"},
}

## 形态专属强化 · 流派制：每个形态 3 条流派，各 3 级（初/续/极）。
## tier 2/3 需要先拥有前置卡（req）——一局 3 次强化正好能把一条流派走到"极"。
## theme 给面板配色用（0 朱砂 / 1 墨青 / 2 赭金）。
## 只对当前形态生效：换头后旧形态的卡休眠，换回来再生效（player._apply_form_mods 过滤 forms）。
const FORM_UPGRADES := {
	# ---------- 绛弦·苏挽音：万狂同奏（乱弦 / 同梦 / 心魔） ----------
	"z002_chorus_1": {"label": "乱弦 · 初", "desc": "魔音命中时，使周围 240 内最多 2 名敌人癫狂 6 秒", "max": 1, "icon": "icon_sword", "forms": ["z002"], "path": "乱弦", "tier": 1, "theme": 0},
	"z002_chorus_2": {"label": "乱弦 · 续", "desc": "癫狂敌人伤及同伴时，使受伤者癫狂 4 秒", "max": 1, "icon": "icon_sword", "forms": ["z002"], "path": "乱弦", "tier": 2, "theme": 0, "req": "z002_chorus_1"},
	"z002_chorus_3": {"label": "乱弦 · 极", "desc": "癫狂敌人伤及同伴时，再附加 1 层怨与 1 层六感尽失", "max": 1, "icon": "icon_sword", "forms": ["z002"], "path": "乱弦", "tier": 3, "theme": 0, "req": "z002_chorus_2"},
	"z002_allure_1": {"label": "同梦 · 初", "desc": "摄心额外魅惑周围 240 内一名非首领敌人 6 秒，不为其回血", "max": 1, "icon": "icon_undo", "forms": ["z002"], "path": "同梦", "tier": 1, "theme": 1},
	"z002_allure_2": {"label": "同梦 · 续", "desc": "魅惑敌人伤及同伴时，自身魅惑延长 1 秒，最长 20 秒", "max": 1, "icon": "icon_undo", "forms": ["z002"], "path": "同梦", "tier": 2, "theme": 1, "req": "z002_allure_1"},
	"z002_allure_3": {"label": "同梦 · 极", "desc": "魅惑敌人对同伴造成的伤害翻倍", "max": 1, "icon": "icon_undo", "forms": ["z002"], "path": "同梦", "tier": 3, "theme": 1, "req": "z002_allure_2"},
	"z002_mind_1": {"label": "心魔 · 初", "desc": "心魔引引爆后，存活目标保留六感尽失", "max": 1, "icon": "icon_arrow_up", "forms": ["z002"], "path": "心魔", "tier": 1, "theme": 2},
	"z002_mind_2": {"label": "心魔 · 续", "desc": "心魔引每击杀一名敌人，返还 3 秒冷却", "max": 1, "icon": "icon_arrow_up", "forms": ["z002"], "path": "心魔", "tier": 2, "theme": 2, "req": "z002_mind_1"},
	"z002_mind_3": {"label": "心魔 · 极", "desc": "心魔引击杀时，对周围 240 内敌人造成 3 伤并附加 6 秒癫狂", "max": 1, "icon": "icon_arrow_up", "forms": ["z002"], "path": "心魔", "tier": 3, "theme": 2, "req": "z002_mind_2"},
	# ---------- 双刺·冷红绫：绯羽 / 归刃 / 影饵 ----------
	"c021_feather_1": {"label": "绯羽 · 初", "desc": "K 命中剥离全部流血，每层凝一羽（最多 3 羽）", "max": 1, "icon": "icon_sword", "forms": ["c021"], "path": "绯羽", "tier": 1, "theme": 0},
	"c021_feather_2": {"label": "绯羽 · 续", "desc": "U 消耗全部绯羽，每羽让掷匕多分裂一次", "max": 1, "icon": "icon_sword", "forms": ["c021"], "path": "绯羽", "tier": 2, "theme": 0, "req": "c021_feather_1"},
	"c021_feather_3": {"label": "绯羽 · 极", "desc": "分裂匕命中时牵引周围敌人并定身", "max": 1, "icon": "icon_sword", "forms": ["c021"], "path": "绯羽", "tier": 3, "theme": 0, "req": "c021_feather_2"},
	"c021_return_1": {"label": "归刃 · 初", "desc": "U 掷匕在命中点或终点留匕 8 秒", "max": 1, "icon": "icon_undo", "forms": ["c021"], "path": "归刃", "tier": 1, "theme": 1},
	"c021_return_2": {"label": "归刃 · 续", "desc": "留匕期间 K 先回闪至最近落匕处并收匕", "max": 1, "icon": "icon_undo", "forms": ["c021"], "path": "归刃", "tier": 2, "theme": 1, "req": "c021_return_1"},
	"c021_return_3": {"label": "归刃 · 极", "desc": "收匕牵动落点敌人：多匕拉撞，单目标续缚", "max": 1, "icon": "icon_undo", "forms": ["c021"], "path": "归刃", "tier": 3, "theme": 1, "req": "c021_return_2"},
	"c021_bait_1": {"label": "影饵 · 初", "desc": "完美闪避留下 1.5 秒残影，引诱附近敌人", "max": 1, "icon": "icon_arrow_up", "forms": ["c021"], "path": "影饵", "tier": 1, "theme": 2},
	"c021_bait_2": {"label": "影饵 · 续", "desc": "残影消失时定身仍在追逐它的敌人", "max": 1, "icon": "icon_arrow_up", "forms": ["c021"], "path": "影饵", "tier": 2, "theme": 2, "req": "c021_bait_1"},
	"c021_bait_3": {"label": "影饵 · 极", "desc": "残影存在时，L 让人影交叉处只叠加流血", "max": 1, "icon": "icon_arrow_up", "forms": ["c021"], "path": "影饵", "tier": 3, "theme": 2, "req": "c021_bait_2"},
	# ---------- 梅剑·白疏影：缠枝 / 梅烙 / 回环 ----------
	"c023_bind_1": {"label": "缠枝 · 初", "desc": "普攻首段把拉回者撞向近敌，双方定身", "max": 1, "icon": "icon_sword", "forms": ["c023"], "path": "缠枝", "tier": 1, "theme": 0},
	"c023_bind_2": {"label": "缠枝 · 续", "desc": "K 尾鞭将命中者统一拉至身前", "max": 1, "icon": "icon_sword", "forms": ["c023"], "path": "缠枝", "tier": 2, "theme": 0, "req": "c023_bind_1"},
	"c023_bind_3": {"label": "缠枝 · 极", "desc": "尾鞭留下 5 秒枝界，界内敌人无法走出", "max": 1, "icon": "icon_sword", "forms": ["c023"], "path": "缠枝", "tier": 3, "theme": 0, "req": "c023_bind_2"},
	"c023_plum_1": {"label": "梅烙 · 初", "desc": "普攻两段命中同一中毒目标，结成梅烙", "max": 1, "icon": "icon_potion", "forms": ["c023"], "path": "梅烙", "tier": 1, "theme": 1},
	"c023_plum_2": {"label": "梅烙 · 续", "desc": "K 命中梅烙目标会催花：定身并向周围传毒", "max": 1, "icon": "icon_potion", "forms": ["c023"], "path": "梅烙", "tier": 2, "theme": 1, "req": "c023_plum_1"},
	"c023_plum_3": {"label": "梅烙 · 极", "desc": "K 花域结束时，把域内敌人全部拉回", "max": 1, "icon": "icon_potion", "forms": ["c023"], "path": "梅烙", "tier": 3, "theme": 1, "req": "c023_plum_2"},
	"c023_counter_1": {"label": "回环 · 初", "desc": "K 期间首次近战攻击被收鞭格挡并拉近攻击者", "max": 1, "icon": "icon_medal", "forms": ["c023"], "path": "回环", "tier": 1, "theme": 2},
	"c023_counter_2": {"label": "回环 · 续", "desc": "格挡后与攻击者换位，并获得短暂无敌", "max": 1, "icon": "icon_medal", "forms": ["c023"], "path": "回环", "tier": 2, "theme": 2, "req": "c023_counter_1"},
	"c023_counter_3": {"label": "回环 · 极", "desc": "反制不中断 K，并缚住攻击者 2.5 秒", "max": 1, "icon": "icon_medal", "forms": ["c023"], "path": "回环", "tier": 3, "theme": 2, "req": "c023_counter_2"},
	# ---------- 力僧·定山：搬山 / 钟鸣 / 苦行 ----------
	"c013_mountain_1": {"label": "搬山 · 初", "desc": "击退撞人时双方定身，碰撞即控制", "max": 1, "icon": "icon_sword", "forms": ["c013"], "path": "搬山", "tier": 1, "theme": 0},
	"c013_mountain_2": {"label": "搬山 · 续", "desc": "普攻可以击退被 L 眩晕的目标", "max": 1, "icon": "icon_sword", "forms": ["c013"], "path": "搬山", "tier": 2, "theme": 0, "req": "c013_mountain_1"},
	"c013_mountain_3": {"label": "搬山 · 极", "desc": "击退撞墙时，以落点为中心范围击飞", "max": 1, "icon": "icon_sword", "forms": ["c013"], "path": "搬山", "tier": 3, "theme": 0, "req": "c013_mountain_2"},
	"c013_bell_1": {"label": "钟鸣 · 初", "desc": "金钟罩展开时，把周围敌人拉到身前", "max": 1, "icon": "icon_medal", "forms": ["c013"], "path": "钟鸣", "tier": 1, "theme": 1},
	"c013_bell_2": {"label": "钟鸣 · 续", "desc": "盾中再按 K 主动碎钟，按剩余时间定身周围敌人", "max": 1, "icon": "icon_medal", "forms": ["c013"], "path": "钟鸣", "tier": 2, "theme": 1, "req": "c013_bell_1"},
	"c013_bell_3": {"label": "钟鸣 · 极", "desc": "碎钟留下一次钟壳，挡下攻击并反震敌人", "max": 1, "icon": "icon_medal", "forms": ["c013"], "path": "钟鸣", "tier": 3, "theme": 1, "req": "c013_bell_2"},
	"c013_ascetic_1": {"label": "苦行 · 初", "desc": "受击叠戒印（最多 3），U 砸地每层额外回血", "max": 1, "icon": "icon_potion", "forms": ["c013"], "path": "苦行", "tier": 1, "theme": 2},
	"c013_ascetic_2": {"label": "苦行 · 续", "desc": "戒印回血溢出时，每层转为一次护身盾", "max": 1, "icon": "icon_potion", "forms": ["c013"], "path": "苦行", "tier": 2, "theme": 2, "req": "c013_ascetic_1"},
	"c013_ascetic_3": {"label": "苦行 · 极", "desc": "三戒释放 U 不进入冷却，并同时展开钟鸣", "max": 1, "icon": "icon_potion", "forms": ["c013"], "path": "苦行", "tier": 3, "theme": 2, "req": "c013_ascetic_2"},
	# ---------- 剑仙·洛惊鸿：听锋 / 挑月 / 惊鸿谱 ----------
	"z000_listen_1": {"label": "听锋 · 初", "desc": "完美闪避给攻击者留下 5 秒破绽", "max": 1, "icon": "icon_medal", "forms": ["z000"], "path": "听锋", "tier": 1, "theme": 0},
	"z000_listen_2": {"label": "听锋 · 续", "desc": "近战命中消耗破绽，破招并打断敌人", "max": 1, "icon": "icon_medal", "forms": ["z000"], "path": "听锋", "tier": 2, "theme": 0, "req": "z000_listen_1"},
	"z000_listen_3": {"label": "听锋 · 极", "desc": "破招后回身步，闪避立即冷却且短暂无敌", "max": 1, "icon": "icon_medal", "forms": ["z000"], "path": "听锋", "tier": 3, "theme": 0, "req": "z000_listen_2"},
	"z000_moon_1": {"label": "挑月 · 初", "desc": "U 后 4 秒内可在空中普攻，追身浮空目标", "max": 1, "icon": "icon_arrow_up", "forms": ["z000"], "path": "挑月", "tier": 1, "theme": 1},
	"z000_moon_2": {"label": "挑月 · 续", "desc": "空中普攻命中可续浮空，每次起跳最多两次", "max": 1, "icon": "icon_arrow_up", "forms": ["z000"], "path": "挑月", "tier": 2, "theme": 1, "req": "z000_moon_1"},
	"z000_moon_3": {"label": "挑月 · 极", "desc": "U 对浮空目标改为砸落，落点范围击飞", "max": 1, "icon": "icon_arrow_up", "forms": ["z000"], "path": "挑月", "tier": 3, "theme": 1, "req": "z000_moon_2"},
	"z000_score_1": {"label": "惊鸿谱 · 初", "desc": "K/L/U 各留一种剑诀，命中为敌人留诀", "max": 1, "icon": "icon_sword", "forms": ["z000"], "path": "惊鸿谱", "tier": 1, "theme": 2},
	"z000_score_2": {"label": "惊鸿谱 · 续", "desc": "三诀齐备后普攻第四段归一：拉人并定身", "max": 1, "icon": "icon_sword", "forms": ["z000"], "path": "惊鸿谱", "tier": 2, "theme": 2, "req": "z000_score_1"},
	"z000_score_3": {"label": "惊鸿谱 · 极", "desc": "归一重置最长技能冷却；觉醒中归一免诀，O 先拉带诀敌人", "max": 1, "icon": "icon_sword", "forms": ["z000"], "path": "惊鸿谱", "tier": 3, "theme": 2, "req": "z000_score_2"},
	# ---------- 银夜·将去未还：踏霄 / 漏刻 / 去来 ----------
	"z003_sky_1": {"label": "踏霄 · 初", "desc": "二段挑飞后 4 秒内可空中 J 追身", "max": 1, "icon": "icon_arrow_up", "forms": ["z003"], "path": "踏霄", "tier": 1, "theme": 0},
	"z003_sky_2": {"label": "踏霄 · 续", "desc": "空中第三段改为砸落，落地眩晕周围敌人", "max": 1, "icon": "icon_arrow_up", "forms": ["z003"], "path": "踏霄", "tier": 2, "theme": 0, "req": "z003_sky_1"},
	"z003_sky_3": {"label": "踏霄 · 极", "desc": "砸落让自己反弹，可再接一次挑飞", "max": 1, "icon": "icon_arrow_up", "forms": ["z003"], "path": "踏霄", "tier": 3, "theme": 0, "req": "z003_sky_2"},
	"z003_clock_1": {"label": "漏刻 · 初", "desc": "时停中用不同招式命中，各留一枚时刻（最多 3）", "max": 1, "icon": "icon_undo", "forms": ["z003"], "path": "漏刻", "tier": 1, "theme": 1},
	"z003_clock_2": {"label": "漏刻 · 续", "desc": "时停自然结束，每枚时刻使目标定身 0.6 秒", "max": 1, "icon": "icon_undo", "forms": ["z003"], "path": "漏刻", "tier": 2, "theme": 1, "req": "z003_clock_1"},
	"z003_clock_3": {"label": "漏刻 · 极", "desc": "集齐三刻的目标，时停后余滞减速 4 秒", "max": 1, "icon": "icon_undo", "forms": ["z003"], "path": "漏刻", "tier": 3, "theme": 1, "req": "z003_clock_2"},
	"z003_returning_1": {"label": "去来 · 初", "desc": "O 起手留下 6 秒归痕，并记住路径命中者", "max": 1, "icon": "icon_sword", "forms": ["z003"], "path": "去来", "tier": 1, "theme": 2},
	"z003_returning_2": {"label": "去来 · 续", "desc": "归痕中闪避返程，只叠流血与定身、不伤血", "max": 1, "icon": "icon_sword", "forms": ["z003"], "path": "去来", "tier": 2, "theme": 2, "req": "z003_returning_1"},
	"z003_returning_3": {"label": "去来 · 极", "desc": "交叉命中触发破招；返程命中免除闪避冷却", "max": 1, "icon": "icon_sword", "forms": ["z003"], "path": "去来", "tier": 3, "theme": 2, "req": "z003_returning_2"},
}

## 开局赐福：每局出发前三选一（blessing_panel 弹出），效果只在本局生效
const BLESSINGS := {
	"revive": {"label": "残墨续命", "desc": "阵亡后以 4 点生命原地爬起一次"},
	"reroll": {"label": "灵思泉涌", "desc": "每次强化三选一额外重随 1 次"},
	"hp": {"label": "铁砚护身", "desc": "生命上限 +2"},
	"damage": {"label": "锋墨", "desc": "本局全部伤害 +1"},
	"cooldown": {"label": "清流", "desc": "本局技能冷却 -10%"},
	"dash": {"label": "燕回", "desc": "本局闪避冷却 -15%"},
}

var active := false
var mode := MODE_ADVENTURE # adventure / endless
var difficulty := 1 # 五档问境索引，默认落笔
var depth := 1 # 无尽模式层数（冒险模式恒为 1）
var room_index := 0
var hp := BASE_HP
var max_hp := BASE_HP
var skull_id := "c021"
var upgrades: Dictionary = {}
var blessing := ""
var blessing_used := false # 续命赐福是否已消耗（一局一次）
var blessing_rerolls := 0 # 永久商品提供的每局赐福重随次数
var supply_revive := false # 复活墨符：与续命赐福相互独立
var supply_revive_used := false
var supply_hp := 0 # 生肌散：本局额外生命上限
var max_hp_loss := 0 # 镰意绽花：本局生命上限损失，跨房间保留
var supply_upgrade_rerolls := 0 # 重随券：整局共享的额外强化重随次数
var guard_available := false # 护砚：每局第一次实际受伤减免
var c021_dance_kills := 0 # 血舞·极：跨房间保留的每三杀回血计数
var c021_red_butterfly_used := false # 红蝶：每局首次死亡满血复活，之后持续失去生命
var c013_damage_hits := 0 # 降魔：实际造成伤害的累计次数，每四次凝一层佛陀
var c013_buddha := 0 # 佛陀：跨房间保留，无叠加上限
var c023_ink_bonus := 0 # 墨梅：每次实际伤害积累的额外结算墨锭
var z003_kill_counts: Dictionary = {} # 血色切割：敌人 类型+阶级 -> 本局击败数
var z003_stolen: Dictionary = {} # 血色切割：同一键 -> 被动包与召唤场景，未来 PvP 共用
var z003_madness_hp := 0 # 失心疯：夺取后由命中与受击累积的生命上限修正
var boss_id := "" # 当前 Boss 房登场的 Boss
var boss_queue: Array = [] # 无归冒险为两只不同 Boss；其他情况只有一只
var boss_defeated: Array = [] # 本次 Boss 房已讨伐名录，结算落款用
var boss_phase := 0 # 无归连战当前场次（0/1）
var last_hit := {} # 玩家最后一次实际扣血的攻击者/招式/伤害，结算终局对演用
var meta_snapshot := {} # 开局时的 Meta 快照，结算面板 diff 出本局收获


## 开新一局（开始流程面板选完模式、难度与角色后调用；测试无参 = 冒险 + 落笔 + 双刺）
func start(new_mode := MODE_ADVENTURE, new_skull := "c021", new_difficulty := 1) -> void:
	active = true
	mode = MODE_ENDLESS if new_mode == MODE_ENDLESS else MODE_ADVENTURE
	difficulty = clampi(new_difficulty, 0, DIFFICULTIES.size() - 1)
	depth = 1
	room_index = 0
	skull_id = new_skull if new_skull != "" else "c021"
	upgrades = {}
	blessing = ""
	blessing_used = false
	blessing_rerolls = Meta.shop_level("blessing_reroll")
	supply_revive = false
	supply_revive_used = false
	supply_hp = 0
	supply_upgrade_rerolls = 0
	max_hp_loss = 0
	guard_available = Meta.shop_level("start_guard") > 0
	c021_dance_kills = 0
	c021_red_butterfly_used = false
	c013_damage_hits = 0
	c013_buddha = 0
	c023_ink_bonus = 0
	z003_kill_counts.clear()
	z003_stolen.clear()
	z003_madness_hp = 0
	last_hit = {}
	boss_defeated = []
	boss_phase = 0
	_roll_bosses()
	meta_snapshot = Meta.snapshot() # 结算面板据此展示本局契合/解锁收获
	Score.reset()
	var supply := Meta.consume_selected_supply()
	supply_revive = supply == "supply_revive"
	supply_hp = 2 if supply == "supply_hp" else 0
	if supply == "supply_reroll":
		supply_upgrade_rerolls = 2
	max_hp = calculated_max_hp()
	hp = max_hp


## 化身固有生命与所有局内外上限修正统一走这里；红蝶触发后固定为 100（仍会被削上限）。
func calculated_max_hp() -> int:
	if skull_id == "c021" and c021_red_butterfly_used:
		return maxi(1, 100 - max_hp_loss)
	var form_base := 60 if skull_id == "c023" else BASE_HP
	return maxi(1, form_base + level("hp") + (2 if blessing == "hp" else 0) \
		+ Meta.start_hp_bonus() + Meta.form_hp_bonus(skull_id) + supply_hp - max_hp_loss + z003_madness_hp)


## 血色切割统一入口：敌人死亡提交 export_passives()；化身与未来 PvP 直接提交同构被动包。
## 返回本次新夺取的包；未达阈值或已夺取返回空字典，同类型不同阶级分别计数。
func record_blood_cut(packet: Dictionary, count_defeat := true) -> Dictionary:
	var type_id := str(packet.get("type_id", ""))
	var tier := str(packet.get("tier", "mob"))
	if type_id.is_empty() or (packet.get("passives", []) as Array).is_empty():
		return {}
	var key := "%s:%s" % [type_id, tier]
	if z003_stolen.has(key):
		return {}
	var threshold := 6 if tier == "mob" else (3 if tier == "elite" else 1)
	var count := int(z003_kill_counts.get(key, 0)) + (1 if count_defeat else 0)
	z003_kill_counts[key] = count
	if count < threshold:
		return {}
	var stored := packet.duplicate(true)
	stored["key"] = key
	z003_stolen[key] = stored
	return stored.duplicate(true)


func has_stolen_passive(id: String) -> bool:
	for packet in z003_stolen.values():
		if (packet.get("passives", []) as Array).has(id):
			return true
	return false


func random_stolen_packet() -> Dictionary:
	if z003_stolen.is_empty():
		return {}
	var keys := z003_stolen.keys()
	return (z003_stolen[str(keys[randi() % keys.size()])] as Dictionary).duplicate(true)


func room_config() -> Dictionary:
	if is_boss_room():
		return BOSS_ROOM
	var cfg: Dictionary
	if mode == MODE_ENDLESS:
		cfg = {"waves": endless_waves(room_index)}
	else:
		cfg = ROOMS[clampi(room_index, 0, ROOMS.size() - 1)]
	cfg = cfg.duplicate(true)
	cfg["waves"] = scale_waves(cfg["waves"])
	return cfg


## 数量倍率只作用于普通怪：先从波次总数扣除精英，再把精英原数加回。
func scale_waves(source: Array) -> Array:
	var result := source.duplicate(true)
	var mul := float(DIFFICULTIES[difficulty]["count"])
	for cfg in result:
		var elite := int(cfg.get("elite", 0))
		var normal := maxi(0, int(cfg.get("count", 0)) - elite)
		cfg["count"] = maxi(1, int(round(float(normal) * mul))) + elite
	return result


## 敌方攻击统一入口：普通怪、精英、Boss 近战/冲锋/火区及后续敌投射物均走这里。
func enemy_damage(base: int) -> int:
	return maxi(1, base + int(DIFFICULTIES[difficulty]["attack"]))


func difficulty_label() -> String:
	return str(DIFFICULTIES[difficulty]["label"])


func _roll_bosses() -> void:
	var pool := BossTypes.ROSTER.duplicate()
	pool.shuffle()
	boss_queue = []
	var amount := 2 if mode == MODE_ADVENTURE and difficulty == DIFFICULTIES.size() - 1 else 1
	for i in amount:
		boss_queue.append(str(pool[i]))
	boss_id = str(boss_queue[0])


## 无尽模式第 i 间房的波次（按层数成长）：血量/数量/速度/精英数一起抬，
## 精英血量为「形态表基础血量 × hp_mul」，每层 +30%
func endless_waves(i: int) -> Array:
	var d := depth
	var hp := 2 * (2 + (d - 1) + i)
	var spd := minf(1.55, 1.0 + 0.05 * float(d - 1))
	var total := mini(12, 5 + i + mini(d - 1, 5))
	var elite := int((d - 1) / 2) + (1 if i >= 2 else 0)
	var mul := 1.0 + 0.3 * float(d - 1)
	return [
		{"count": maxi(3, total - 1), "hp": hp, "speed": spd, "elite": maxi(0, elite - 1), "hp_mul": mul},
		{"count": total + 1, "hp": hp + 2, "speed": minf(1.6, spd + 0.05), "elite": elite, "hp_mul": mul},
	]


## 无尽模式 Boss 缩放：血量每层 +40%，出手冷却每层 -6%（最低 0.6 倍 = 出手快 40%）
func boss_hp_scale() -> float:
	return 1.0 + 0.4 * float(depth - 1) if mode == MODE_ENDLESS else 1.0


func boss_cd_scale() -> float:
	return maxf(0.6, 1.0 - 0.06 * float(depth - 1)) if mode == MODE_ENDLESS else 1.0


func room_label() -> String:
	if mode == MODE_ENDLESS:
		return "无尽 · 第 %d 层" % depth
	return str(room_config()["label"])


func room_no() -> String:
	if is_boss_room():
		return "Boss"
	return "%d / %d" % [room_index + 1, ROOMS.size()]


func mode_label() -> String:
	return "无尽" if mode == MODE_ENDLESS else "冒险"


## 三关全过后进入 Boss 房（room_index 越过普通房间数）
func is_boss_room() -> bool:
	return room_index >= ROOMS.size()


func is_last_room() -> bool:
	return room_index >= ROOMS.size() - 1


func advance() -> void:
	room_index += 1
	# 无尽：打完 Boss 进下一层（三小关重来，Boss 换一只，数值更高）
	if mode == MODE_ENDLESS and room_index > ROOMS.size():
		depth += 1
		room_index = 0
		boss_phase = 0
		boss_defeated = []
		_roll_bosses()
	elif room_index > ROOMS.size():
		room_index = ROOMS.size()


## 已完成的普通房间数；无尽每过一层额外计入已完成的 Boss 房。
func cleared_room_count() -> int:
	return maxi(0, depth - 1) * (ROOMS.size() + 1) + clampi(room_index, 0, ROOMS.size())


func level(key: String) -> int:
	return int(upgrades.get(key, 0))



## 卡牌信息查询：通用与形态专属两表合并（面板/购买统一走这里）
func card_info(key: String) -> Dictionary:
	if UPGRADES.has(key):
		return UPGRADES[key]
	return FORM_UPGRADES.get(key, {})


## 卡池轮转：每次三选一保证「一条正在走的流派 · 一条新流派 · 一张通用」，
## 一局的 3 次强化刚好能把一条流派从"初"推到"极"，选择即流派。
func roll_cards(count: int = 3) -> Array:
	var gen: Array = [] # 通用池：还没满级
	for k in UPGRADES:
		if level(k) < int(UPGRADES[k]["max"]):
			gen.append(k)
	var cont: Array = [] # 已开张流派的下一个层级（前置已拥有）
	var fresh: Array = [] # 还没开张的流派第一层
	for k in FORM_UPGRADES:
		var info: Dictionary = FORM_UPGRADES[k]
		if not (info["forms"] as Array).has(skull_id) or level(k) >= int(info["max"]):
			continue
		var req := str(info.get("req", ""))
		if req == "":
			fresh.append(k)
		elif level(req) > 0:
			cont.append(k)
	var picked: Array = []
	_take_random(cont, picked, count)
	_take_random(fresh, picked, count)
	_take_random(gen, picked, count)
	var rest: Array = []
	rest.append_array(fresh)
	rest.append_array(cont)
	rest.append_array(gen)
	rest.shuffle()
	for k in rest:
		if picked.size() >= count:
			break
		if not picked.has(k):
			picked.append(k)
	picked.shuffle()
	return picked


## 从池里随机取一张塞进结果（池空或已取满就跳过）
func _take_random(pool: Array, into: Array, count: int) -> void:
	if pool.is_empty() or into.size() >= count:
		return
	into.append(pool[randi() % pool.size()])


## 免费选择一项通关强化。成功会立刻影响本房间的玩家（room 负责调用 apply_to）
func buy(key: String) -> bool:
	var info: Dictionary = card_info(key)
	if info.is_empty():
		return false
	if level(key) >= int(info["max"]):
		return false
	upgrades[key] = level(key) + 1
	if key == "hp":
		max_hp = calculated_max_hp()
		hp = max_hp # 买了加血就回满，下一层的起始血量一并提高
	return true


## 永久强化重随由每个面板自行重置；重随券的两次额度则整局共享。
func consume_supply_reroll() -> bool:
	if supply_upgrade_rerolls <= 0:
		return false
	supply_upgrade_rerolls -= 1
	return true


## 离开房间前：把玩家当前状态写进 run
func snapshot(player) -> void:
	hp = int(player.hp)
	max_hp = int(player.max_hp)
	skull_id = str(player.skull_id)


## 进入房间后：把 run 状态装回玩家（强化 / 血量 / 形态）
func apply_to(player) -> void:
	# 玩家脚本没编译过时实例是裸 CharacterBody2D，直接跳过避免 Invalid access
	if not player.has_method("set_upgrades"):
		push_error("Run.apply_to: 玩家缺少 set_upgrades（脚本未加载？），状态未装回")
		return
	player.set_upgrades(upgrades)
	if player.skull_id != skull_id:
		player.swap_skull(skull_id)
	max_hp = calculated_max_hp()
	player.max_hp = player.effective_max_hp(max_hp) if player.has_method("effective_max_hp") else max_hp
	var extra_cap: int = player.extra_hp_cap() if player.has_method("extra_hp_cap") else 0
	player.hp = clampi(hp, 1, player.max_hp + extra_cap)
	player.hp_changed.emit(player.hp, player.max_hp)
	if player.has_method("on_room_enter"):
		player.on_room_enter()


## 镰意绽花：只扣本局上限，不造成普通直伤；实际损失写入 Run，换房与后续强化都不会洗掉。
func lose_max_hp(amount: int, player = null) -> int:
	if player != null and is_instance_valid(player) and player.has_method("_saint_immune") and bool(player.call("_saint_immune")):
		return 0
	var actual := mini(maxi(0, amount), maxi(0, max_hp - 1))
	if actual <= 0:
		return 0
	max_hp_loss += actual
	max_hp = maxi(1, max_hp - actual)
	hp = mini(hp, max_hp)
	if player != null and is_instance_valid(player):
		player.max_hp = max_hp
		player.hp = mini(int(player.hp), max_hp)
		hp = int(player.hp)
		player.hp_changed.emit(player.hp, player.max_hp)
	return actual
