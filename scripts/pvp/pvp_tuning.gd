extends RefCounted

## 玩家对战的集中数值配置：pvp_rules（伤害/回合）与 player（治疗/控制/持续伤害）共用。
## 只影响 pvp_mode，PvE 的伤害与状态逻辑完全不读取这里的常数。

const MAX_HP := 140
## PvE 结算值 → PVP 血量。原 8.0 下调到 7.0，延长 TTK，避免两三个技能打完一回合。
const DAMAGE_SCALE := 7.0
## 单次命中伤害上限：高倍率技能也不能一击过半，保证被反打的一方仍有操作空间。
const HIT_DAMAGE_CAP := 26
## 圣僧（镇岳被动）在 PVP 中的单次伤害封顶：140 血体系下沿用 3 点会近乎无敌，取常规上限的约 1/3
const SAINT_HIT_CAP := 8
## 治疗折算：PVP 回血不按 PvE 数值直接回，避免续航型角色无限拉血。
const HEAL_SCALE := 0.6
## 控制时长折算：定身/眩晕/减速统一缩短，避免一套控制链直接定死。
const CONTROL_SCALE := 0.6
const BLEED_SCALE := 0.7
## 易伤/躁动：受伤放大系数
const VULN_SCALE := 1.25
const FRENZY_SCALE := 1.2
## 邪佛压场：自身输出折算
const PRESSURE_SCALE := 0.85
## 时停与 BOSS 档位一致，最高不超过 BOSS 的 5 秒
const TIME_STOP_MAX := 5.0
## 红蝶在 PVP 中每回合首次致死的复活量：按对战生命上限的比例给第二条命
const REVIVE_HP_RATIO := 0.5
## 复活起身保护：这段时间内不再结算伤害，避免刚起身就被同一套连段立刻打死
const REVIVE_GUARD := 1.0
## PvP 受击无敌：PvE 的 0.8 秒会吞掉连段，对战取更短的防重复判定窗口
const HURT_INVINCIBLE := 0.25

const ROUNDS_TO_WIN := 2
const ROUND_INTRO := 1.0
const ROUND_END_DELAY := 1.4
## 玩家受击半径：与 PvE 的敌人半径取同一量级，避免贴脸时明明碰到却判不中
const HURT_RADIUS := 42.0
## 角色系数：默认 1.0；由 pvp_balance_test 量出各角色技能单次伤害后回填微调。
const CHAR_SCALE := {
	"z000": 1.0,
	"z001": 0.8, # 烬生：单段基础值偏高，对战按 0.8 折算，J/K 仍保留压制力
	"z002": 1.0,
	"z003": 1.0,
	"c013": 1.0,
	"c021": 1.0,
	"c023": 1.0,
}
