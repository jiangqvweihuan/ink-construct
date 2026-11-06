extends Node

## 功名录 · 成就系统
##
## 三层数据：
##   stats    —— 跨周目的累计统计（击杀、闪避、墨锭、拾取……），条件达成即解锁
##   run      —— 本局临时统计（受伤、技能次数、开局时刻），用于无伤 / 速通 / 空手这类单局条件
##   unlocked —— 已解锁 id -> 解锁时间戳；称号从已解锁条目里挑一个佩戴
##
## 存档：user://achievements.json。首次读档时用 Meta 的历史数据补种，老存档不会从零开始。
## 实时反馈：解锁时右上角浮出一枚朱砂小印（战斗 / 结算 / 主菜单都可见），1.2 秒后淡出。

const SAVE_PATH := "user://achievements.json"
const SAVE_VER := 1

const CAT_JOURNEY := "行旅"
const CAT_SKILL := "技艺"
const CAT_FORM := "化身"
const CAT_BEAST := "百相"
const CAT_INK := "墨缘"
const CAT_HIDDEN := "秘闻"
const CAT_ORDER := [CAT_JOURNEY, CAT_SKILL, CAT_FORM, CAT_BEAST, CAT_INK, CAT_HIDDEN]

const TIER_NAME := {1: "墨", 2: "朱", 3: "金"}
const TIER_COLOR := {
	1: Color(0.60, 0.58, 0.52),
	2: Color(0.66, 0.20, 0.16),
	3: Color(0.87, 0.70, 0.28),
}

## 敌人 / Boss 名单：百相页逐条收录，refresh_meta() 会用 Meta.seen 补记
const BEASTS := [
	{"id": "c016", "name": "刀客", "boss": false},
	{"id": "c017", "name": "蛮兵", "boss": false},
	{"id": "c035", "name": "刺客", "boss": false},
	{"id": "c018", "name": "双镰", "boss": false},
	{"id": "c037", "name": "青魇剑主", "boss": false},
	{"id": "c012", "name": "青笠剑客", "boss": false},
	{"id": "c009", "name": "墨霆", "boss": true},
	{"id": "c015a1", "name": "焚鼎", "boss": true},
	{"id": "c001", "name": "武车", "boss": true},
	{"id": "c008", "name": "碎岳", "boss": true},
	{"id": "c032", "name": "鸣钟", "boss": true},
]

const FORMS := [
	{"id": "c021", "name": "双刺"},
	{"id": "c013", "name": "力僧"},
	{"id": "c023", "name": "梅剑"},
	{"id": "z000", "name": "剑仙"},
	{"id": "z002", "name": "绛弦"},
	{"id": "z003", "name": "银夜"},
]

## 成就定义。stat 条件用累计统计；没有 stat 的靠游戏流程主动 unlock（spec 写明条件）。
const ACHIEVEMENTS := [
	# ---------- 行旅 ----------
	{"id": "j01", "name": "初入残卷", "desc": "击败第一名敌人", "cat": CAT_JOURNEY, "tier": 1, "ink": 2, "stat": "kills", "target": 1},
	{"id": "j02", "name": "百人斩", "desc": "累计击败 100 名敌人", "cat": CAT_JOURNEY, "tier": 1, "ink": 6, "stat": "kills", "target": 100},
	{"id": "j03", "name": "千人斩", "desc": "累计击败 1000 名敌人", "cat": CAT_JOURNEY, "tier": 2, "ink": 14, "stat": "kills", "target": 1000, "title": "千人斩"},
	{"id": "j04", "name": "万人敌", "desc": "累计击败 10000 名敌人", "cat": CAT_JOURNEY, "tier": 3, "ink": 30, "stat": "kills", "target": 10000, "title": "万人敌"},
	{"id": "j05", "name": "十室不空", "desc": "累计清空 10 个房间", "cat": CAT_JOURNEY, "tier": 1, "ink": 4, "stat": "rooms", "target": 10},
	{"id": "j06", "name": "百室", "desc": "累计清空 100 个房间", "cat": CAT_JOURNEY, "tier": 2, "ink": 14, "stat": "rooms", "target": 100},
	{"id": "j07", "name": "千室", "desc": "累计清空 1000 个房间", "cat": CAT_JOURNEY, "tier": 3, "ink": 24, "stat": "rooms", "target": 1000, "title": "千室"},
	{"id": "j08", "name": "破墨初成", "desc": "首次通关冒险模式", "cat": CAT_JOURNEY, "tier": 1, "ink": 10, "stat": "adventure_clears", "target": 1, "title": "破墨人"},
	{"id": "j09", "name": "十全十美", "desc": "通关冒险模式 10 次", "cat": CAT_JOURNEY, "tier": 2, "ink": 22, "stat": "adventure_clears", "target": 10},
	{"id": "j10", "name": "百炼成钢", "desc": "通关冒险模式 50 次", "cat": CAT_JOURNEY, "tier": 3, "ink": 32, "stat": "adventure_clears", "target": 50, "title": "百炼"},
	{"id": "j11", "name": "初探无尽", "desc": "无尽模式抵达第 3 层", "cat": CAT_JOURNEY, "tier": 1, "ink": 6, "stat": "best_endless", "target": 3},
	{"id": "j12", "name": "十层深渊", "desc": "无尽模式抵达第 10 层", "cat": CAT_JOURNEY, "tier": 2, "ink": 16, "stat": "best_endless", "target": 10, "title": "深入者"},
	{"id": "j13", "name": "二十层", "desc": "无尽模式抵达第 20 层", "cat": CAT_JOURNEY, "tier": 3, "ink": 28, "stat": "best_endless", "target": 20, "title": "深渊客"},
	{"id": "j14", "name": "初遇首领", "desc": "击败第一名首领", "cat": CAT_JOURNEY, "tier": 1, "ink": 6, "stat": "boss_kills", "target": 1},
	{"id": "j15", "name": "十伐", "desc": "累计击败 10 名首领", "cat": CAT_JOURNEY, "tier": 2, "ink": 14, "stat": "boss_kills", "target": 10},
	{"id": "j16", "name": "五十伐", "desc": "累计击败 50 名首领", "cat": CAT_JOURNEY, "tier": 3, "ink": 26, "stat": "boss_kills", "target": 50, "title": "伐木人"},
	{"id": "j17", "name": "启程", "desc": "累计开启 10 局", "cat": CAT_JOURNEY, "tier": 1, "ink": 4, "stat": "runs", "target": 10},
	{"id": "j18", "name": "百局", "desc": "累计开启 100 局", "cat": CAT_JOURNEY, "tier": 2, "ink": 16, "stat": "runs", "target": 100},
	{"id": "j19", "name": "问境 · 惊锋", "desc": "以惊锋难度通关", "cat": CAT_JOURNEY, "tier": 1, "ink": 10, "stat": "best_difficulty", "target": 2},
	{"id": "j20", "name": "问境 · 狂澜", "desc": "以狂澜难度通关", "cat": CAT_JOURNEY, "tier": 2, "ink": 18, "stat": "best_difficulty", "target": 3},
	{"id": "j21", "name": "问境 · 无归", "desc": "以无归难度通关", "cat": CAT_JOURNEY, "tier": 3, "ink": 34, "stat": "best_difficulty", "target": 4, "title": "无归"},
	{"id": "j22", "name": "屡败屡战", "desc": "累计阵亡 10 次", "cat": CAT_JOURNEY, "tier": 1, "ink": 4, "stat": "deaths", "target": 10},

	# ---------- 技艺 ----------
	{"id": "s01", "name": "完美一闪", "desc": "首次完美闪避", "cat": CAT_SKILL, "tier": 1, "ink": 3, "stat": "perfect_dodges", "target": 1},
	{"id": "s02", "name": "闪身百次", "desc": "累计完美闪避 100 次", "cat": CAT_SKILL, "tier": 2, "ink": 12, "stat": "perfect_dodges", "target": 100},
	{"id": "s03", "name": "千钧一发", "desc": "累计完美闪避 1000 次", "cat": CAT_SKILL, "tier": 3, "ink": 22, "stat": "perfect_dodges", "target": 1000, "title": "无影"},
	{"id": "s04", "name": "格开一刀", "desc": "首次招架成功", "cat": CAT_SKILL, "tier": 1, "ink": 4, "stat": "parries", "target": 1},
	{"id": "s05", "name": "百招不落", "desc": "累计招架 100 次", "cat": CAT_SKILL, "tier": 2, "ink": 15, "stat": "parries", "target": 100},
	{"id": "s06", "name": "连击二十", "desc": "单场战斗达到 20 连击", "cat": CAT_SKILL, "tier": 1, "ink": 4, "stat": "max_combo", "target": 20},
	{"id": "s07", "name": "连击五十", "desc": "单场战斗达到 50 连击", "cat": CAT_SKILL, "tier": 2, "ink": 10, "stat": "max_combo", "target": 50},
	{"id": "s08", "name": "连击一百", "desc": "单场战斗达到 100 连击", "cat": CAT_SKILL, "tier": 2, "ink": 18, "stat": "max_combo", "target": 100},
	{"id": "s09", "name": "连击二百", "desc": "单场战斗达到 200 连击", "cat": CAT_SKILL, "tier": 3, "ink": 28, "stat": "max_combo", "target": 200, "title": "不辍笔"},
	{"id": "s10", "name": "一击八伤", "desc": "单次造成 8 点伤害", "cat": CAT_SKILL, "tier": 1, "ink": 5, "stat": "max_hit", "target": 8},
	{"id": "s11", "name": "一击十二伤", "desc": "单次造成 12 点伤害", "cat": CAT_SKILL, "tier": 2, "ink": 12, "stat": "max_hit", "target": 12},
	{"id": "s12", "name": "一击二十伤", "desc": "单次造成 20 点伤害", "cat": CAT_SKILL, "tier": 3, "ink": 25, "stat": "max_hit", "target": 20, "title": "崩山"},
	{"id": "s13", "name": "墨海千伤", "desc": "累计造成 1000 点伤害", "cat": CAT_SKILL, "tier": 1, "ink": 5, "stat": "damage_dealt", "target": 1000},
	{"id": "s14", "name": "万伤", "desc": "累计造成 10000 点伤害", "cat": CAT_SKILL, "tier": 2, "ink": 18, "stat": "damage_dealt", "target": 10000},
	{"id": "s15", "name": "无伤一室", "desc": "无伤清空 1 个房间", "cat": CAT_SKILL, "tier": 1, "ink": 6, "stat": "no_hit_rooms", "target": 1},
	{"id": "s16", "name": "无伤十室", "desc": "累计无伤清空 10 个房间", "cat": CAT_SKILL, "tier": 2, "ink": 16, "stat": "no_hit_rooms", "target": 10},
	{"id": "s17", "name": "无伤五十室", "desc": "累计无伤清空 50 个房间", "cat": CAT_SKILL, "tier": 3, "ink": 28, "stat": "no_hit_rooms", "target": 50, "title": "不染"},
	{"id": "s18", "name": "无伤通关", "desc": "整局未受任何伤害通关", "cat": CAT_SKILL, "tier": 2, "ink": 22, "stat": "no_hit_clears", "target": 1, "title": "雪衣"},
	{"id": "s19", "name": "五次无伤", "desc": "无伤通关 5 次", "cat": CAT_SKILL, "tier": 3, "ink": 30, "stat": "no_hit_clears", "target": 5, "title": "澄怀"},
	{"id": "s20", "name": "绝境求生", "desc": "仅剩 1 点生命通关", "cat": CAT_SKILL, "tier": 2, "ink": 20, "stat": "last_stand_clears", "target": 1, "title": "一线"},
	{"id": "s21", "name": "疾如风", "desc": "4 分钟内通关一局", "cat": CAT_SKILL, "tier": 1, "ink": 8, "stat": "speed_clears", "target": 1},
	{"id": "s22", "name": "十度疾风", "desc": "4 分钟内通关 10 次", "cat": CAT_SKILL, "tier": 2, "ink": 18, "stat": "speed_clears", "target": 10},
	{"id": "s23", "name": "钟罩护体", "desc": "金钟罩抵挡 50 次攻击", "cat": CAT_SKILL, "tier": 1, "ink": 6, "stat": "blocks", "target": 50},
	{"id": "s24", "name": "百钟不破", "desc": "金钟罩抵挡 200 次攻击", "cat": CAT_SKILL, "tier": 2, "ink": 16, "stat": "blocks", "target": 200},
	{"id": "s25", "name": "百技", "desc": "累计施展 100 次技能", "cat": CAT_SKILL, "tier": 1, "ink": 4, "stat": "skills_used", "target": 100},
	{"id": "s26", "name": "千技", "desc": "累计施展 1000 次技能", "cat": CAT_SKILL, "tier": 2, "ink": 12, "stat": "skills_used", "target": 1000},
	{"id": "s27", "name": "五室不染", "desc": "连续 5 个房间未受伤", "cat": CAT_SKILL, "tier": 2, "ink": 14, "stat": "no_hit_streak", "target": 5},
	{"id": "s28", "name": "一线清室", "desc": "仅剩 1 点生命时清空 10 个房间", "cat": CAT_SKILL, "tier": 2, "ink": 14, "stat": "low_hp_rooms", "target": 10},
	{"id": "s29", "name": "精英猎手", "desc": "累计击败 50 名精英", "cat": CAT_SKILL, "tier": 2, "ink": 14, "stat": "elite_kills", "target": 50},
	{"id": "s30", "name": "精英屠夫", "desc": "累计击败 200 名精英", "cat": CAT_SKILL, "tier": 3, "ink": 26, "stat": "elite_kills", "target": 200},

	# ---------- 化身 ----------
	{"id": "f_c021_clear", "name": "双刺 · 初演", "desc": "以双刺通关一局", "cat": CAT_FORM, "tier": 1, "ink": 10, "stat": "clear_c021", "target": 1},
	{"id": "f_c021_kill", "name": "双刺 · 三百", "desc": "以双刺累计击败 300 名敌人", "cat": CAT_FORM, "tier": 2, "ink": 12, "stat": "form_kill_c021", "target": 300},
	{"id": "f_c021_kill2", "name": "双刺 · 千斩", "desc": "以双刺累计击败 1000 名敌人", "cat": CAT_FORM, "tier": 3, "ink": 20, "stat": "form_kill_c021", "target": 1000},
	{"id": "f_c021_mastery", "name": "双刺 · 大成", "desc": "双刺契合度达到 Lv3", "cat": CAT_FORM, "tier": 3, "ink": 18, "stat": "mastery_c021", "target": 3},
	{"id": "f_c013_clear", "name": "力僧 · 初演", "desc": "以力僧通关一局", "cat": CAT_FORM, "tier": 1, "ink": 10, "stat": "clear_c013", "target": 1},
	{"id": "f_c013_kill", "name": "力僧 · 三百", "desc": "以力僧累计击败 300 名敌人", "cat": CAT_FORM, "tier": 2, "ink": 12, "stat": "form_kill_c013", "target": 300},
	{"id": "f_c013_kill2", "name": "力僧 · 千斩", "desc": "以力僧累计击败 1000 名敌人", "cat": CAT_FORM, "tier": 3, "ink": 20, "stat": "form_kill_c013", "target": 1000},
	{"id": "f_c013_mastery", "name": "力僧 · 大成", "desc": "力僧契合度达到 Lv3", "cat": CAT_FORM, "tier": 3, "ink": 18, "stat": "mastery_c013", "target": 3},
	{"id": "f_c023_clear", "name": "梅剑 · 初演", "desc": "以梅剑通关一局", "cat": CAT_FORM, "tier": 1, "ink": 10, "stat": "clear_c023", "target": 1},
	{"id": "f_c023_kill", "name": "梅剑 · 三百", "desc": "以梅剑累计击败 300 名敌人", "cat": CAT_FORM, "tier": 2, "ink": 12, "stat": "form_kill_c023", "target": 300},
	{"id": "f_c023_kill2", "name": "梅剑 · 千斩", "desc": "以梅剑累计击败 1000 名敌人", "cat": CAT_FORM, "tier": 3, "ink": 20, "stat": "form_kill_c023", "target": 1000},
	{"id": "f_c023_mastery", "name": "梅剑 · 大成", "desc": "梅剑契合度达到 Lv3", "cat": CAT_FORM, "tier": 3, "ink": 18, "stat": "mastery_c023", "target": 3},
	{"id": "f_z000_clear", "name": "剑仙 · 初演", "desc": "以剑仙通关一局", "cat": CAT_FORM, "tier": 1, "ink": 10, "stat": "clear_z000", "target": 1},
	{"id": "f_z000_kill", "name": "剑仙 · 三百", "desc": "以剑仙累计击败 300 名敌人", "cat": CAT_FORM, "tier": 2, "ink": 12, "stat": "form_kill_z000", "target": 300},
	{"id": "f_z000_kill2", "name": "剑仙 · 千斩", "desc": "以剑仙累计击败 1000 名敌人", "cat": CAT_FORM, "tier": 3, "ink": 20, "stat": "form_kill_z000", "target": 1000},
	{"id": "f_z000_mastery", "name": "剑仙 · 大成", "desc": "剑仙契合度达到 Lv3", "cat": CAT_FORM, "tier": 3, "ink": 18, "stat": "mastery_z000", "target": 3},
	{"id": "f_z002_clear", "name": "绛弦 · 初演", "desc": "以绛弦通关一局", "cat": CAT_FORM, "tier": 1, "ink": 10, "stat": "clear_z002", "target": 1},
	{"id": "f_z002_kill", "name": "绛弦 · 三百", "desc": "以绛弦累计击败 300 名敌人", "cat": CAT_FORM, "tier": 2, "ink": 12, "stat": "form_kill_z002", "target": 300},
	{"id": "f_z002_kill2", "name": "绛弦 · 千斩", "desc": "以绛弦累计击败 1000 名敌人", "cat": CAT_FORM, "tier": 3, "ink": 20, "stat": "form_kill_z002", "target": 1000},
	{"id": "f_z002_mastery", "name": "绛弦 · 大成", "desc": "绛弦契合度达到 Lv3", "cat": CAT_FORM, "tier": 3, "ink": 18, "stat": "mastery_z002", "target": 3},
	{"id": "f_z003_clear", "name": "银夜 · 初演", "desc": "以银夜通关一局", "cat": CAT_FORM, "tier": 1, "ink": 10, "stat": "clear_z003", "target": 1},
	{"id": "f_z003_kill", "name": "银夜 · 三百", "desc": "以银夜累计击败 300 名敌人", "cat": CAT_FORM, "tier": 2, "ink": 12, "stat": "form_kill_z003", "target": 300},
	{"id": "f_z003_kill2", "name": "银夜 · 千斩", "desc": "以银夜累计击败 1000 名敌人", "cat": CAT_FORM, "tier": 3, "ink": 20, "stat": "form_kill_z003", "target": 1000},
	{"id": "f_z003_mastery", "name": "银夜 · 大成", "desc": "银夜契合度达到 Lv3", "cat": CAT_FORM, "tier": 3, "ink": 18, "stat": "mastery_z003", "target": 3},
	{"id": "f_all", "name": "六相俱全", "desc": "解锁全部六种化身", "cat": CAT_FORM, "tier": 3, "ink": 25, "stat": "forms_unlocked", "target": 6, "title": "六相"},

	# ---------- 百相 ----------
	{"id": "e_c016", "name": "破 · 刀客", "desc": "击败刀客", "cat": CAT_BEAST, "tier": 1, "ink": 3, "stat": "enemy_c016", "target": 1},
	{"id": "e_c017", "name": "破 · 蛮兵", "desc": "击败蛮兵", "cat": CAT_BEAST, "tier": 1, "ink": 3, "stat": "enemy_c017", "target": 1},
	{"id": "e_c035", "name": "破 · 刺客", "desc": "击败刺客", "cat": CAT_BEAST, "tier": 1, "ink": 3, "stat": "enemy_c035", "target": 1},
	{"id": "e_c018", "name": "破 · 双镰", "desc": "击败双镰", "cat": CAT_BEAST, "tier": 1, "ink": 3, "stat": "enemy_c018", "target": 1},
	{"id": "e_c037", "name": "破 · 青魇剑主", "desc": "击败青魇剑主", "cat": CAT_BEAST, "tier": 2, "ink": 8, "stat": "enemy_c037", "target": 1},
	{"id": "e_c012", "name": "破 · 青笠剑客", "desc": "击败青笠剑客", "cat": CAT_BEAST, "tier": 2, "ink": 8, "stat": "enemy_c012", "target": 1},
	{"id": "e_c009", "name": "讨 · 墨霆", "desc": "击败首领墨霆", "cat": CAT_BEAST, "tier": 2, "ink": 12, "stat": "enemy_c009", "target": 1},
	{"id": "e_c015a1", "name": "讨 · 焚鼎", "desc": "击败首领焚鼎", "cat": CAT_BEAST, "tier": 2, "ink": 12, "stat": "enemy_c015a1", "target": 1},
	{"id": "e_c001", "name": "讨 · 武车", "desc": "击败首领武车", "cat": CAT_BEAST, "tier": 2, "ink": 12, "stat": "enemy_c001", "target": 1},
	{"id": "e_c008", "name": "讨 · 碎岳", "desc": "击败首领碎岳", "cat": CAT_BEAST, "tier": 2, "ink": 12, "stat": "enemy_c008", "target": 1},
	{"id": "e_c032", "name": "讨 · 鸣钟", "desc": "击败首领鸣钟", "cat": CAT_BEAST, "tier": 2, "ink": 12, "stat": "enemy_c032", "target": 1},
	{"id": "e_c016_100", "name": "刀客百斩", "desc": "累计击败 100 名刀客", "cat": CAT_BEAST, "tier": 2, "ink": 12, "stat": "enemy_c016", "target": 100},
	{"id": "e_c017_100", "name": "蛮兵百斩", "desc": "累计击败 100 名蛮兵", "cat": CAT_BEAST, "tier": 2, "ink": 12, "stat": "enemy_c017", "target": 100},
	{"id": "e_c018_100", "name": "双镰百斩", "desc": "累计击败 100 名双镰", "cat": CAT_BEAST, "tier": 2, "ink": 12, "stat": "enemy_c018", "target": 100},
	{"id": "e_boss10", "name": "青魇十伐", "desc": "累计击败 10 名青魇剑主", "cat": CAT_BEAST, "tier": 3, "ink": 18, "stat": "enemy_c037", "target": 10},
	{"id": "e_all", "name": "百相入卷", "desc": "收录全部 11 种敌人与首领", "cat": CAT_BEAST, "tier": 3, "ink": 28, "stat": "enemy_all", "target": 11, "title": "百相"},
	{"id": "e_boss_all", "name": "首领全讨", "desc": "五种首领各击败一次", "cat": CAT_BEAST, "tier": 3, "ink": 24, "stat": "boss_types", "target": 5},

	# ---------- 墨缘 ----------
	{"id": "m01", "name": "初拾墨锭", "desc": "累计获得 50 墨锭", "cat": CAT_INK, "tier": 1, "ink": 3, "stat": "ink_earned", "target": 50},
	{"id": "m02", "name": "聚墨五百", "desc": "累计获得 500 墨锭", "cat": CAT_INK, "tier": 2, "ink": 12, "stat": "ink_earned", "target": 500},
	{"id": "m03", "name": "墨海", "desc": "累计获得 3000 墨锭", "cat": CAT_INK, "tier": 3, "ink": 24, "stat": "ink_earned", "target": 3000, "title": "墨海"},
	{"id": "m04", "name": "初耗", "desc": "累计花费 100 墨锭", "cat": CAT_INK, "tier": 1, "ink": 4, "stat": "ink_spent", "target": 100},
	{"id": "m05", "name": "散尽千金", "desc": "累计花费 2000 墨锭", "cat": CAT_INK, "tier": 2, "ink": 16, "stat": "ink_spent", "target": 2000},
	{"id": "m06", "name": "首购", "desc": "在墨锭商栈完成首次购买", "cat": CAT_INK, "tier": 1, "ink": 3, "stat": "buys", "target": 1},
	{"id": "m07", "name": "商户常客", "desc": "累计购买 20 次", "cat": CAT_INK, "tier": 2, "ink": 12, "stat": "buys", "target": 20},
	{"id": "m08", "name": "初点修炼", "desc": "点亮第一个永久修炼节点", "cat": CAT_INK, "tier": 1, "ink": 4, "stat": "form_nodes", "target": 1},
	{"id": "m09", "name": "修炼十阶", "desc": "点亮 10 个永久修炼节点", "cat": CAT_INK, "tier": 2, "ink": 14, "stat": "form_nodes", "target": 10},
	{"id": "m10", "name": "修炼三十", "desc": "点亮 30 个永久修炼节点", "cat": CAT_INK, "tier": 3, "ink": 26, "stat": "form_nodes", "target": 30, "title": "修行者"},
	{"id": "m11", "name": "携带补给", "desc": "在本局使用一次补给", "cat": CAT_INK, "tier": 1, "ink": 4, "stat": "supplies_used", "target": 1},
	{"id": "m12", "name": "行囊常备", "desc": "累计使用 10 次补给", "cat": CAT_INK, "tier": 2, "ink": 12, "stat": "supplies_used", "target": 10},
	{"id": "m13", "name": "拾遗", "desc": "首次拾取关卡中的地面物件", "cat": CAT_INK, "tier": 1, "ink": 3, "stat": "decor_pickups", "target": 1},
	{"id": "m14", "name": "拾遗三十", "desc": "累计拾取 30 件地面物件", "cat": CAT_INK, "tier": 2, "ink": 12, "stat": "decor_pickups", "target": 30},
	{"id": "m15", "name": "拾遗百件", "desc": "累计拾取 100 件地面物件", "cat": CAT_INK, "tier": 3, "ink": 24, "stat": "decor_pickups", "target": 100},
	{"id": "m16", "name": "强化十选", "desc": "累计选择 10 次强化", "cat": CAT_INK, "tier": 1, "ink": 5, "stat": "upgrades_picked", "target": 10},
	{"id": "m17", "name": "强化百选", "desc": "累计选择 100 次强化", "cat": CAT_INK, "tier": 2, "ink": 16, "stat": "upgrades_picked", "target": 100},
	{"id": "m18", "name": "赐福十次", "desc": "累计接受 10 次开局赐福", "cat": CAT_INK, "tier": 2, "ink": 12, "stat": "blessings_picked", "target": 10},
	{"id": "m19", "name": "全数买断", "desc": "买断全部五种化身的解锁", "cat": CAT_INK, "tier": 3, "ink": 26, "stat": "buyouts", "target": 5, "title": "藏家"},
	{"id": "m20", "name": "墨锭满仓", "desc": "一次持有 1000 墨锭", "cat": CAT_INK, "tier": 3, "ink": 20, "stat": "ink_hold", "target": 1000},

	# ---------- 秘闻 ----------
	{"id": "h01", "name": "空手通关", "desc": "不选任何强化通关一局", "cat": CAT_HIDDEN, "tier": 2, "ink": 16, "spec": "整局不选强化并通关"},
	{"id": "h02", "name": "不施一技", "desc": "不施展任何技能通关一局", "cat": CAT_HIDDEN, "tier": 3, "ink": 24, "spec": "整局不按 U / I / O / K / L 通关"},
	{"id": "h03", "name": "三分钟通关", "desc": "3 分钟内结束一局冒险", "cat": CAT_HIDDEN, "tier": 3, "ink": 26, "title": "疾书", "spec": "冒险模式 180 秒内通关"},
	{"id": "h04", "name": "百死不悔", "desc": "累计阵亡 100 次", "cat": CAT_HIDDEN, "tier": 3, "ink": 24, "stat": "deaths", "target": 100},
	{"id": "h05", "name": "一局百杀", "desc": "单局击败 100 名敌人", "cat": CAT_HIDDEN, "tier": 2, "ink": 16, "stat": "best_run_kills", "target": 100},
	{"id": "h06", "name": "一局千伤", "desc": "单局造成 1000 点伤害", "cat": CAT_HIDDEN, "tier": 2, "ink": 16, "stat": "best_run_damage", "target": 1000},
	{"id": "h07", "name": "残卷三十", "desc": "拾取 30 次残卷", "cat": CAT_HIDDEN, "tier": 2, "ink": 12, "stat": "decor_scroll", "target": 30},
	{"id": "h08", "name": "香炉三十", "desc": "触发 30 次香炉", "cat": CAT_HIDDEN, "tier": 2, "ink": 12, "stat": "decor_censer", "target": 30},
	{"id": "h09", "name": "石碑三十", "desc": "触发 30 次石碑", "cat": CAT_HIDDEN, "tier": 2, "ink": 12, "stat": "decor_stele", "target": 30},
	{"id": "h10", "name": "无字碑", "desc": "解锁其余全部成就", "cat": CAT_HIDDEN, "tier": 3, "ink": 50, "title": "无字碑", "spec": "功名录仅余此条空白"},
	{"id": "h11", "name": "九命", "desc": "使用复活墨符 5 次", "cat": CAT_HIDDEN, "tier": 2, "ink": 12, "stat": "revives", "target": 5},
]

const RUN_KEYS := ["kills", "damage_dealt", "skills_used", "perfect_dodges", "parries", "boss_kills", "elite_kills", "blocks"]

## 佩戴称号的属性加成：克制向，部分带轻微代价（负数）。
## 战斗：hp / damage / move_speed / cooldown / dodge_window / dash；
## 局外：ink_gain / shop_discount。百分比用小数表示。
const TITLE_BONUS := {
	"j03": {"damage": 1, "hp": -1},                       # 千人斩：杀伐过甚
	"j04": {"damage": 2, "hp": -1},                       # 万人敌
	"j07": {"ink_gain": 0.08, "move_speed": -0.03},       # 千室：久战成习
	"j08": {"hp": 1},                                     # 破墨人
	"j10": {"hp": 1, "damage": 1, "move_speed": -0.04},   # 百炼
	"j12": {"ink_gain": 0.08},                            # 深入者
	"j13": {"ink_gain": 0.12, "hp": -1},                  # 深渊客
	"j16": {"damage": 1},                                 # 伐木人
	"j21": {"damage": 1, "move_speed": 0.05, "hp": -1},   # 无归
	"s03": {"dodge_window": 0.04},                        # 无影
	"s09": {"damage": 1},                                 # 不辍笔
	"s12": {"damage": 1, "move_speed": -0.04},            # 崩山：力沉步滞
	"s17": {"hp": 1},                                     # 不染
	"s18": {"hp": 1, "damage": -1},                       # 雪衣：守成
	"s19": {"hp": 2, "damage": -1},                       # 澄怀
	"s20": {"hp": 2, "ink_gain": -0.06},                  # 一线：险中求存
	"f_all": {"cooldown": -0.05, "hp": -1},               # 六相：博而不精
	"e_all": {"damage": 1, "ink_gain": 0.05},             # 百相
	"m03": {"ink_gain": 0.12},                            # 墨海
	"m10": {"cooldown": -0.05},                           # 修行者
	"m19": {"shop_discount": -0.10},                      # 藏家
	"h03": {"move_speed": 0.06, "hp": -1},                # 疾书
	"h10": {"hp": 1, "damage": 1, "ink_gain": 0.08},      # 无字碑：终极，无代价
}

const BONUS_NAME := {
	"hp": "生命上限",
	"damage": "伤害",
	"move_speed": "移速",
	"cooldown": "技能冷却",
	"dodge_window": "闪避余韵",
	"dash": "冲刺距离",
	"ink_gain": "墨锭获取",
	"shop_discount": "商铺价格",
}

const BONUS_ORDER := ["hp", "damage", "move_speed", "cooldown", "dodge_window", "dash", "ink_gain", "shop_discount"]

signal unlocked_signal(id: String)

var stats := {}
var run := {}
var unlocked := {}
var equipped := ""
var _by_stat := {}
var _defs := {}
var _session: Array = []
var _silent := false
var _no_hit_streak := 0

# 实时小印章
var _toast_layer: CanvasLayer
var _toast: Control
var _toast_seal: Panel
var _toast_tier: Label
var _toast_name: Label
var _toast_sub: Label
var _queue: Array = []
var _toast_running := false

const TOAST_POS := Vector2(930, 32)
const TOAST_SIZE := Vector2(326, 72)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in ACHIEVEMENTS:
		var id := str(a["id"])
		_defs[id] = a
		var key := str(a.get("stat", ""))
		if key != "":
			if not _by_stat.has(key):
				_by_stat[key] = []
			_by_stat[key].append(id)
	_load()
	_build_toast()
	# 首次补种时连 refresh_meta 一起静默，否则开机会连刷十几枚印章
	var seeding := unlocked.is_empty() and stats.is_empty()
	if seeding:
		_silent = true
		_seed_from_meta()
	refresh_meta()
	if seeding:
		_silent = false


# ---------- 查询 ----------

func defs() -> Array:
	return ACHIEVEMENTS


func get_def(id: String) -> Dictionary:
	return _defs.get(id, {})


func is_unlocked(id: String) -> bool:
	return unlocked.has(id)


func unlocked_count() -> int:
	return unlocked.size()


func total_count() -> int:
	return ACHIEVEMENTS.size()


## [当前, 目标]；无 stat 的特殊成就返回 [0, 1]
func progress(id: String) -> Array:
	var a: Dictionary = _defs.get(id, {})
	if a.is_empty():
		return [0, 1]
	if is_unlocked(id):
		return [1, 1]
	var key := str(a.get("stat", ""))
	if key == "":
		return [0, 1]
	var target := maxi(1, int(a.get("target", 1)))
	var cur := mini(target, int(stats.get(key, 0)))
	return [cur, target]


func category_progress(cat: String) -> Array:
	var done := 0
	var total := 0
	for a in ACHIEVEMENTS:
		if str(a["cat"]) != cat:
			continue
		total += 1
		if is_unlocked(str(a["id"])):
			done += 1
	return [done, total]


## 已解锁的称号：[{id, title}]
func unlocked_titles() -> Array:
	var out: Array = []
	for a in ACHIEVEMENTS:
		var t := str(a.get("title", ""))
		if t != "" and is_unlocked(str(a["id"])):
			out.append({"id": str(a["id"]), "title": t})
	return out


func equip_title(id: String) -> bool:
	var a: Dictionary = _defs.get(id, {})
	if a.is_empty() or str(a.get("title", "")) == "" or not is_unlocked(id):
		return false
	equipped = id
	_save()
	return true


func equipped_title() -> String:
	if equipped == "":
		return ""
	return str(_defs.get(equipped, {}).get("title", ""))


## 当前佩戴称号的某项加成；未佩戴或该称号没有这项时返回 0
func bonus(key: String) -> float:
	if equipped == "":
		return 0.0
	return float(TITLE_BONUS.get(equipped, {}).get(key, 0.0))


func bonus_int(key: String) -> int:
	return int(round(bonus(key)))


## 称号加成文案：「生命上限 +1 · 伤害 -1」
func bonus_text(id: String) -> String:
	var b: Dictionary = TITLE_BONUS.get(id, {})
	if b.is_empty():
		return ""
	var parts: Array = []
	for key in BONUS_ORDER:
		if not b.has(key):
			continue
		var v := float(b[key])
		var label := str(BONUS_NAME.get(key, key))
		var sign_text := "+" if v >= 0.0 else "-"
		if key == "hp" or key == "damage":
			parts.append("%s %s%d" % [label, sign_text, int(round(absf(v)))])
		elif key == "dodge_window":
			parts.append("%s %s%.2f 秒" % [label, sign_text, absf(v)])
		else:
			parts.append("%s %s%d%%" % [label, sign_text, roundi(absf(v) * 100.0)])
	return " · ".join(parts)


func equipped_bonus_text() -> String:
	return bonus_text(equipped) if equipped != "" else ""


# ---------- 记录 ----------

## 累计事件（击杀、闪避、墨锭……）。同一 key 也会同步进本局统计。
func event(key: String, amount := 1) -> void:
	if key.is_empty() or amount == 0:
		return
	_add(key, amount)
	_mirror_run(key, amount)
	_check(key)


## 峰值类统计（最大连击、最深层数……）
func max_event(key: String, value: int) -> void:
	if key.is_empty():
		return
	if value <= int(stats.get(key, 0)):
		return
	stats[key] = value
	_check(key)


func run_event(key: String, amount := 1) -> void:
	_mirror_run(key, amount)


func _add(key: String, amount: int) -> void:
	stats[key] = int(stats.get(key, 0)) + amount


func _mirror_run(key: String, amount: int) -> void:
	if not RUN_KEYS.has(key):
		return
	run[key] = int(run.get(key, 0)) + amount


func _check(key: String) -> void:
	var ids: Array = _by_stat.get(key, [])
	if ids.is_empty():
		return
	for id in ids:
		if unlocked.has(id):
			continue
		var a: Dictionary = _defs[id]
		if int(stats.get(key, 0)) >= int(a.get("target", 1)):
			unlock(id)


func unlock(id: String) -> bool:
	if not _defs.has(id) or unlocked.has(id):
		return false
	unlocked[id] = int(Time.get_unix_time_from_system())
	_session.append(id)
	var a: Dictionary = _defs[id]
	var reward := int(a.get("ink", 0))
	if reward > 0:
		Meta.add_ink(reward)
	_save()
	unlocked_signal.emit(id)
	if not _silent:
		_queue_toast(id)
	# 无字碑：其余条目全部达成后自行点亮
	if id != "h10" and unlocked.size() >= ACHIEVEMENTS.size() - 1:
		unlock("h10")
	return true


# ---------- 本局 ----------

func begin_run() -> void:
	run = {
		"kills": 0, "damage_dealt": 0, "damage_taken": 0,
		"skills_used": 0, "perfect_dodges": 0, "parries": 0,
		"boss_kills": 0, "elite_kills": 0, "blocks": 0,
		"room_damage": 0, "started_ms": Time.get_ticks_msec(),
	}
	_session = []
	_no_hit_streak = 0
	event("runs")


## 受伤：本局与本房各记一笔（受击处调用，amount 为实际扣血）
func hurt_event(amount: int) -> void:
	if amount <= 0:
		return
	run["damage_taken"] = int(run.get("damage_taken", 0)) + amount
	run["room_damage"] = int(run.get("room_damage", 0)) + amount


func room_begin() -> void:
	run["room_damage"] = 0


## 房间清空：无伤 / 残血清房 / 连续无伤都在这里结算
func room_cleared() -> void:
	event("rooms")
	if int(run.get("room_damage", 0)) <= 0:
		event("no_hit_rooms")
		_no_hit_streak += 1
		max_event("no_hit_streak", _no_hit_streak)
	else:
		_no_hit_streak = 0
	if Run.hp <= 1:
		event("low_hp_rooms")
	run["room_damage"] = 0
	_save()


## 结算：通关 / 阵亡都走这里。只在通关时判定单局条件。
func finish_run(cleared: bool) -> void:
	max_event("best_run_kills", int(run.get("kills", 0)))
	max_event("best_run_damage", int(run.get("damage_dealt", 0)))
	max_event("best_endless", Run.depth)
	if not cleared:
		event("deaths")
		_save()
		return
	var secs := (Time.get_ticks_msec() - int(run.get("started_ms", Time.get_ticks_msec()))) / 1000.0
	event("adventure_clears")
	event("clear_" + Run.skull_id)
	max_event("best_difficulty", Run.difficulty)
	if int(run.get("damage_taken", 0)) <= 0:
		event("no_hit_clears")
	if int(run.get("skills_used", 0)) <= 0:
		unlock("h02")
	if Run.upgrades.is_empty():
		unlock("h01")
	if secs <= 180.0:
		unlock("h03")
	if secs <= 240.0:
		event("speed_clears")
	if Run.hp <= 1:
		event("last_stand_clears")
	_save()


func session_unlocks() -> Array:
	return _session.duplicate()


# ---------- 外部埋点 ----------

## 敌人被玩家击败时由敌人脚本调用（Meta 已记过击杀与收录）
func note_enemy_killed(id: String, elite: bool) -> void:
	if elite:
		event("elite_kills")
	if is_boss(id):
		event("boss_kills")
	max_event("max_combo", Score.max_combo)


func is_boss(id: String) -> bool:
	for b in BEASTS:
		if str(b["id"]) == id:
			return bool(b["boss"])
	return false


## Meta 数据变动后同步：收录数、首领种类、解锁形态数
func refresh_meta() -> void:
	var beasts := 0
	var bosses := 0
	for b in BEASTS:
		if Meta.enemy_kills(str(b["id"])) > 0:
			if bool(b["boss"]):
				bosses += 1
			else:
				beasts += 1
	max_event("enemy_all", beasts + bosses)
	max_event("boss_types", bosses)
	var forms := 0
	for f in FORMS:
		if Meta.is_unlocked(str(f["id"])):
			forms += 1
	max_event("forms_unlocked", forms)
	for f in FORMS:
		max_event("mastery_" + str(f["id"]), Meta.mastery_level(str(f["id"])))


func _seed_from_meta() -> void:
	max_event("kills", Meta.kills)
	max_event("adventure_clears", Meta.clears)
	max_event("form_nodes", Meta.form_nodes.size())
	max_event("buys", Meta.purchases.size())
	max_event("ink_hold", Meta.ink)
	for id in Meta.seen:
		max_event("enemy_" + str(id), Meta.enemy_kills(str(id)))
	for id in Meta.mastery:
		max_event("form_kill_" + str(id), Meta.mastery_exp(str(id)))


# ---------- 实时小印章 ----------

func _build_toast() -> void:
	_toast_layer = CanvasLayer.new()
	_toast_layer.layer = 95
	_toast_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_toast_layer)

	_toast = Control.new()
	_toast.position = TOAST_POS
	_toast.size = TOAST_SIZE
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	_toast_layer.add_child(_toast)

	var bg := Panel.new()
	bg.size = TOAST_SIZE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.055, 0.050, 0.045, 0.93)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.87, 0.70, 0.28, 0.42)
	sb.set_corner_radius_all(3)
	bg.add_theme_stylebox_override("panel", sb)
	_toast.add_child(bg)

	var bar := ColorRect.new()
	bar.color = Color(0.66, 0.20, 0.16, 0.9)
	bar.position = Vector2(0, 0)
	bar.size = Vector2(3, TOAST_SIZE.y)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.add_child(bar)

	_toast_seal = Panel.new()
	_toast_seal.position = Vector2(14, 13)
	_toast_seal.size = Vector2(46, 46)
	_toast_seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ssb := StyleBoxFlat.new()
	ssb.bg_color = Color(0.62, 0.18, 0.14, 0.95)
	ssb.set_corner_radius_all(2)
	_toast_seal.add_theme_stylebox_override("panel", ssb)
	_toast.add_child(_toast_seal)

	_toast_tier = Label.new()
	_toast_tier.position = Vector2(0, 0)
	_toast_tier.size = Vector2(46, 46)
	_toast_tier.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_tier.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast_tier.add_theme_font_size_override("font_size", 24)
	_toast_tier.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	_toast_tier.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_seal.add_child(_toast_tier)

	_toast_sub = Label.new()
	_toast_sub.position = Vector2(72, 11)
	_toast_sub.size = Vector2(240, 20)
	_toast_sub.add_theme_font_size_override("font_size", 12)
	_toast_sub.add_theme_color_override("font_color", Color(0.87, 0.70, 0.28))
	_toast_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.add_child(_toast_sub)

	_toast_name = Label.new()
	_toast_name.position = Vector2(72, 32)
	_toast_name.size = Vector2(240, 28)
	_toast_name.add_theme_font_size_override("font_size", 20)
	_toast_name.add_theme_color_override("font_color", Color(0.949, 0.918, 0.847))
	_toast_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.add_child(_toast_name)


func _queue_toast(id: String) -> void:
	_queue.append(id)
	if not _toast_running:
		_toast_running = true
		_run_toasts()


func _run_toasts() -> void:
	while not _queue.is_empty():
		var id := str(_queue.pop_front())
		await _play_toast(id)
	_toast_running = false


func _play_toast(id: String) -> void:
	var a: Dictionary = _defs.get(id, {})
	if a.is_empty() or _toast == null:
		return
	var tier := int(a.get("tier", 1))
	_toast_tier.text = str(TIER_NAME.get(tier, "墨"))
	_toast_sub.text = "功名录 · %s · %s" % [str(a.get("cat", "")), str(TIER_NAME.get(tier, "墨")) + "印"]
	_toast_name.text = str(a.get("name", ""))
	var accent: Color = TIER_COLOR.get(tier, Color(0.7, 0.6, 0.4))
	var seal_style := _toast_seal.get_theme_stylebox("panel") as StyleBoxFlat
	if seal_style != null:
		seal_style.bg_color = Color(accent, 0.95)
	_toast.visible = true
	_toast.modulate.a = 0.0
	_toast.position = TOAST_POS + Vector2(34, 0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_toast, "modulate:a", 1.0, 0.2)
	tw.tween_property(_toast, "position", TOAST_POS, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await tw.finished
	await get_tree().create_timer(1.25, true).timeout
	if not is_instance_valid(_toast):
		return
	var tw2 := create_tween()
	tw2.set_parallel(true)
	tw2.tween_property(_toast, "modulate:a", 0.0, 0.3)
	tw2.tween_property(_toast, "position", TOAST_POS + Vector2(26, 0), 0.3)
	await tw2.finished
	_toast.visible = false


# ---------- 存档 ----------

func _save() -> void:
	if not Meta.persist:
		return # 与 Meta 同步：测试场景关掉落盘，别污染玩家存档
	# 与 Meta 相同的临时文件替换，避免中断留下半份 JSON
	var temp_path := SAVE_PATH + ".tmp"
	var f := FileAccess.open(temp_path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"ver": SAVE_VER, "stats": stats, "unlocked": unlocked, "equipped": equipped,
	}))
	f.close()
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_path), ProjectSettings.globalize_path(SAVE_PATH))
	if err != OK and FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
		err = DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_path), ProjectSettings.globalize_path(SAVE_PATH))
	if err != OK:
		push_error("Achievements: 存档替换失败，错误码 %d" % err)


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return
	var s = data.get("stats", {})
	if typeof(s) == TYPE_DICTIONARY:
		for k in s:
			stats[str(k)] = int(s[k])
	var u = data.get("unlocked", {})
	if typeof(u) == TYPE_DICTIONARY:
		unlocked = u
	equipped = str(data.get("equipped", ""))
	if equipped != "" and not unlocked.has(equipped):
		equipped = ""
