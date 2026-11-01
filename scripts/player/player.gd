class_name Player
extends CharacterBody2D

## 玩家控制器 · 形态数据见 scripts/player/skulls.gd
## 每个形态自带骨架 / 缩放 / 动画名映射 / 普攻段 / 技能表，换头时按 profile 重建 SpineSprite。
## 缩放按"游戏内角色高 128px"反推，换头不会突然变大变小。

const DAMAGE_NUMBER := preload("res://scripts/ui/damage_number.gd")
const Skulls := preload("res://scripts/player/skulls.gd")
const PROJECTILE := preload("res://scripts/systems/projectile.gd") # 远程形态的普攻/技能发投射物
const FX := preload("res://scripts/systems/fx.gd") # 精灵条特效：斩击/化身光柱/受击墨花
const Settings = preload("res://scripts/ui/settings.gd") # 改键后 HUD 键名要读 InputMap
const DMG_COLOR := Color(0.18, 0.36, 0.43) # 石青：玩家受伤数字


## 队列动画提前接管的时长：spine 在结束前一个混合时长（default_mix=0.2）就把下一段混进来，
## root_motion 技能必须在此之前结算位移，否则读到的是被 stand 拉回途中的根骨值（多留一帧余量）
const ROOT_MIX_LEAD := 0.24

## 技能 action -> HUD 按键字母
const KEY_LABELS := {"skill": "K", "skill_sweep": "L", "skill_ult": "U", "skill_i": "I", "skill_o": "O", "skill_p": "P"}

## 技能配置里 hits.at 是动画开始后多少秒判定命中，按逐帧截图标定：
## skill01：0.75s 前冲突刺后起跳隐身（0.75~1.28s 闪现位移+无敌），1.30s 现身一刀，path=沿闪现路径全判。
## skill03：1.0s 平刺一段，2.0s 双手分枪横扫一段（大范围）。
## skill04：举枪过顶连斩，1.2/2.1/3.0s 各一段。
## 锁定时长用动画真实时长（_skill_durations 运行时查表），不用手填。
## 音效命名：audio/sfx/<名字>.wav，_sfx_cache 里缓存后直接播
const SFX_BASE := "res://audio/sfx/"
const SFX_PRECACHE := [
	"weapon_sword",   # 普攻起手（挥剑嗖）
	"voice_sword_hit",# 普攻命中（咔劈肉）
	"voice_skill_cast",# 技能起手通用（嗡）
	"hit_heavy",      # skill01 突刺命中
	"skill_fist",     # skill03 第一段平刺
	"voice_fan_hit",  # skill03 第二段横扫
	"skill_blade",    # skill04 长连段（落叶镖）
	"hit_fist",       # 玩家受伤
	"dash_step",      # 冲刺脚步（踏地）
	"skill_boom",     # 金钟罩上罩（力僧 K 第二段）
	"gold",           # 金钟罩挡下攻击（金属清响）
]

@export var run_speed := 240.0
@export var accel := 2200.0    # 启动加速度（"踩油门"）
@export var brake := 5200.0    # 制动减速度（"松油门 + 刹"，比启动快得多）
@export var turn_accel := 3000.0 # 反向转向加速度（比同方向启动略快）
@export var gravity := 2000.0
@export var max_fall_speed := 900.0
@export var jump_velocity := -640.0
@export var coyote_time := 0.10
@export var jump_buffer := 0.12
@export var dash_speed := 560.0
@export var dash_time := 0.16
@export var dash_cooldown := 0.45
@export var hurt_time := 0.35
@export var max_hp := 8

signal hp_changed(current: int, maximum: int)
signal died
signal skull_changed(id: String)

enum State { IDLE, RUN, JUMP, FALL, DASH, ATTACK, SKILL, HURT, DEAD }
var state: int = State.IDLE
var facing := 1 # 1 朝右，-1 朝左
var hp: int

# ---------- 当前形态（由 Skulls.SKULLS 表注入，换头时整组替换） ----------
var skull_id := Skulls.DEFAULT_ID
var anim_map: Dictionary = {} # idle/run/dash/air/hurt/dead/getup -> Spine 动画名
var attacks: Array = [] # 普攻段表：{anim, lock, hits, damage, range, lunge}
var skill_config: Dictionary = {} # 技能名 -> {action, cooldown, hits...}
var hud_skills: Array = [] # HUD 技能栏顺序（K/L/U 依次）
var base_scale := 0.394 # 骨架缩放，按形态反推

# ---------- 局内强化（Run.upgrades 注入，换房间保留） ----------
var damage_bonus := 0 # 全部伤害 +N
var cooldown_scale := 1.0 # 技能冷却倍率

var _coyote := 0.0
var _jump_buf := 0.0
var _dash_timer := 0.0
var _dash_cd := 0.0
var _attack_idx := -1
var _attack_timer := 0.0
var _attack_queued := false
var _attack_hits: Array = [] # 本段普攻剩余待结算的命中时刻（动画秒），按升序弹出
var _hurt_timer := 0.0
var _hurt_invincible := 0.0 # 受伤后的短暂无敌：被围殴时不会一帧连掉好几血
var _hurt_cast_key := "" # 最近一次实伤的敌人出手编号；只允许同招后续段穿过上述无敌
var _cuts: Array = [] # 刺客割伤：每次镖去独立保存 3/6 秒两次结算，不刷新、不合并
var _cut_casts: Dictionary = {} # 同一次出手至多挂一组割伤
var _bleed_stacks := 0 # 普通流血：与割伤完全分离，每层每秒 1 伤
var _bleed_time := 0.0
var _bleed_acc := 0.0
var _bleed_source: Dictionary = {}
const BLEED_MAX := 5
const BLEED_DUR := 3.0
var _jump_seal := 0.0 # 辟地实伤附加：封跳剩余秒数，不影响闪避与其他动作
var _dash_seal := 0.0 # 旋斩实伤附加：只封 Shift 闪避，不影响移动、跳跃与攻击
# ---------- 通用动作接口（形态表按需开启；未配 = 退回旧行为，新角色照抄这组字段即可） ----------
var _dash_time_base := 0.0 # 闪避时长 = 闪避动画长度（完美闪避判定窗口）
var _dash_speed_base := 0.0 # 闪避位移速度（配合时长控制总距离）
var _hurt_heavy_anim := "" # 重击受击动画（不配 = 用普通 hurt）
var _fall_anim := "" # 倒地动画（不配 = 没有倒地机制）
var _low_idle_anim := "" # 残血待机动画（不配 = 始终普通待机）
var _hurt_heavy_at := 999 # 伤害 ≥ 此值播重击受击
var _knock_at := 999 # 伤害 ≥ 此值直接倒地
var _low_hp_ratio := 0.0 # 血量比例 ≤ 此值切残血待机
var _anim_durations := {} # 通用动画名 -> 真实时长（受击/倒地/起身用）
var _hurt_phase := "" # 倒地阶段："" / "fall" / "getup" / "chain"
var _hurt_getup_dur := 0.0 # 倒地流程里起身段时长（剩余时间跨过它就进入起身无敌）
var _knock_chain: Array = [] # 倒地链（形态表 knock_chain）：重受击逐段接续，最后一段起身（力僧）
var _hurt_chain: Array = [] # 倒地链剩余段：[{anim, dur}]
var _hurt_seg_left := 0.0 # 当前段剩余时间
var _shield_hits := 0 # 金钟罩剩余免伤次数（力僧 K 第二段）
var _shield_time := 0.0 # 金钟罩剩余秒数（到点自动消失）
var _mastery_cd := 1.0 # 契合 Lv1：该形态技能冷却倍率
var _mastery_dmg := 0 # 契合 Lv2：该形态普攻加伤
var body_radius := 30.0 # 受击半径：挨打按"攻击方射程 + 本半径"判定（与小怪/Boss 同一规则）
# ---------- 形态专属强化（Run.upgrades 的卡键注入，换房间随 set_upgrades 重算） ----------
var range_scale := 1.0 # 攻击范围倍率（锋扫/鞭术/震地）
var proj_extra := 0 # 投射物额外齐发数（双发）
var proj_pierce := false # 投射物穿透（剑气·极）
var skill_lifesteal := false # 技能命中回血（血饮）
var poise := false # 技能期间霸体
var _upgrades: Dictionary = {} # 本局已购强化键（换头时按新形态重算流派效果）
var _attack_damage_bonus := 0 # 仅普攻加伤（锋扫/鞭术/震地）
var _proj_damage_bonus := 0 # 剑气加伤
var _proj_speed_scale := 1.0
var _proj_range_scale := 1.0
var _lifesteal_heal := 1 # 血饮每次回血量
var _lifesteal_cd_max := 6.0 # 血饮内置冷却
var _lifesteal_buff := 0 # 血饮·极：回血同时挂的限时加伤
var _damage_reduce := 0 # 受到伤害减免（最低仍吃 1）
var _reflect_bonus := 0 # 定山反弹加伤
var _heal_bonus := 0 # 技能回血加量
var _form_cd_scale := 1.0 # 形态卡片提供的技能冷却倍率
var _skill_cd_mod: Dictionary = {} # 指定技能名 -> 额外冷却倍率
var _skill_damage_mod: Dictionary = {} # 指定技能名 -> 加伤（杀阵·续）
var _skill_hit_refund := 0.0 # 指定技能命中后返还的冷却秒数（杀阵·极）
var _tick_damage_bonus := 0 # 持续段加伤（内劲）
var _tick_interval_scale := 1.0 # 持续段出伤频率倍率
var _tick_range_scale := 1.0 # 持续段范围倍率
var _stop_bonus := 0.0 # 时停时长加成
var _stop_buff_damage := 0 # 时停期间加伤
var _stop_buff_timer := 0.0
var _blink_dist_scale := 1.0 # 位移斩杀距离倍率
var _qg_jump_bonus := 0.0 # 轻功·初：跳跃额外倍率
var _qg_hover_bonus := 0.0 # 轻功·初：悬停额外秒数
var _dash_attack_dmg := 0 # 冲刺终点斩伤害（疾刃）
var _dash_attack_refund := false # 冲刺斩命中即回满冲刺
var _dodge_bonus := 0 # 完美闪避赏伤加成（掠影）
var _dodge_time_bonus := 0.0 # 完美闪避赏伤时长加成
var _dodge_cd_refund := 0.0 # 完美闪避减全部技能冷却（轻功·续/极）
var _dash_time_scale := 1.0 # 冲刺时长倍率（疾影）
var _dash_cd_scale := 1.0 # 冲刺冷却倍率（疾影）
var _skill_poise := false # 当前技能自带的霸体（力僧定山：蓄力期间自身霸体，不依赖强化）
var _skill_reflect := false # 当前技能自带的反伤（力僧定山：技能期间无敌，伤害原样弹回攻击者）
var _skill_ranged_guard := false # 当前技能的远程格挡（梅剑转鞭：技能期间免疫并反弹敌方投射物）
var _skill_tick_acc := 0.0 # 技能持续伤害段的计时累计（每 interval 秒结算一次）
# ---------- 局外永久修炼的运行时状态（配置在 Meta.FORM_NODES） ----------
var _attack_range_scale := 1.0 # 梅剑·鞭势：只放大普攻，不影响技能
var _skill_range_scale := 1.0 # 力僧·震岳：只放大 K
var _blink_bonus_dist := 0.0 # 银夜·无还：O 固定位移增量
var _perm_lifesteal_cd := 0.0 # 双刺·血舞：独立 8 秒回血计时
var _shield_heal_used := false # 力僧·金刚：每房一次护盾回血
var _hurt_guard_timer := 0.0 # 力僧·禅定：受击后的短暂减伤
var _hurt_cd_refund_cd := 0.0 # 梅剑·静守：受击减 K 冷却的内置间隔
var _dash_attack_window := 0.0 # 双刺·无影：闪避后下一普攻的生效窗口
var _attack_dodge_bonus := false # 本段普攻是否已拿到上述加伤
var _final_wave_done := false # 双刺·连刃：末段追加剑气每段普攻至多一次
var _dance_kills := 0 # 双刺·血舞：每三次击杀回血
var _o_kill_window := 0.0 # 银夜·无还：O 命中后的击杀归属窗口
var _skill_cast_id := 0 # 每次技能递增，供投射物识别来源
var _edge_k_hits: Dictionary = {} # 藏锋：本次 K 对每个目标的命中段数
var _k_sealed: Dictionary = {} # 藏锋：三段封脉目标
var _skill_cancel_ready := false # 回锋：L 命中后的闪避取消窗口
var _wind_final := false # 游身：完美闪避后的第四段起手
# ---------- 局内流派机制：只存运行状态，是否解锁统一由 _own(卡键) 判断 ----------
var _feathers := 0 # 冷红绫·绯羽
var _daggers: Array = [] # 归刃：{pos, time}
var _bait: Node2D = null # 影饵：可被敌人暂时代替玩家追踪的残影
var _bait_time := 0.0
var _bait_root := false
var _branch_zones: Array = [] # 白疏影·枝界：{x, radius, time}
var _plum_marks: Dictionary = {} # 梅烙：目标 id -> {target, hits, marked}
var _parry_ready := false # 回环：每次 K 只格挡首次近战
var _bell_shell := false # 定山·碎钟后的一次反震壳
var _precepts := 0 # 苦行戒印
var _openings: Dictionary = {} # 洛惊鸿·破绽：目标 id -> {target, time}
var _air_follow := 0.0 # 挑月 / 踏霄的空中追身窗口
var _air_floats := 0 # 挑月每次起跳的续浮空次数
var _air_slam := false # 银夜空中第三段是否按砸落结算
var _air_combo_reset := false # 砸落反弹后可再接二段挑飞
var _sword_seals: Dictionary = {} # 惊鸿谱自身 K/L/U 三诀
var _seal_targets: Dictionary = {} # 带诀敌人：id -> {target, seals}
var _outbound_hits: Dictionary = {} # 银夜 O 去程命中者，返程交叉判破招
var _return_mark := Vector2.ZERO # 去来归痕
var _return_time := 0.0
var _time_marks: Dictionary = {} # 漏刻：id -> {target, moves}
var _delayed: Array = [] # 轻量延迟动作：{time, kind, pos, target}
# ---------- 剑仙·洛惊鸿专属机制（形态表注入，其他形态全为默认值=关闭） ----------
var _dash_pool: Dictionary = {} # 双闪避：still=站定原地闪 / move=移动中随机段（逐项 anim/time/speed/cd）
var _dash_speed_now := 0.0 # 本次闪避的实际速度（0 = 原地闪避，不产生位移）
var _dash_cd_set := 0.0 # 本次闪避结束后要走的冷却（站定/移动两套不同）
var _jump_seg := false # 形态是否配了分段跳跃动画（jump_start/jump_mid/jump_down/jump_land）
var _awaken_time := 0.0 # 觉醒剩余时间（剑仙 I：从动画播完那一刻才开始计时）
var _awaken_pending := 0.0 # 觉醒待激活时长（I 动画播完时转成 _awaken_time）
var _awaken_stacks := 0 # 剑意层数：觉醒期间每次命中 +1（最多 5），每层全伤 +1
var _skill_damage_total := 0 # 本次技能累计打出的伤害（O 第三段按比例回血）
var _skill_cd_set := 0.0 # 本次技能的原始冷却（P 命中返还按它的比例算）
# ---------- 银夜·将去未还专属机制（形态表注入，其他形态全为默认值=关闭） ----------
var _qg_jump_mul := 1.0 # 轻功：跳跃初速倍率（明显跳得更高）
var _qg_hover := 0.0 # 轻功：跃过顶点后空中滞留时长
var _qg_jump_mul_base := 1.0 # 形态表原始跳跃倍率（流派卡在其上叠加）
var _qg_hover_base := 0.0 # 形态表原始悬停时长
var _hover_left := 0.0 # 本次跳跃剩余悬停时间
var _hover_frozen := false # 悬停期间动画已定格（time_scale=0 冻成漂浮姿态）
var _room_buff_used := false # 银夜 P：本房间的觉醒强化是否已加持（玩家随房间重建 = 天然一房一次）
var _buff_damage := 0 # 觉醒（I）：限时内全伤害 +N
var _buff_timer := 0.0 # 觉醒剩余时间
var _attack_anim := "" # 本段普攻实际抽中的动画（随机池段用）
var _attack_lock := 0.0 # 本段普攻的锁定时长（随机池段 = 抽中动画的真实时长）
var _attack_durations := {} # 普攻动画名 -> 真实时长（随机池段的 lock = 抽中动画的时长）
var _skill_anim := "" # 本次技能实际播放的动画（随机池技能用）
var _skill_speed := 1.0 # 本次技能的动画播放速度倍率（<1 慢放，时刻表按动画时间对齐）
var _dash_anim_speed := 1.0 # dash 动画播放速度倍率（形态表 dash_anim_speed，短动画慢放填满冲刺窗口）
var _skill_teleport := 0.0 # 技能抽到自带位移动画（银夜 O 的 #87）：原地播放，收招瞬间瞬移这段距离
var _skill_root_follow := false # 技能配置 root_motion：节点跟着根骨位移走，收招后真的停在动画终点
var _skill_root_x := 0.0 # root_motion 技能起手时的节点 x（根骨位移量以它为基准）
var _mix_restore := false # 瞬移切换时把默认混合压到 0，渲染侧应用完后下一帧恢复 0.2
var _stop_done := false # 时停（U）本场已触发
var _lifesteal_cd := 0.0 # 饮血内置冷却
var _skill_name := ""
var _skill_timer := 0.0
var _skill_dur := 0.0 # 本次技能动画真实时长
var _skill_hits: Array = [] # 尚未结算的命中段（按 at 升序，逐个弹出）
var _skill_start_x := 0.0 # 技能起手 x，path 命中判定的路径起点
var _skill_cds := {} # 技能名 -> 剩余冷却
var _room_cd_cursed := false # 魔爆：仅当前玩家所在房间有效，重建玩家即自然清除
var _room_cd_uses: Dictionary = {} # 诅咒后各技能已使用次数；下次冷却每次再 +1 秒
var _skill_durations := {} # 技能名 -> 动画真实时长，setup 时缓存
var _invincible := false # 闪现段无敌
var _blink_active := false # 闪现段与敌人的碰撞例外已开启
var _idle_queued := false # stand 已排队在技能后面，切 IDLE 时别重复 set（重开会重开淡化）

var sprite: Node2D # SpineSprite（GDExtension 类，用 ClassDB 创建）
var _anim_state # SpineAnimationState
var _root_bone # SpineBone：骨架根骨，root_motion 技能按它的位移驱动节点位移
var _root_bone_base := 0.0 # 根骨出生 x：结算位移后必须把它拨回这里，否则后续动画会一直带着上一招的位移
var _current_anim := "" # 防同名动画重放（floated 在跳跃顶点重放会抽搐）
var _sfx_player: AudioStreamPlayer
var _sfx_cache: Dictionary = {}


func _ready() -> void:
	add_to_group("player")
	hp = max_hp
	_apply_profile(skull_id)
	_setup_spine()
	_setup_sfx()


## 把形态表里的动画映射 / 普攻段 / 技能表 / HUD 顺序装到实例上
func _apply_profile(id: String) -> void:
	var profile: Dictionary = Skulls.get_profile(id)
	# 局外养成的契合度加成随形态一起装上（Meta 是 autoload，测试场景里也在）
	var mods: Dictionary = Meta.mods(id)
	_mastery_cd = float(mods["cd"])
	_mastery_dmg = int(mods["damage"])
	skull_id = id if Skulls.SKULLS.has(id) else Skulls.DEFAULT_ID
	anim_map = profile["anim"]
	attacks = profile["attacks"]
	skill_config = profile["skills"]
	hud_skills = profile["hud_skills"]
	base_scale = float(profile["scale"])
	body_radius = float(profile.get("body_radius", 30.0)) # 形态表可按体型覆盖（未来大型化身）
	# 轻功（银夜）：没有该配置的形态倍率 1.0、不悬停，手感不受影响
	var qg: Dictionary = profile.get("qinggong", {})
	_qg_jump_mul_base = float(qg.get("jump_mul", 1.0))
	_qg_hover_base = float(qg.get("hover", 0.0))
	_dash_anim_speed = float(profile.get("dash_anim_speed", 1.0)) # 短冲刺动画可慢放（银夜 autorush 只有 0.083s）
	# 双闪避池（剑仙）：站定/移动各一套，不配就走下方通用的单段闪避
	_dash_pool = profile.get("dash_pool", {})
	_jump_seg = anim_map.has("jump_start") # 分段跳跃：起跳/上升/下降/落地四段动画
	_awaken_time = 0.0
	_awaken_pending = 0.0
	_awaken_stacks = 0
	_skill_damage_total = 0
	# 通用动作接口：闪避时长/速度、受击分档、倒地、残血待机（形态表不配就走默认值）
	_dash_time_base = float(profile.get("dash_time", dash_time))
	_dash_speed_base = float(profile.get("dash_speed", dash_speed))
	_hurt_heavy_anim = str(anim_map.get("hurt_heavy", anim_map["hurt"]))
	_fall_anim = str(anim_map.get("fall", ""))
	_low_idle_anim = str(anim_map.get("low_idle", ""))
	_low_hp_ratio = float(profile.get("low_hp_ratio", 0.0))
	var tiers: Dictionary = profile.get("hurt_tiers", {})
	_hurt_heavy_at = int(tiers.get("heavy", 999))
	_knock_at = int(tiers.get("knockdown", 999))
	_hurt_phase = ""
	_hurt_getup_dur = 0.0
	# 倒地链（力僧）：不配就退回"单段 fall → getup"的老流程
	_knock_chain = profile.get("knock_chain", []).duplicate()
	_hurt_chain.clear()
	_hurt_seg_left = 0.0
	_shield_hits = 0
	_shield_time = 0.0
	# 换头后按新形态重算流派强化：旧形态的卡休眠，新形态的卡生效
	_apply_form_mods()


## 局内强化注入：通用卡（伤害/冷却/生命/冲刺/闪避）+ 当前形态的流派卡。换房间时由 Run.apply_to 重新调用
func set_upgrades(up: Dictionary) -> void:
	_upgrades = up.duplicate()
	var cd := int(up.get("cooldown", 0))
	damage_bonus = int(up.get("damage", 0))
	run_speed = 240.0 # 上一房间石碑的"疾风"随换房清掉（原位漂移不跨房）
	cooldown_scale = maxf(0.55, 1.0 - 0.15 * cd)
	max_hp = 8 + int(up.get("hp", 0))
	# 疾影：冲刺时长/距离 +20%，完美闪避判定窗口同步变长；冷却 -10%
	var dash_lv := int(up.get("dash", 0))
	_dash_time_scale = 1.0 + 0.2 * dash_lv
	_dash_cd_scale = maxf(0.6, 1.0 - 0.1 * dash_lv)
	# 掠影：完美闪避收益加档
	var dodge_lv := int(up.get("dodge", 0))
	_dodge_bonus = dodge_lv
	_dodge_time_bonus = 0.2 * dodge_lv
	_apply_form_mods()


## 形态流派强化：只对当前形态生效（换头后旧形态的卡休眠，换回来再生效）。
## 先整组归零，再按已购键逐个装上——换房间/换头都走这里重算，不残留上一形态的加成。
func _apply_form_mods() -> void:
	range_scale = 1.0
	proj_extra = 0
	proj_pierce = false
	skill_lifesteal = false
	poise = false
	_attack_damage_bonus = 0
	_proj_damage_bonus = 0
	_proj_speed_scale = 1.0
	_proj_range_scale = 1.0
	_lifesteal_heal = 1
	_lifesteal_cd_max = 6.0
	_lifesteal_buff = 0
	_damage_reduce = 0
	_reflect_bonus = 0
	_heal_bonus = 0
	_form_cd_scale = 1.0
	_skill_cd_mod.clear()
	_skill_damage_mod.clear()
	_skill_hit_refund = 0.0
	_tick_damage_bonus = 0
	_tick_interval_scale = 1.0
	_tick_range_scale = 1.0
	_stop_bonus = 0.0
	_stop_buff_damage = 0
	_blink_dist_scale = 1.0
	_qg_jump_bonus = 0.0
	_qg_hover_bonus = 0.0
	_dash_attack_dmg = 0
	_dash_attack_refund = false
	_dodge_cd_refund = 0.0
	_attack_range_scale = 1.0
	_skill_range_scale = 1.0
	_blink_bonus_dist = 0.0
	# 永久修炼与局内流派叠加；按当前形态装配，换头后不会串效果。
	match skull_id:
		"c013":
			_reflect_bonus += int(Meta.has_form_node("c013_guard_1"))
			_skill_range_scale = 1.15 if Meta.has_form_node("c013_seismic_1") else 1.0
		"c023":
			_attack_range_scale = 1.15 if Meta.has_form_node("c023_lash_1") else 1.0
		"z003":
			_stop_bonus += 0.25 if Meta.has_form_node("z003_time_1") else 0.0
			if Meta.has_form_node("z003_time_2"):
				_stop_buff_damage = maxi(_stop_buff_damage, 1)
			_blink_bonus_dist = 100.0 if Meta.has_form_node("z003_return_1") else 0.0
	# 轻功：形态表原值 + 流派加成（跳跃更高、悬停更久）
	_qg_jump_mul = _qg_jump_mul_base * (1.0 + _qg_jump_bonus)
	_qg_hover = _qg_hover_base + _qg_hover_bonus


## 当前形态是否拥有某张局内卡。卡键按形态唯一，换头后旧卡自然休眠。
func _own(key: String) -> bool:
	return int(_upgrades.get(key, 0)) > 0


## 流派状态计时。节点本身不另开 Timer，换房/死亡时随玩家实例一起销毁。
func _build_tick(delta: float) -> void:
	_air_follow = maxf(0.0, _air_follow - delta)
	if _return_time > 0.0:
		_return_time = maxf(0.0, _return_time - delta)
		if _return_time <= 0.0:
			_outbound_hits.clear()
	if is_on_floor():
		_air_floats = 0
		_air_combo_reset = false
	for i in range(_daggers.size() - 1, -1, -1):
		_daggers[i]["time"] = float(_daggers[i]["time"]) - delta
		if float(_daggers[i]["time"]) <= 0.0:
			_daggers.remove_at(i)
	for i in range(_branch_zones.size() - 1, -1, -1):
		_branch_zones[i]["time"] = float(_branch_zones[i]["time"]) - delta
		if float(_branch_zones[i]["time"]) <= 0.0:
			_branch_zones.remove_at(i)
	for id in _openings.keys():
		var mark: Dictionary = _openings[id]
		mark["time"] = float(mark["time"]) - delta
		if float(mark["time"]) <= 0.0 or not is_instance_valid(mark["target"]):
			_openings.erase(id)
	for id in _k_sealed.keys():
		if not is_instance_valid(_k_sealed[id]) or int(_k_sealed[id].get("hp")) <= 0:
			_k_sealed.erase(id)
	for id in _plum_marks.keys():
		if not is_instance_valid(_plum_marks[id]["target"]) or int(_plum_marks[id]["target"].get("hp")) <= 0:
			_plum_marks.erase(id)
	for id in _seal_targets.keys():
		if not is_instance_valid(_seal_targets[id]["target"]) or int(_seal_targets[id]["target"].get("hp")) <= 0:
			_seal_targets.erase(id)
	for id in _time_marks.keys():
		if not is_instance_valid(_time_marks[id]["target"]) or int(_time_marks[id]["target"].get("hp")) <= 0:
			_time_marks.erase(id)
	if _bait_time > 0.0:
		_bait_time -= delta
		if _bait_time <= 0.0:
			_expire_bait()
	for zone in _branch_zones:
		for e in get_tree().get_nodes_in_group("enemies"):
			var p := e as Node2D
			if p == null or int(e.get("hp")) <= 0:
				continue
			if absf(p.global_position.x - float(zone["x"])) <= float(zone["radius"]) + _radius_of(p) \
					and absf(p.global_position.y - global_position.y) <= 150.0 and e.has_method("contain"):
				var dur := 0.12 if not e.has_method("stop_tier") or str(e.call("stop_tier")) != "boss" else 0.06
				e.call("contain", dur)


## 影饵只是一段可被敌人索敌的墨影，不是第二个玩家，也不承受伤害。
func _spawn_bait() -> void:
	if is_instance_valid(_bait):
		_expire_bait()
	_bait = Node2D.new()
	_bait.add_to_group("player_decoy")
	_bait.global_position = global_position
	get_tree().current_scene.add_child(_bait)
	FX.spawn(_bait, "vanish", Vector2.ZERO, {"loop": true, "scale": 0.8, "mod": Color(0.45, 0.65, 0.7, 0.55)})
	_bait_time = 1.5
	_bait_root = _own("c021_bait_2")


func _expire_bait() -> void:
	if not is_instance_valid(_bait):
		_bait = null
		_bait_time = 0.0
		return
	if _bait_root:
		for e in get_tree().get_nodes_in_group("enemies"):
			if int(e.get("hp")) > 0 and e.get("_target") == _bait:
				e.call("root", 1.5)
	_bait.queue_free()
	_bait = null
	_bait_time = 0.0
	_bait_root = false


func _setup_sfx() -> void:
	_sfx_player = AudioStreamPlayer.new()
	add_child(_sfx_player)
	for n in SFX_PRECACHE:
		var r := load(SFX_BASE + n + ".wav")
		if r != null:
			_sfx_cache[n] = r
		else:
			push_error("Player SFX not found: " + SFX_BASE + n + ".wav")


func _play_sfx(sfx_name: String) -> void:
	var s = _sfx_cache.get(sfx_name)
	if s != null:
		_sfx_player.stream = s
		_sfx_player.play()


func _setup_spine() -> void:
	var profile: Dictionary = Skulls.get_profile(skull_id)
	var data_path := str(profile["data"])
	var data = load(data_path)
	if data == null or not data.call("is_skeleton_data_loaded"):
		push_error("Player: 骨架数据加载失败 " + data_path)
		return
	# 换头时先把旧骨架拆掉，避免两套骨架同时在场
	if sprite != null and is_instance_valid(sprite):
		sprite.queue_free()
		sprite = null
		_anim_state = null
	sprite = ClassDB.instantiate("SpineSprite")
	add_child(sprite)
	sprite.set("skeleton_data_res", data)
	data.call("set_default_mix", 0.2) # 切换混合 0.1->0.2，收招/起步过渡更柔
	sprite.scale = Vector2(base_scale * facing, base_scale)
	_anim_state = sprite.call("get_animation_state")
	_root_bone = sprite.call("get_skeleton").call("get_root_bone") # root_motion 技能靠它读动画的位移量
	_root_bone_base = float(_root_bone.call("get_x")) if _root_bone != null else 0.0
	# 缓存技能动画真实时长，技能锁定必须按实际时长走（C016 的教训：手填时长收招会抽搐）
	# 随机池技能（银夜 I/O）：池里每个动画都要缓存，时长按抽中的那个走
	_skill_durations.clear()
	_skill_cds.clear()
	for n in skill_config:
		var names: Array = skill_config[n].get("pool", [n])
		for an in names:
			var a = data.call("find_animation", str(an))
			if a != null:
				_skill_durations[str(an)] = a.call("get_duration")
			else:
				push_error("Player: 技能动画不存在 " + str(an))
		_skill_cds[n] = 0.0
	# 普攻随机池（银夜三段）：抽中哪段动画，锁定时长就是哪段的真实时长
	_attack_durations.clear()
	for atk in attacks:
		for an in atk.get("pool", [atk.get("anim", "")]):
			var an_str := str(an)
			if an_str == "" or _attack_durations.has(an_str):
				continue
			var aa = data.call("find_animation", an_str)
			if aa != null:
				_attack_durations[an_str] = aa.call("get_duration")
			else:
				push_error("Player: 普攻动画不存在 " + an_str)
	# 通用动作时长（受击分档 / 倒地 / 起身 / 残血待机）：按实际动画长度锁状态，
	# 手填时长会在短动画上收招早半拍、长动画上卡半拍
	_anim_durations.clear()
	for k in anim_map:
		var an := str(anim_map[k])
		if an == "" or _anim_durations.has(an):
			continue
		var a = data.call("find_animation", an)
		if a != null:
			_anim_durations[an] = a.call("get_duration")
	# 倒地链里的每段也要有真实时长（力僧：重受击 / 浮空重受击 / 倒地 / 起身）
	for n in _knock_chain:
		var cn := str(n)
		if _anim_durations.has(cn):
			continue
		var ca = data.call("find_animation", cn)
		if ca != null:
			_anim_durations[cn] = ca.call("get_duration")
		else:
			push_error("Player: 倒地链动画不存在 " + cn)
	_current_anim = ""
	_play(anim_map["idle"], true)


func _physics_process(delta: float) -> void:
	_build_tick(delta)
	_coyote = maxf(0.0, _coyote - delta)
	_jump_buf = maxf(0.0, _jump_buf - delta)
	_dash_cd = maxf(0.0, _dash_cd - delta)
	_hurt_invincible = maxf(0.0, _hurt_invincible - delta)
	_cut_tick(delta) # 割伤是延迟直扣：不吃受击无敌，也不触发受击硬直或阴影
	_bleed_tick(delta) # 普通流血独立计时，与割伤互不合并且不重复进入 hurt
	_jump_seal = maxf(0.0, _jump_seal - delta)
	_dash_seal = maxf(0.0, _dash_seal - delta)
	_lifesteal_cd = maxf(0.0, _lifesteal_cd - delta) # 饮血内置冷却
	_perm_lifesteal_cd = maxf(0.0, _perm_lifesteal_cd - delta)
	_hurt_guard_timer = maxf(0.0, _hurt_guard_timer - delta)
	_hurt_cd_refund_cd = maxf(0.0, _hurt_cd_refund_cd - delta)
	_dash_attack_window = maxf(0.0, _dash_attack_window - delta)
	_o_kill_window = maxf(0.0, _o_kill_window - delta)
	# 金钟罩（力僧 K 第二段）：8 秒内没挨打就自动散
	if _shield_hits > 0:
		_shield_time = maxf(0.0, _shield_time - delta)
		if _shield_time <= 0.0:
			_shield_hits = 0
			_shield_heal_once()
	_buff_timer = maxf(0.0, _buff_timer - delta) # 觉醒 buff 倒计时
	# 剑仙觉醒：到点清空剑意层数（层数只在觉醒期内有效）
	_awaken_time = maxf(0.0, _awaken_time - delta)
	if _awaken_time <= 0.0:
		_awaken_stacks = 0
	_stop_buff_timer = maxf(0.0, _stop_buff_timer - delta) # 时停加伤倒计时
	var cd_recovery := delta
	if skull_id == "c013" and hp <= 4 and Meta.has_form_node("c013_meditation_3"):
		cd_recovery *= 1.2 # 禅定·极：残血时冷却恢复 +20%
	for n in _skill_cds:
		_skill_cds[n] = maxf(0.0, float(_skill_cds[n]) - cd_recovery)
	if is_on_floor():
		_coyote = coyote_time
	if Input.is_action_just_pressed("jump"):
		_jump_buf = jump_buffer

	match state:
		State.IDLE, State.RUN:
			_ground_move(delta)
		State.JUMP, State.FALL:
			_air_move(delta)
		State.DASH:
			_dash_tick(delta)
		State.ATTACK:
			_attack_tick(delta)
		State.SKILL:
			_skill_tick(delta)
		State.HURT:
			_hurt_tick(delta)
		State.DEAD:
			velocity.x = 0.0

	# 残血待机：待机时按血量比例实时切换（技能/受击/倒地结束后也会自动接管）
	if state == State.IDLE:
		var want_idle := _idle_anim()
		if want_idle != _current_anim:
			_play(want_idle, true)

	if state != State.DASH:
		# 轻功悬停（银夜）：跃过顶点后滞留一小段，期间不落——velocity.y 快归零时触发；
		# 悬停期间把跳跃动画定格成漂浮姿态（动画还在播但人不动，看着才不怪）
		if _hover_left > 0.0 and (state == State.JUMP or state == State.FALL) and velocity.y > -60.0:
			_hover_left -= delta
			velocity.y = 0.0
			_set_hover_freeze(true)
		else:
			velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)
			_set_hover_freeze(false)
	move_and_slide()
	_post_move()


# ---------- 各状态逻辑 ----------

func _ground_move(delta: float) -> void:
	var dir := Input.get_axis("move_left", "move_right")
	if dir != 0.0:
		var target := dir * run_speed
		var acc := accel if signf(velocity.x) == dir else turn_accel # 反向转弯给更大加速度，避免"踩住刹车"的粘滞
		facing = 1 if dir > 0.0 else -1
		_apply_facing()
		velocity.x = move_toward(velocity.x, target, acc * delta)
		_set_state(State.RUN)
	else:
		# 松油门立刻重刹，跟动作游戏的手感走——停下比起步快
		velocity.x = move_toward(velocity.x, 0.0, brake * delta)
		_set_state(State.IDLE)
	_try_jump()
	_try_dash()
	if Input.is_action_just_pressed("attack"):
		_start_attack(0)
	else:
		_try_skill()


func _air_move(delta: float) -> void:
	var dir := Input.get_axis("move_left", "move_right")
	if dir != 0.0:
		facing = 1 if dir > 0.0 else -1
		_apply_facing()
		velocity.x = move_toward(velocity.x, dir * run_speed, accel * 0.7 * delta)
	else:
		# 空中松油门轻微制动，比地面刹得慢（不锁死空中控制）
		velocity.x = move_toward(velocity.x, 0.0, brake * 0.4 * delta)
	if Input.is_action_just_pressed("attack") and _air_follow > 0.0:
		if skull_id == "z000" and (_own("z000_moon_1") or Meta.has_form_node("z000_volley_2")):
			_chase_air_target()
			_start_attack(0)
			return
		if skull_id == "z003" and _own("z003_sky_1"):
			_chase_air_target()
			_start_attack(1 if _air_combo_reset else 2)
			_air_combo_reset = false
			return
	_try_dash()


func _chase_air_target() -> void:
	var best: Node2D = null
	var best_dist := 420.0
	for e in get_tree().get_nodes_in_group("enemies"):
		var p := e as Node2D
		if p == null or int(e.get("hp")) <= 0:
			continue
		var d := global_position.distance_to(p.global_position)
		if d < best_dist and absf(p.global_position.y - global_position.y) <= 260.0:
			best = p
			best_dist = d
	if best != null:
		global_position = best.global_position + Vector2(-facing * 75.0, 0.0)
		velocity = Vector2.ZERO


func _dash_tick(delta: float) -> void:
	_dash_timer -= delta
	velocity = Vector2(facing * _dash_speed_now, 0.0)
	if _dash_timer <= 0.0:
		var cut := _dash_attack() # 疾刃：冲刺收尾斩身前一刀
		_sword_dash_sweep()
		_dash_cd = 0.0 if (cut and _dash_attack_refund) else _dash_cd_set * _dash_cd_scale
		velocity.x = facing * run_speed * 0.5
		_set_state(State.IDLE if is_on_floor() else State.FALL)


## 游身：闪避结束回身扫身后；极阶把浮空者砸落、地面者挑飞，Boss 只受短破招。
func _sword_dash_sweep() -> void:
	if skull_id != "z000" or not Meta.has_form_node("z000_wind_2"):
		return
	var did_hit := false
	for e in get_tree().get_nodes_in_group("enemies"):
		var p := e as Node2D
		if p == null or int(e.get("hp")) <= 0:
			continue
		var dx: float = p.global_position.x - global_position.x
		var behind := dx != 0.0 and (dx > 0.0) != (facing > 0)
		if not behind or absf(dx) > 150.0 + _radius_of(p) or absf(p.global_position.y - global_position.y) > 100.0:
			continue
		p.call("take_damage", 1 + damage_bonus + _mastery_dmg + _buff_now() + _target_damage_bonus(p), global_position.x)
		hit_scored()
		if int(e.get("hp")) > 0 and Meta.has_form_node("z000_wind_3"):
			var boss := p.has_method("stop_tier") and str(p.call("stop_tier")) == "boss"
			var airborne := p.has_method("is_on_floor") and not bool(p.call("is_on_floor"))
			if boss:
				p.call("stun", 0.8)
			elif airborne and p.has_method("slam"):
				p.call("slam")
			else:
				p.call("launch", -facing, 120.0, 430.0)
		FX.spawn(get_tree().current_scene, "slash", p.global_position + Vector2(0, -60), {"scale": 0.5, "flip": facing > 0})
		did_hit = true
	if did_hit:
		_play_sfx("skill_blade")
		Feel.hitstop(0.05)
		Feel.shake(5.0, 0.15)


## 疾刃（双刺流派）：冲刺终点斩身前敌人；返回是否命中（供"命中即回满冲刺"判定）
func _dash_attack() -> bool:
	if _dash_attack_dmg <= 0:
		return false
	var did_hit := false
	for e in get_tree().get_nodes_in_group("enemies"):
		var p := e as Node2D
		if p == null or int(e.get("hp")) <= 0:
			continue
		var dx: float = p.global_position.x - global_position.x
		var dy: float = absf(p.global_position.y - global_position.y)
		var in_front := dx == 0.0 or (dx > 0.0) == (facing > 0)
		if not in_front or absf(dx) > 130.0 + _radius_of(p) or dy > 80.0:
			continue
		p.call("take_damage", _dash_attack_dmg + damage_bonus + _buff_now() + _target_damage_bonus(p), global_position.x)
		hit_scored()
		FX.spawn(get_tree().current_scene, "slash", Vector2((global_position.x + p.global_position.x) * 0.5, global_position.y - 70), {"scale": 0.5, "flip": facing < 0})
		did_hit = true
	if did_hit:
		_play_sfx("hit_heavy")
		Feel.hitstop(0.05)
		Feel.shake(5.0, 0.15)
	return did_hit


func _attack_tick(delta: float) -> void:
	_attack_timer -= delta
	# 攻击期间继续减速 lunge，用比地面略低的制动让前冲带"惯性"感——
	# 原来用 accel=2200 秒刹，位移只有 2-3px，等于没冲；现在用 brake*0.5，
	# 刹得慢一半，lunge 110px 至少能飘 10px 出去再停
	velocity.x = move_toward(velocity.x, 0.0, brake * 0.5 * delta)
	if Input.is_action_just_pressed("attack"):
		_attack_queued = true
	# 到点结算命中（支持一段动画多次命中，如 atk03 双刺）
	var lock: float = _attack_lock # 随机池段没有配置 lock，用起手时解析好的时长
	var t: float = lock - _attack_timer # 动画已进行时间
	while not _attack_hits.is_empty() and t >= _hit_time(_attack_hits[0]):
		_deal_hit(_attack_hits.pop_front())
	# 取消窗口：本段命中全部结算完后、lock 后 30%（atk["cancel"] 可调）允许提前
	# 接下一招 / 移动 / dash——不用干等收招帧，连段手感跟得上输入节奏
	var cancel_from: float = lock * (1.0 - float(attacks[_attack_idx].get("cancel", 0.3)))
	if t >= cancel_from and _attack_hits.is_empty():
		if _attack_queued and _attack_idx < attacks.size() - 1:
			_start_attack(_attack_idx + 1)
			return
		if Input.get_axis("move_left", "move_right") != 0.0:
			_set_state(State.IDLE if is_on_floor() else State.FALL)
			return
		_try_dash()
	if _attack_timer <= 0.0:
		if _attack_queued and _attack_idx < attacks.size() - 1:
			_start_attack(_attack_idx + 1)
		else:
			_set_state(State.IDLE if is_on_floor() else State.FALL)


## 命中段时刻：旧格式直接是秒数，新格式是 {"at": 秒, ...}
func _hit_time(h) -> float:
	return float(h["at"]) if h is Dictionary else float(h)


func _deal_hit(h = null) -> void:
	if _attack_idx < 0 or _attack_idx >= attacks.size():
		return
	var atk: Dictionary = attacks[_attack_idx]
	# 远程形态：发投射物，命中由投射物自己结算（伤害带上局内强化与契合加伤）
	if atk.has("projectile"):
		# 双发（剑仙流派）：额外投射物纵向错开齐发；剑气·初/续 与 御剑·极 在此加伤
		for i in proj_extra + 1:
			_spawn_projectile(atk["projectile"], int(atk["damage"]) + damage_bonus + _mastery_dmg + _proj_damage_bonus + _buff_now(), "voice_sword_hit", i * 26.0)
		return
	# 命中段：旧格式是纯秒数（沿用本段统一 damage/range），
	# 新格式是字典（一段动画里多段不同伤害/范围，如梅剑鞭击后接突刺）
	var spec: Dictionary = h if h is Dictionary else atk
	var dmg := int(spec.get("damage", atk.get("damage", 1))) + damage_bonus + _mastery_dmg + _attack_damage_bonus + _buff_now()
	var final_attack := _attack_idx == attacks.size() - 1
	if final_attack and ((skull_id == "c021" and Meta.has_form_node("c021_combo_1")) \
			or (skull_id == "z003" and Meta.has_form_node("z003_chase_1"))):
		dmg += 1
	if _attack_dodge_bonus:
		dmg += 1 # 无影·初：闪避后的下一次普攻
	var reach := float(spec.get("range", atk.get("range", 100.0))) * range_scale * _attack_range_scale
	var side_any := bool(spec.get("both", atk.get("both", false)))
	var pull := float(spec.get("pull", 0.0)) # 鞭击拉回：命中后把敌人拽到身前这个距离
	if pull > 0.0 and skull_id == "c023" and Meta.has_form_node("c023_lash_2"):
		pull = 120.0
	var did_hit := false
	var pulled := 0 # 已拉回的敌人数，多目标依次错开 34px 免得叠成一坨
	for e in get_tree().get_nodes_in_group("enemies"):
		var p := e as Node2D
		if p == null:
			continue
		# 尸体不结算：怪死了但尸体还在场（dead_min 停留），打上去不该涨连击/触发顿帧
		if int(e.get("hp")) <= 0:
			continue
		var dx: float = p.global_position.x - global_position.x
		var dy: float = absf(p.global_position.y - global_position.y)
		var in_front := dx == 0.0 or (dx > 0.0) == (facing > 0)
		# both = 回身横扫：动画把武器甩到身后，前后两侧都算命中，否则"动画打到却没判上"
		# 射程 + 目标受击半径：体型大的 Boss 在身体边缘就能被够到，不用贴到原点
		if not (in_front or side_any) or absf(dx) > reach + _radius_of(p) or dy > 70.0:
			continue
		# 朱砂斩击打在攻击者与被击者的中点胸口高度：视觉上像"从玩家挥出"（拉回前先取位置）
		var mx := (global_position.x + p.global_position.x) * 0.5
		p.call("take_damage", dmg + _target_damage_bonus(p), global_position.x)
		hit_scored() # 命中一只算一次连击
		_on_build_hit(p, "attack%d" % _attack_idx)
		if skull_id == "z003" and _attack_idx == 1 and _own("z003_sky_1"):
			_air_follow = 4.0
		# 击飞（银夜段2）：敌人往空中挑起，落地硬直；打死的尸体不再挑
		var lc: Dictionary = spec.get("launch", {})
		var silver_slam := skull_id == "z003" and _attack_idx == 2 and not is_on_floor() and _own("z003_sky_2")
		var sword_slam := skull_id == "z000" and _attack_idx == 3 and not is_on_floor() and Meta.has_form_node("z000_volley_3")
		if not lc.is_empty() and int(e.get("hp")) > 0 and not silver_slam and not sword_slam:
			p.call("launch", facing, float(lc.get("vx", 150.0)), float(lc.get("vy", 520.0)))
		# 击退（银夜 L）：往攻击方向轰飞，撞同伴/墙壁产生组合伤害
		var kb: Dictionary = spec.get("knockback", {})
		if not kb.is_empty() and int(e.get("hp")) > 0:
			p.call("knock_back", facing, float(kb.get("force", 620.0)), int(kb.get("impact", 1)))
		# 眩晕（剑仙普攻第三段）：每一段都附短暂眩晕，锁移动也锁出手
		var stun := float(spec.get("stun", 0.0))
		if stun > 0.0 and int(e.get("hp")) > 0 and p.has_method("stun"):
			p.call("stun", stun)
		if pull > 0.0 and int(e.get("hp")) > 0:
			# 只朝玩家方向收，已经贴脸的敌人不往前推
			var want_x := global_position.x + float(facing) * (pull + pulled * 34.0)
			want_x = minf(p.global_position.x, want_x) if facing > 0 else maxf(p.global_position.x, want_x)
			_pull_enemy(p, want_x)
			if skull_id == "c023" and _own("c023_bind_1"):
				for other_e in get_tree().get_nodes_in_group("enemies"):
					var other := other_e as Node2D
					if other == null or other == p or int(other_e.get("hp")) <= 0:
						continue
					if other.global_position.distance_to(p.global_position) <= _radius_of(p) + _radius_of(other) + 45.0:
						p.call("root", 1.2)
						other.call("root", 1.2)
						break
			pulled += 1
		FX.spawn(get_tree().current_scene, "slash", Vector2(mx, global_position.y - 70), {"scale": 0.45, "flip": facing < 0})
		did_hit = true
	if did_hit:
		if final_attack:
			_try_unification()
		_play_sfx(str(spec.get("sfx", "voice_sword_hit")))
		Feel.hitstop(0.045) # 命中一僵，普攻比技能轻
		Feel.shake(4.0, 0.13)
		if final_attack and skull_id == "c021" and Meta.has_form_node("c021_combo_3") and not _final_wave_done:
			_final_wave_done = true
			_combo_finish_wave()


## 连刃·极：末段首次命中追加一次双向范围斩，固定 1 伤。
func _combo_finish_wave() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		var p := e as Node2D
		if p == null or int(e.get("hp")) <= 0:
			continue
		if absf(p.global_position.x - global_position.x) <= 240.0 + _radius_of(p) \
				and absf(p.global_position.y - global_position.y) <= 120.0:
			p.call("take_damage", 1, global_position.x)
			hit_scored()
	FX.spawn(get_tree().current_scene, "slash", global_position + Vector2(0, -70), {"scale": 1.1})


## 目标的受击半径：体型越大挨打面越大；没有该属性的测试替身按 30 兜底
func _radius_of(e) -> float:
	var r = e.get("body_radius")
	return float(r) if r != null else 30.0


## 目标状态加伤：毒梅看中毒，逐影看击飞；投射物命中时也会查询同一入口。
func _target_damage_bonus(p: Node2D) -> int:
	var bonus := 0
	if skull_id == "c023" and Meta.has_form_node("c023_venom_2"):
		var poison_left = p.get("_poison_time")
		if poison_left != null and float(poison_left) > 0.0:
			bonus += 1
	if skull_id == "z003" and Meta.has_form_node("z003_chase_2"):
		var enemy_state = p.get("state")
		if enemy_state != null and int(enemy_state) == 6: # c016.State.FLY
			bonus += 1
	return bonus


## 限时加伤：觉醒、完美闪避、血饮与时停共用"取最高"；条件修炼与首房强化另行叠加。
func _buff_now() -> int:
	var v := _buff_damage if _buff_timer > 0.0 else 0
	if _stop_buff_timer > 0.0:
		v = maxi(v, _stop_buff_damage)
	var total := v + _awaken_stacks
	if skull_id == "c021":
		if Meta.has_form_node("c021_combo_2") and Score.combo >= 10:
			total += 1
		if Meta.has_form_node("c021_shadow_3") and not is_on_floor():
			total += 1
	if Meta.shop_level("start_edge") > 0 and Run.room_index == 0 and Run.depth == 1:
		total += 1 # 初锋：每局首个普通房全部伤害 +1
	return total


## 命中计数：连击数 +（剑仙觉醒期间）剑意叠层。玩家造成的每次命中都走这里
func hit_scored() -> void:
	Score.add_hit()
	if _awaken_time > 0.0 and _awaken_stacks < 5:
		_awaken_stacks += 1


## 把敌人直接牵到指定横坐标；所有"拉回/牵引"共用同一个视觉与站位规则。
func _pull_enemy(p: Node2D, want_x: float) -> void:
	if int(p.get("hp")) <= 0:
		return
	var super_armor = p.get("_super_armor")
	if super_armor != null and bool(super_armor):
		return
	var boss := p.has_method("stop_tier") and str(p.call("stop_tier")) == "boss"
	if boss:
		p.call("stun", 0.6) # Boss 不被强制搬运，牵引转换为短破招
	else:
		p.global_position.x = want_x
	FX.spawn(get_tree().current_scene, "slash", p.global_position + Vector2(0, -60), {"scale": 0.35})


## 击退撞人 / 撞墙后的搬山联动。
func on_knock_collision(victim: Node2D, other: Node2D) -> void:
	if skull_id != "c013" or not _own("c013_mountain_1"):
		return
	if int(victim.get("hp")) > 0:
		victim.call("root", 1.5)
	if is_instance_valid(other) and int(other.get("hp")) > 0:
		other.call("root", 1.5)


func on_knock_wall(_victim: Node2D, pos: Vector2) -> void:
	if skull_id == "c013" and _own("c013_mountain_3"):
		_slam_aoe(pos)


## 被砸落敌人的落地回报：银夜本人借反作用力再起，洛惊鸿只结算落点冲击。
func on_enemy_slammed(p: Node2D, pos: Vector2) -> void:
	_slam_aoe(pos, skull_id == "z003", p)
	if skull_id == "z003" and _air_slam:
		_air_slam = false
		if _own("z003_sky_3"):
			velocity.y = -520.0
			state = State.JUMP
			_air_follow = 4.0
			_air_combo_reset = true


## 砸落的落点效果。Boss 不被普通击飞，改为短硬直；已落地者不再被自己的冲击二次击飞。
func _slam_aoe(pos: Vector2, stun_only := false, exclude: Node2D = null) -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		var p := e as Node2D
		if p == null or p == exclude or int(e.get("hp")) <= 0:
			continue
		if absf(p.global_position.x - pos.x) > 180.0 + _radius_of(p) or absf(p.global_position.y - pos.y) > 150.0:
			continue
		var boss := e.has_method("stop_tier") and str(e.call("stop_tier")) == "boss"
		if stun_only or boss:
			p.call("stun", 1.5 if not boss else 0.8)
		else:
			p.call("launch", 1 if p.global_position.x >= pos.x else -1, 130.0, 430.0)
	FX.spawn(get_tree().current_scene, "ink_hit", pos + Vector2(0, -40), {"scale": 1.0})
	Feel.shake(7.0, 0.2)


## 每次近战/技能命中后的流派钩子：标记、回收、破招与空中派生都从这里进入。
func _on_build_hit(p: Node2D, move_id: String) -> void:
	if int(p.get("hp")) <= 0:
		return
	var id := p.get_instance_id()
	if skull_id == "c021":
		if move_id == "skill01" and _own("c021_feather_1") and p.has_method("consume_bleed"):
			var layers := int(p.call("consume_bleed"))
			if layers > 0:
				_feathers = mini(3, _feathers + layers)
				var dn := DAMAGE_NUMBER.new()
				dn.setup("绯羽 %d/3" % _feathers, Color(0.9, 0.55, 0.55))
				dn.global_position = global_position + Vector2(0, -150)
				get_tree().current_scene.add_child(dn)
	elif skull_id == "c023":
		var poison_left = p.get("_poison_time")
		if move_id.begins_with("attack") and _own("c023_plum_1") and poison_left != null and float(poison_left) > 0.0:
			var mark: Dictionary = _plum_marks.get(id, {"target": p, "hits": 0, "marked": false})
			mark["hits"] = mini(2, int(mark["hits"]) + 1)
			mark["marked"] = int(mark["hits"]) >= 2
			_plum_marks[id] = mark
		if move_id == "skill02" and _own("c023_plum_2") and bool(_plum_marks.get(id, {}).get("marked", false)):
			_plum_marks.erase(id)
			p.call("root", 2.0)
			for e in get_tree().get_nodes_in_group("enemies"):
				var other := e as Node2D
				if other != null and other != p and int(e.get("hp")) > 0 and other.global_position.distance_to(p.global_position) <= 280.0:
					other.call("apply_poison", 4.0)
	elif skull_id == "c013":
		if move_id.begins_with("attack") and _own("c013_mountain_2"):
			var stun_left = p.get("_stun_timer")
			if stun_left != null and float(stun_left) > 0.0:
				p.call("knock_back", facing, 480.0, 1)
	elif skull_id == "z000":
		if move_id == "atk04" and Meta.has_form_node("z000_edge_1"):
			_pull_enemy(p, global_position.x + facing * 105.0)
			if Meta.has_form_node("z000_edge_2"):
				_edge_k_hits[id] = int(_edge_k_hits.get(id, 0)) + 1
				if int(_edge_k_hits[id]) >= 3 and not _k_sealed.has(id):
					_k_sealed[id] = p
					p.call("stun", 1.5) # 封招：三段打全立即断招，并留下一次 L 引爆机会
					var dn := DAMAGE_NUMBER.new()
					dn.setup("封脉", Color(0.85, 0.72, 0.42))
					dn.global_position = p.global_position + Vector2(0, -140)
					get_tree().current_scene.add_child(dn)
		if move_id == "skill02-" and _k_sealed.has(id):
			_k_sealed.erase(id)
			p.call("stun", 1.2)
			if Meta.has_form_node("z000_edge_3"):
				for e in get_tree().get_nodes_in_group("enemies"):
					var other := e as Node2D
					if other == null or other == p or int(e.get("hp")) <= 0:
						continue
					if other.global_position.distance_to(p.global_position) <= 280.0:
						var side := 1.0 if other.global_position.x >= p.global_position.x else -1.0
						_pull_enemy(other, p.global_position.x + side * 55.0)
						other.call("root", 0.8)
			FX.spawn(get_tree().current_scene, "ink_hit", p.global_position + Vector2(0, -60), {"scale": 0.7})
		if _own("z000_listen_2") and _openings.has(id):
			_openings.erase(id)
			p.call("stun", 1.5)
			if _own("z000_listen_3"):
				global_position.x -= facing * 90.0
				_dash_cd = 0.0
				_hurt_invincible = maxf(_hurt_invincible, 0.45)
		if state == State.SKILL and _own("z000_score_1"):
			var action := str(skill_config.get(_skill_name, {}).get("action", ""))
			var seal: String = {"skill": "K", "skill_sweep": "L", "skill_ult": "U"}.get(action, "")
			if seal != "":
				var entry: Dictionary = _seal_targets.get(id, {"target": p, "seals": {}})
				(entry["seals"] as Dictionary)[seal] = true
				_seal_targets[id] = entry
		var final_slam := move_id == "attack3" and not is_on_floor() and Meta.has_form_node("z000_volley_3")
		if final_slam:
			var boss := p.has_method("stop_tier") and str(p.call("stop_tier")) == "boss"
			if boss:
				p.call("stun", 0.8)
				_slam_aoe(p.global_position, true)
			elif p.has_method("slam"):
				p.call("slam")
		elif move_id.begins_with("attack") and not is_on_floor() and _own("z000_moon_2") and _air_floats < 2:
			_air_floats += 1
			velocity.y = -300.0
			p.call("launch", facing, 80.0, 260.0)
	elif skull_id == "z003":
		var stopped = p.get("_stop_timer")
		if _own("z003_clock_1") and stopped != null and float(stopped) > 0.0:
			var entry: Dictionary = _time_marks.get(id, {"target": p, "moves": []})
			if not (entry["moves"] as Array).has(move_id) and (entry["moves"] as Array).size() < 3:
				(entry["moves"] as Array).append(move_id)
			_time_marks[id] = entry
		if move_id == "skill11" and _own("z003_returning_1"):
			_outbound_hits[id] = true
		if move_id == "attack2" and not is_on_floor() and _own("z003_sky_2"):
			velocity.y = 820.0
			_air_slam = true
			var boss := p.has_method("stop_tier") and str(p.call("stop_tier")) == "boss"
			if boss:
				p.call("stun", 0.8)
				_slam_aoe(p.global_position, true)
				_air_slam = false
				if _own("z003_sky_3"):
					velocity.y = -520.0
					state = State.JUMP
					_air_follow = 4.0
					_air_combo_reset = true
			elif p.has_method("slam"):
				p.call("slam")


## 惊鸿谱·归一：三诀齐备，或觉醒中的极阶免诀归一。
func _try_unification() -> void:
	if skull_id != "z000" or not _own("z000_score_2"):
		return
	var awaken_free := _awaken_time > 0.0 and _own("z000_score_3")
	var ready := _sword_seals.has("K") and _sword_seals.has("L") and _sword_seals.has("U")
	if not ready and not awaken_free:
		return
	for e in get_tree().get_nodes_in_group("enemies"):
		var p := e as Node2D
		if p == null or int(e.get("hp")) <= 0:
			continue
		if absf(p.global_position.x - global_position.x) <= 420.0 + _radius_of(p) \
				and absf(p.global_position.y - global_position.y) <= 150.0:
			_pull_enemy(p, global_position.x + facing * 95.0)
			p.call("root", 2.0)
	if _own("z000_score_3"):
		var longest := ""
		for n in _skill_cds:
			if longest == "" or float(_skill_cds[n]) > float(_skill_cds[longest]):
				longest = str(n)
		if longest != "":
			_skill_cds[longest] = 0.0
	if not awaken_free:
		_sword_seals.clear()
	var dn := DAMAGE_NUMBER.new()
	dn.setup("归一", Color(0.9, 0.75, 0.3))
	dn.global_position = global_position + Vector2(0, -160)
	get_tree().current_scene.add_child(dn)


func _skill_tick(delta: float) -> void:
	_skill_timer -= delta
	if _mix_restore:
		# 上一帧的瞬移切换已经随渲染应用完毕，恢复默认混合（下一帧物理 tick 时渲染侧必然已跑过）
		_mix_restore = false
		sprite.get("skeleton_data_res").call("set_default_mix", 0.2)
	var cfg: Dictionary = skill_config[_skill_name]
	if _skill_cancel_ready and _dash_cd <= 0.0 and Input.is_action_just_pressed("dash"):
		_skill_cancel_ready = false
		_skill_hits.clear()
		_skill_poise = false
		_skill_reflect = false
		_skill_ranged_guard = false
		_invincible = false
		_set_blink(false)
		_try_dash()
		if state == State.DASH:
			return
	var t: float = (_skill_dur - _skill_timer) * _skill_speed # 动画时间：慢放技能的时刻表按动画帧标定，与 cfg 的 at/blink 对齐
	# 根骨跟随（root_motion）：动画把根骨挪了多远，节点就跟着挪多远，再用 sprite 反向抵消同一份量——
	# 画面看到的动作与原来一模一样，但人物真的走到了动画终点（命中判定 / 投射物出手点也都在正确位置）
	if _skill_root_follow and _root_bone != null:
		var off := _root_offset()
		sprite.position.x = -off
		global_position.x = _skill_root_x + off
	# root_motion 收尾：队列里的 stand 会在结束前一个混合时长（默认 0.2s）就接管轨道、把根骨往 0 拉，
	# 所以必须赶在混合开始前结算位移（再多留一帧余量），然后零混合瞬切 stand——人物正好停在动画终点
	if _skill_root_follow and t >= _skill_dur * _skill_speed - ROOT_MIX_LEAD:
		_reset_root_follow()
		if _anim_state != null:
			var idle_anim := _idle_anim()
			var data = sprite.get("skeleton_data_res")
			data.call("set_default_mix", 0.0)
			_anim_state.call("clear_track", 0) # 连队列里排的 stand 一起清，防止它在旧位置自动接续
			_anim_state.call("set_animation", idle_anim, true, 0)
			_mix_restore = true
			_current_anim = idle_anim
			_idle_queued = true
	# 自带位移动画（#87）尾声提前 0.12s 收尾：瞬移到终点 + 清轨道瞬时切 stand。
	# 不能等收招帧才切——队列里自动接续的 stand 会在旧位置抢先起播、混出一帧残影（残影根因）；
	# 提前切，缝在动画还在播时合上，path 命中仍在收招帧从终点回扫整段路径
	if _skill_teleport > 0.0 and t >= _skill_dur * _skill_speed - 0.12:
		global_position.x += facing * _skill_teleport
		_skill_teleport = 0.0
		if _anim_state != null:
			# 全程零混合做手术：clear_track 自身也会按默认混合把旧轨道淡出（旧姿势带 600px
			# 位移量，淡出去就是残余虚影）——压到 0 再切，渲染侧应用后由 _mix_restore 恢复
			var data = sprite.get("skeleton_data_res")
			data.call("set_default_mix", 0.0)
			_anim_state.call("clear_track", 0) # 连队列里排的 stand 一起清，防止它在旧位置自动接续
			_anim_state.call("set_animation", anim_map["idle"], true, 0)
			_mix_restore = true
			_current_anim = anim_map["idle"]
			_idle_queued = true # _set_state 走"stand 已就位"分支，别再重开淡化
	# 位移三分支：自带位移动画（#87）原地播放等收招瞬移；普通闪现段高速前冲+穿身；其余减速
	if _skill_teleport > 0.0:
		_set_blink(true) # 原地期间同样开穿身：动画画面在冲，站位不动不该被敌人挤住
		velocity.x = move_toward(velocity.x, 0.0, accel * delta)
	elif _skill_root_follow:
		# 位置直接由根骨驱动。这里不碰 blink：blink 同时等于"整段无敌"，U 不该白送无敌
		velocity.x = 0.0
	elif cfg.has("blink_from") and t >= cfg["blink_from"] and t <= cfg["blink_to"]:
		_set_blink(true)
		var blink_window := maxf(0.01, float(cfg["blink_to"]) - float(cfg["blink_from"]))
		var bonus_speed := _blink_bonus_dist / blink_window # 无还·初：固定 +100px，不再随技能速度缩放
		velocity.x = facing * (float(cfg["blink_speed"]) * _blink_dist_scale + bonus_speed)
	else:
		_set_blink(false)
		velocity.x = move_toward(velocity.x, 0.0, accel * delta)
	# 无敌：闪现/原地段全程 + 配置 invincible（银夜 O 冲刺整段无敌）
	_invincible = _blink_active or bool(cfg.get("invincible", false))
	# 到点结算命中段
	while not _skill_hits.is_empty() and t >= _skill_hits[0]["at"]:
		var h: Dictionary = _skill_hits.pop_front()
		_deal_skill_hit(h)
	# 持续伤害段（梅剑·转鞭）：from~to 期间每隔 interval 秒结算一次，前后方范围内所有敌人
	var tick: Dictionary = cfg.get("tick", {})
	if not tick.is_empty() and t >= float(tick["from"]) and t <= float(tick.get("to", _skill_dur)):
		_skill_tick_acc += delta
		var iv := float(tick.get("interval", 0.5)) * _tick_interval_scale # 内劲·续：出鞭更快
		while _skill_tick_acc >= iv:
			_skill_tick_acc -= iv
			_deal_skill_tick(tick)
	# 时间暂停（银夜 U）：到点定住全场敌人，杂兵/精英/Boss 分档时长，无视霸体打断前摇
	var stop: Dictionary = cfg.get("stop", {})
	if not stop.is_empty() and not _stop_done and t >= float(stop.get("at", 0.5)):
		_stop_done = true
		var stop_dur := float(stop.get("mob", 2.0)) + _stop_bonus # 时停·初：全档位 +1 秒
		for e in get_tree().get_nodes_in_group("enemies"):
			if int(e.get("hp")) <= 0:
				continue
			var tier := str(e.call("stop_tier")) if e.has_method("stop_tier") else "mob"
			e.call("time_stop", float(stop.get(tier, 2.0)) + _stop_bonus)
		# 时停·续：定住的这段时间里全伤害 +2（独立槽，_buff_now 取最高）
		if _stop_buff_damage > 0:
			_stop_buff_timer = maxf(_stop_buff_timer, stop_dur)
	# 银夜 I 严格跟随 skill10 轨道：不预排 stand，动画完成的同一帧立即收招，避免终帧后仍锁操作。
	var silver_awaken_done := false
	if skull_id == "z003" and _skill_name == "skill10" and _anim_state != null:
		var entry = _anim_state.call("get_current", 0)
		if entry != null:
			var animation = entry.call("get_animation")
			silver_awaken_done = animation != null and str(animation.call("get_name")) == _skill_anim and bool(entry.call("is_complete"))
	# 其他技能按真实时长退出（它们预排了 stand，current 会被循环待机污染）；银夜 I 额外接受轨道完成信号。
	if _skill_timer <= 0.0 or silver_awaken_done:
		# 自带位移动画兜底：正常尾声已提前 0.12s 瞬移+切 stand（见上），这里只兜底位置
		if _skill_teleport > 0.0:
			global_position.x += facing * _skill_teleport
			_skill_teleport = 0.0
		# 收招兜底：命中段 at 略晚于动画时长时（力僧定山 at=3.12 > 3.05），
		# 靠计时器驱动永远触发不到 t>=at，整段伤害会凭空丢失——退出这一帧补结算
		while not _skill_hits.is_empty():
			_deal_skill_hit(_skill_hits.pop_front())
		_invincible = false
		_skill_poise = false
		_skill_reflect = false
		_skill_ranged_guard = false
		_skill_tick_acc = 0.0
		_set_blink(false)
		# 觉醒（剑仙 I）：动画播完这一刻才开始计时，觉醒窗口内 O/P 才解锁
		if _awaken_pending > 0.0:
			_awaken_time = _awaken_pending
			_awaken_pending = 0.0
			_awaken_stacks = 0
		if skull_id == "c023" and _skill_name == "skill02" and _own("c023_plum_3"):
			for e in get_tree().get_nodes_in_group("enemies"):
				var p := e as Node2D
				if p != null and int(e.get("hp")) > 0 and absf(p.global_position.x - global_position.x) <= 520.0 + _radius_of(p) \
						and absf(p.global_position.y - global_position.y) <= 170.0:
					_pull_enemy(p, global_position.x + facing * 100.0)
		if skull_id == "z000" and _skill_name == "skill04":
			if _own("z000_moon_1"):
				_air_follow = 4.0
			elif Meta.has_form_node("z000_volley_2"):
				_air_follow = 2.0
		_skill_cancel_ready = false
		_parry_ready = false
		_set_state(State.IDLE if is_on_floor() else State.FALL)


func _set_blink(on: bool) -> void:
	if on == _blink_active:
		return
	_blink_active = on
	for e in get_tree().get_nodes_in_group("enemies"):
		if on:
			add_collision_exception_with(e)
		else:
			remove_collision_exception_with(e)


## 根骨当前把人物推开了多少世界像素（骨架空间位移 × 缩放 × 朝向）
func _root_offset() -> float:
	if _root_bone == null:
		return 0.0
	return (float(_root_bone.call("get_world_x")) - _root_bone_base) * base_scale * facing


## 收掉根骨跟随：先把当下的位移量结算进节点位置，再把根骨拨回出生位置、清掉 sprite 补偿——
## 节点挪了 +off、根骨退了 -off、补偿清 0，画面不动，但骨架姿势回到正常基准。
## 只清补偿不回拨根骨的话，人偶会被永远画在节点左侧 off 处（实测 stand 不会自己把根骨拉回 0）。
func _reset_root_follow() -> void:
	if not _skill_root_follow:
		return
	_skill_root_follow = false
	var off := _root_offset()
	if _root_bone != null:
		global_position.x = _skill_root_x + off
		_root_bone.call("set_x", _root_bone_base)
	if sprite:
		sprite.position = Vector2.ZERO


func _deal_skill_hit(h: Dictionary) -> void:
	var low_hp_skill := skull_id == "c021" and Meta.has_form_node("c021_dance_2") and hp * 2 <= max_hp
	# 远程技能：发投射物，命中由投射物自己结算
	if h.has("projectile"):
		var shot_damage := int(h["damage"]) + damage_bonus + _proj_damage_bonus + _buff_now() + int(low_hp_skill)
		var shot_spec: Dictionary = (h["projectile"] as Dictionary).duplicate(true)
		if skull_id == "c021" and _skill_name == "skill02-cankao" and _own("c021_feather_2") and _feathers > 0:
			shot_spec["split"] = int(shot_spec.get("split", 0)) + _feathers
			_feathers = 0
		for i in proj_extra + 1:
			_spawn_projectile(shot_spec, shot_damage, str(h.get("sfx", "")), i * 26.0)
		return
	# 免伤护罩段（力僧 K 第二段）：不打伤害，给自己挂金钟罩
	if h.has("self_shield"):
		_apply_self_shield(h["self_shield"])
	# 纯回血段（力僧定山砸地）：不打伤害，只结算回血与砸地音
	if not h.has("damage"):
		_apply_skill_heal(h)
		return
	var did_hit := false
	var dmg := int(h["damage"]) + damage_bonus + _buff_now() + int(_skill_damage_mod.get(_skill_name, 0)) + int(low_hp_skill)
	if skull_id == "c023" and _skill_name == "skill02" and Meta.has_form_node("c023_lash_3"):
		dmg += 1 # 鞭势·极：只加强 K 的尾鞭，持续段不受影响
	# 觉醒强化（银夜 P）：释放即加持本房间全伤 +N，与是否命中无关；一房一次，再放只剩伤害
	var rb: Dictionary = h.get("room_buff", {})
	if not rb.is_empty() and not _room_buff_used:
		_room_buff_used = true
		damage_bonus += int(rb.get("damage", 0))
		var bn := DAMAGE_NUMBER.new()
		bn.setup("觉醒·全伤+%d" % int(rb.get("damage", 0)), Color(0.9, 0.75, 0.3)) # 金字提示
		bn.global_position = global_position + Vector2(0, -160)
		get_tree().current_scene.add_child(bn)
	var full := bool(h.get("full_screen", false)) # 全屏伤害（银夜 P 觉醒）：无视距离/朝向/高度
	var skill_range := float(h.get("range", 0.0)) * range_scale
	if skull_id == "c013" and _skill_name == "skill01":
		skill_range *= _skill_range_scale # 震岳·初：只放大 K
	for e in get_tree().get_nodes_in_group("enemies"):
		var p := e as Node2D
		if p == null:
			continue
		# 尸体不结算：怪死了但尸体还在场（dead_min 停留），打上去不该涨连击/触发顿帧
		if int(e.get("hp")) <= 0:
			continue
		var dx: float = p.global_position.x - global_position.x
		var dy: float = absf(p.global_position.y - global_position.y)
		var hit_ok := full
		if not hit_ok and dy <= h["height"]:
			if h.get("path", false):
				# 路径判定：闪现扫过的整条线段 + 落点正前方 range
				var x0: float = minf(_skill_start_x, global_position.x) - 20.0
				var x1: float = maxf(_skill_start_x, global_position.x) + 20.0
				var in_path: bool = p.global_position.x >= x0 and p.global_position.x <= x1
				var ahead := dx == 0.0 or (dx > 0.0) == (facing > 0)
				hit_ok = in_path or (ahead and absf(dx) <= skill_range + _radius_of(p))
			else:
				var in_front := dx == 0.0 or (dx > 0.0) == (facing > 0)
				# both = 回身横扫（力僧狼牙棒、双刺回身刺）：动画扫到身后也照样判定
				hit_ok = (in_front or bool(h.get("both", false))) and absf(dx) <= skill_range + _radius_of(p)
		if hit_ok:
			if skull_id == "z003" and _skill_name == "skill11" and Meta.has_form_node("z003_return_3") and _buff_timer > 0.0:
				_o_kill_window = 0.3 # 必须在扣血前开窗口，直接击杀也会归给本次 O
			var hit_damage := dmg + _target_damage_bonus(p)
			p.call("take_damage", hit_damage, global_position.x)
			_skill_damage_total += hit_damage
			hit_scored()
			_apply_hit_bleed(p, h)
			_apply_hit_poison(p, h)
			_skill_kinetic(p, h)
			_apply_hit_control(p, h)
			_on_build_hit(p, _skill_name)
			if skull_id == "c023" and _skill_name == "skill02" and _own("c023_bind_2") and int(e.get("hp")) > 0:
				_pull_enemy(p, global_position.x + facing * 110.0)
			var mx := (global_position.x + p.global_position.x) * 0.5
			FX.spawn(get_tree().current_scene, "slash", Vector2(mx, global_position.y - 70), {"scale": 0.55, "flip": facing < 0})
			did_hit = true
	if did_hit:
		if skull_id == "z000" and _skill_name == "skill02-" and Meta.has_form_node("z000_volley_1"):
			_skill_cancel_ready = true
		if skull_id == "c023" and _skill_name == "skill02" and _own("c023_bind_3"):
			_branch_zones.append({"x": global_position.x, "radius": 260.0, "time": 5.0})
			FX.spawn(get_tree().current_scene, "telegraph", global_position, {"scale": 1.4, "mod": Color(0.5, 0.8, 0.55, 0.7)})
		if skull_id == "c021" and _skill_name == "skill5-" and _own("c021_bait_3") and _bait_time > 0.0 and is_instance_valid(_bait):
			var left := minf(global_position.x, _bait.global_position.x) - 35.0
			var right := maxf(global_position.x, _bait.global_position.x) + 35.0
			for e in get_tree().get_nodes_in_group("enemies"):
				var p := e as Node2D
				if p != null and int(e.get("hp")) > 0 and p.global_position.x >= left and p.global_position.x <= right \
						and absf(p.global_position.y - global_position.y) <= 120.0:
					p.call("apply_bleed", 1)
		if h.has("sfx"):
			_play_sfx(h["sfx"])
		_skill_hit_sustain()
		# 杀阵·极：O 命中返还冷却秒数
		if _skill_hit_refund > 0.0 and _skill_cds.has(_skill_name):
			_skill_cds[_skill_name] = maxf(0.0, float(_skill_cds[_skill_name]) - _skill_hit_refund)
		# 剑仙 P：命中返还本次技能冷却的一定比例（形象上是"踢中就能再来一次"）
		var refund_ratio := float(skill_config[_skill_name].get("refund_ratio", 0.0))
		if refund_ratio > 0.0 and _skill_cds.has(_skill_name):
			_skill_cds[_skill_name] = maxf(0.0, float(_skill_cds[_skill_name]) - _skill_cd_set * refund_ratio)
		Feel.hitstop(0.06) # 技能命中：比普攻更重的顿帧与震屏
		Feel.shake(7.0, 0.2)
	_apply_skill_heal(h)


## 技能命中的续航：局内血饮与永久血舞各自拥有独立冷却，近段和剑气命中共用。
func _skill_hit_sustain() -> void:
	if skill_lifesteal and _lifesteal_cd <= 0.0:
		_lifesteal_cd = _lifesteal_cd_max
		_restore_hp(_lifesteal_heal)
		if _lifesteal_buff > 0:
			_buff_damage = maxi(_buff_damage, _lifesteal_buff)
			_buff_timer = maxf(_buff_timer, 4.0)
	if skull_id == "c021" and Meta.has_form_node("c021_dance_1") and _perm_lifesteal_cd <= 0.0:
		_perm_lifesteal_cd = 8.0
		_restore_hp(1)


func _restore_hp(amount: int) -> void:
	if state == State.DEAD or hp >= max_hp:
		return
	var heal := mini(amount, max_hp - hp)
	hp += heal
	hp_changed.emit(hp, max_hp)
	_spawn_number(heal, Color(0.45, 0.75, 0.5), 130.0)


## 投射物统一回报：连击与技能回血；具体流派派生由各自的命中回调处理。
func on_projectile_hit(_p: Node2D, from_skill: bool, _cast_id: int) -> void:
	hit_scored()
	if from_skill:
		_skill_hit_sustain()


## 双刺掷匕命中：落匕与分裂匕的牵引都依赖真实命中点。
func on_dagger_hit(p: Node2D, pos: Vector2, from_split := false) -> void:
	if skull_id != "c021":
		return
	if _own("c021_return_1"):
		_leave_dagger(pos)
	if from_split and _own("c021_feather_3") and int(p.get("hp")) > 0:
		p.call("root", 1.2)
		for e in get_tree().get_nodes_in_group("enemies"):
			var other := e as Node2D
			if other == null or other == p or int(e.get("hp")) <= 0:
				continue
			if other.global_position.distance_to(p.global_position) <= 240.0:
				_pull_enemy(other, p.global_position.x + signf(other.global_position.x - p.global_position.x) * 45.0)
				other.call("root", 0.8)


func on_projectile_expire(pos: Vector2, style: String) -> void:
	if skull_id == "c021" and style == "dagger" and _own("c021_return_1"):
		_leave_dagger(pos)


func _leave_dagger(pos: Vector2) -> void:
	if _daggers.size() >= 6:
		_daggers.pop_front()
	_daggers.append({"pos": pos, "time": 8.0})
	FX.spawn(get_tree().current_scene, "ink_hit", pos, {"scale": 0.25})


func _recall_daggers() -> void:
	if _daggers.is_empty():
		return
	var nearest: Vector2 = _daggers[0]["pos"]
	for dagger in _daggers:
		var pos: Vector2 = dagger["pos"]
		if absf(pos.x - global_position.x) < absf(nearest.x - global_position.x):
			nearest = pos
	if _own("c021_return_3"):
		var targets: Array = []
		for dagger in _daggers:
			var pos: Vector2 = dagger["pos"]
			for e in get_tree().get_nodes_in_group("enemies"):
				var p := e as Node2D
				if p != null and int(e.get("hp")) > 0 and not targets.has(p) \
						and absf(p.global_position.x - pos.x) <= 150.0 + _radius_of(p):
					targets.append(p)
		if targets.size() == 1:
			_pull_enemy(targets[0], nearest.x)
			targets[0].call("root", 2.5)
		elif targets.size() >= 2:
			var mid: float = (targets[0].global_position.x + targets[1].global_position.x) * 0.5
			_pull_enemy(targets[0], mid - 20.0)
			_pull_enemy(targets[1], mid + 20.0)
			targets[0].call("stun", 1.2)
			targets[1].call("stun", 1.2)
			for i in range(2, targets.size()):
				targets[i].call("root", 1.2)
	global_position.x = nearest.x
	_daggers.clear()
	FX.spawn(get_tree().current_scene, "pillar", global_position, {"scale": 0.35})


## 敌人死亡回报由 c016（Boss 继承）发出；永久效果只归属于当前化身。
func on_enemy_killed(_enemy: Node2D) -> void:
	if skull_id == "c021" and Meta.has_form_node("c021_dance_3"):
		Run.c021_dance_kills = (Run.c021_dance_kills + 1) % 3
		if Run.c021_dance_kills == 0:
			_restore_hp(1)
	if skull_id != "z003":
		return
	if Meta.has_form_node("z003_chase_3"):
		for n in _skill_cds:
			_skill_cds[n] = maxf(0.0, float(_skill_cds[n]) - 1.0)
	if _o_kill_window > 0.0 and _buff_timer > 0.0 and Meta.has_form_node("z003_return_3"):
		_buff_timer += 4.0
		_o_kill_window = 0.0


## 毒梅·极：毒死时向附近最近的两名敌人传毒，避免连锁即死、只传播状态。
func on_poison_kill(victim: Node2D) -> void:
	if skull_id != "c023" or not Meta.has_form_node("c023_venom_3"):
		return
	var candidates: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		var p := e as Node2D
		if p == null or p == victim or int(e.get("hp")) <= 0:
			continue
		if victim.global_position.distance_to(p.global_position) <= 320.0:
			candidates.append(p)
	candidates.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return victim.global_position.distance_squared_to(a.global_position) < victim.global_position.distance_squared_to(b.global_position))
	for i in mini(2, candidates.size()):
		candidates[i].call("apply_poison", 5.0)


## 止时·极：只响应自然计时结束；死亡、击飞等提前解除不会触发。
func on_time_stop_end(p: Node2D) -> void:
	if skull_id != "z003":
		return
	var id := p.get_instance_id()
	if int(p.get("hp")) > 0 and _own("z003_clock_2") and _time_marks.has(id):
		var count := (_time_marks[id]["moves"] as Array).size()
		p.call("root", 0.6 * count)
		if count >= 3 and _own("z003_clock_3") and p.has_method("slow"):
			p.call("slow", 4.0, 0.45)
	_time_marks.erase(id)
	if Meta.has_form_node("z003_time_3") and int(p.get("hp")) > 0:
		p.call("take_damage", 1, global_position.x)
		hit_scored()


## 技能命中的位移效果（与普攻 _deal_hit 同规则）：launch=击飞挑空，knockback=击退轰飞；打死的尸体不动
func _skill_kinetic(p: Node2D, h: Dictionary) -> void:
	if int(p.get("hp")) <= 0:
		return
	var airborne := int(p.get("state")) == 6 or (p.has_method("is_on_floor") and not bool(p.call("is_on_floor")))
	if skull_id == "z000" and _skill_name == "skill04" and _own("z000_moon_3") and airborne:
		var boss := p.has_method("stop_tier") and str(p.call("stop_tier")) == "boss"
		if boss:
			p.call("stun", 0.8)
			_slam_aoe(p.global_position, true)
		elif p.has_method("slam"):
			p.call("slam")
		return
	var lc: Dictionary = h.get("launch", {})
	if not lc.is_empty():
		# ignore_armor（剑仙 U 飞脚）：规则级击飞，连 Boss 的霸体也能挑起来
		p.call("launch", facing, float(lc.get("vx", 150.0)), float(lc.get("vy", 520.0)), bool(lc.get("ignore_armor", false)))
	var kb: Dictionary = h.get("knockback", {})
	var seismic_impact := skull_id == "c013" and _skill_name == "skill03" and Meta.has_form_node("c013_seismic_3")
	if not kb.is_empty():
		# ignore_armor（剑仙 O 横斩）：霸体也照样轰飞；力僧 L 的永久撞人不无视霸体
		var impact := int(kb.get("impact", 1)) + int(seismic_impact)
		p.call("knock_back", facing, float(kb.get("force", 620.0)), impact, bool(kb.get("ignore_armor", false)))
	elif seismic_impact:
		p.call("knock_back", facing, 620.0, 2) # 原本只有晕眩的 L 获得撞人，碰撞伤害 1→2


## 技能命中附加控制（敌人侧接口）：
## root=定身秒数（力僧 K：轰飞后钉在落点，只锁移动、照常出手）
## stun=晕眩秒数（力僧 L：锁移动也锁出手，立即打断正在起的招）
func _apply_hit_control(p: Node2D, h: Dictionary) -> void:
	if int(p.get("hp")) <= 0:
		return
	var stun := float(h.get("stun", 0.0))
	if stun > 0.0 and p.has_method("stun"):
		p.call("stun", stun)
	var root := float(h.get("root", 0.0))
	if skull_id == "c013" and _skill_name == "skill01" and Meta.has_form_node("c013_seismic_2"):
		root = maxf(root, 2.5)
	if root > 0.0 and p.has_method("root"):
		p.call("root", root)


## 金刚·极：护盾抵挡或自然消失时每房最多回一次；换头主动散盾不触发。
func _shield_heal_once() -> void:
	if skull_id != "c013" or not Meta.has_form_node("c013_guard_3") or _shield_heal_used:
		return
	_shield_heal_used = true
	_restore_hp(1)


## 金钟罩（力僧 K 第二段）：给自己挂一次免伤，免疫下一次攻击；time 秒内没挨打也自动散
func _apply_self_shield(spec: Dictionary) -> void:
	_shield_hits = maxi(_shield_hits, int(spec.get("hits", 1)))
	var duration := float(spec.get("time", 8.0))
	if Meta.has_form_node("c013_guard_2"):
		duration += 2.0
	_shield_time = maxf(_shield_time, duration)
	if skull_id == "c013" and _own("c013_bell_1"):
		var pulled := 0
		for e in get_tree().get_nodes_in_group("enemies"):
			var p := e as Node2D
			if p != null and int(e.get("hp")) > 0 and absf(p.global_position.x - global_position.x) <= 340.0 + _radius_of(p) \
					and absf(p.global_position.y - global_position.y) <= 160.0:
				_pull_enemy(p, global_position.x + facing * (105.0 + pulled * 34.0))
				pulled += 1
	var dn := DAMAGE_NUMBER.new()
	dn.setup("金钟罩", Color(0.9, 0.75, 0.3)) # 金：护体成功提示
	dn.global_position = global_position + Vector2(0, -150)
	get_tree().current_scene.add_child(dn)
	_play_sfx("skill_boom")
	Feel.hitstop(0.05)


## 钟鸣·续：主动碎钟，剩余护罩越久，震缚越久；极阶留下一次性反震壳。
func _shatter_bell() -> void:
	var dur := clampf(_shield_time * 0.25, 0.6, 2.5)
	_shield_hits = 0
	_shield_time = 0.0
	_bell_shell = _own("c013_bell_3")
	for e in get_tree().get_nodes_in_group("enemies"):
		var p := e as Node2D
		if p != null and int(e.get("hp")) > 0 and absf(p.global_position.x - global_position.x) <= 360.0 + _radius_of(p) \
				and absf(p.global_position.y - global_position.y) <= 170.0:
			p.call("root", dur)
	_shield_heal_once()
	FX.spawn(get_tree().current_scene, "ink_hit", global_position + Vector2(0, -70), {"scale": 1.0})
	_play_sfx("gold")
	Feel.shake(7.0, 0.2)


## 技能命中附加流血：双刺 L「裂帛」用，每次命中叠一层（敌人侧 apply_bleed 结算，直扣血不进硬直）
func _apply_hit_bleed(p: Node2D, h: Dictionary) -> void:
	var layers := int(h.get("bleed", 0))
	if layers <= 0 or int(p.get("hp")) <= 0:
		return
	if p.has_method("apply_bleed"):
		p.call("apply_bleed", layers)


## 技能命中附加中毒（梅剑 K 尾端甩鞭）：毒 duration 秒，敌人侧每 0.5 秒直扣 1 点、不叠层只刷新
func _apply_hit_poison(p: Node2D, h: Dictionary) -> void:
	var dur := float(h.get("poison", 0.0))
	if dur > 0.0 and skull_id == "c023" and Meta.has_form_node("c023_venom_1"):
		dur += 1.0
	if dur <= 0.0 or int(p.get("hp")) <= 0:
		return
	if p.has_method("apply_poison"):
		p.call("apply_poison", dur)


## 技能自带回血段：与是否命中无关，带 "heal"/"heal_ratio"/"self_buff" 字段的技能走这里
## heal_ratio（剑仙 O 第三段）：按本次技能已打出总伤害的比例回血
func _apply_skill_heal(h: Dictionary) -> void:
	# 纯回血段没有命中判定，命中音得在这里补一声砸地闷响
	if h.has("sfx") and not h.has("damage"):
		_play_sfx(h["sfx"])
	# 自我加伤（剑仙 O 祈祷）：限时全伤 +N
	var sb: Dictionary = h.get("self_buff", {})
	if not sb.is_empty():
		_buff_damage = maxi(_buff_damage, int(sb.get("damage", 0)))
		_buff_timer = maxf(_buff_timer, float(sb.get("time", 6.0)))
	var heal_amt := int(h.get("heal", 0))
	if h.has("heal_ratio") and _skill_damage_total > 0:
		heal_amt += int(round(float(_skill_damage_total) * float(h["heal_ratio"])))
	var used_precepts := 0
	if skull_id == "c013" and _skill_name == "skill02" and h.has("heal") and _own("c013_ascetic_1"):
		used_precepts = _precepts
		heal_amt += used_precepts
	if heal_amt > 0:
		var total_heal := heal_amt + _heal_bonus
		var missing := maxi(0, max_hp - hp)
		var heal := mini(total_heal, missing)
		if heal > 0:
			hp += heal
			hp_changed.emit(hp, max_hp)
			var dn := DAMAGE_NUMBER.new()
			dn.setup("回血 +%d" % heal, Color(0.45, 0.75, 0.5))
			dn.global_position = global_position + Vector2(0, -130)
			get_tree().current_scene.add_child(dn)
		if used_precepts > 0:
			_precepts = 0
			var overflow := maxi(0, total_heal - missing)
			var shields := mini(used_precepts, overflow)
			if shields > 0 and _own("c013_ascetic_2"):
				_apply_self_shield({"hits": shields, "time": 6.0})


## 技能持续伤害段（梅剑·转鞭）：每 interval 秒对前后方范围内的所有敌人各打一次。
## 不顿帧、不震屏——0.5s 一跳的持续伤害如果每跳都卡一下，打起来会抖。
func _deal_skill_tick(tick: Dictionary) -> void:
	var did_hit := false
	for e in get_tree().get_nodes_in_group("enemies"):
		var p := e as Node2D
		if p == null or int(e.get("hp")) <= 0:
			continue
		var dx: float = p.global_position.x - global_position.x
		var dy: float = absf(p.global_position.y - global_position.y)
		if dy > float(tick.get("height", 120.0)):
			continue
		var in_front := dx == 0.0 or (dx > 0.0) == (facing > 0)
		# both = 转鞭：鞭子一直在转，前后方都扫得到
		if not (in_front or bool(tick.get("both", false))) or absf(dx) > float(tick["range"]) * range_scale * _tick_range_scale + _radius_of(p):
			continue
		p.call("take_damage", int(tick["damage"]) + _tick_damage_bonus + damage_bonus + _buff_now() + _target_damage_bonus(p), global_position.x)
		hit_scored()
		_on_build_hit(p, _skill_name)
		_apply_hit_poison(p, tick) # 转鞭每一跳也挂毒：只要长鞭剑打中就有中毒，不是只认尾端
		did_hit = true
	if did_hit:
		_play_sfx("voice_sword_hit")


## 远程格挡（梅剑·转鞭）：技能期间免疫并反弹敌方投射物。
## 目前工程里敌人还没有投射物，这里是预埋接口——以后敌方投射物命中玩家前先调用它，
## 返回 true 表示这次远程攻击已被她免疫并原路弹回，投射物应反向飞回"第一个遇到的敌人"。
func try_reflect_ranged(damage: int, from_x: float, attacker: Node = null) -> bool:
	if not _skill_ranged_guard:
		return false
	# 反弹目标：优先攻击者本人；否则沿来源方向找最近的那个敌人
	var target: Node = null
	if attacker != null and is_instance_valid(attacker) and attacker.has_method("take_damage"):
		target = attacker
	else:
		var dir := signf(from_x - global_position.x)
		var best := INF
		for e in get_tree().get_nodes_in_group("enemies"):
			var p := e as Node2D
			if p == null or int(e.get("hp")) <= 0:
				continue
			var d: float = (p.global_position.x - global_position.x) * dir
			if d >= 0.0 and d < best:
				best = d
				target = e
	if target != null:
		target.call("take_damage", damage, global_position.x)
		hit_scored()
		var tp := target as Node2D
		if tp != null:
			FX.spawn(get_tree().current_scene, "ink_hit", tp.global_position + Vector2(0, -60), {"scale": 0.4})
		_play_sfx("voice_fan_hit")
		Feel.shake(3.0, 0.1)
	return true


## 发一颗投射物：从胸口高度出手，沿朝向直线飞
func _spawn_projectile(spec: Dictionary, damage: int, sfx: String, y_off := 0.0) -> void:
	var pr = PROJECTILE.new()
	var from_skill := state == State.SKILL
	# root=命中定身秒数；split=命中后分裂数量；source 用于状态加伤与流派命中回报。
	pr.setup(facing, float(spec.get("speed", 520.0)) * _proj_speed_scale, float(spec.get("range", 420.0)) * _proj_range_scale,
		damage, sfx, proj_pierce or bool(spec.get("pierce", false)), float(spec.get("root", 0.0)),
		int(spec.get("split", 0)), str(spec.get("style", "qi")),
		int(spec.get("bleed", 0)), float(spec.get("scale", 1.0)), 0,
		self, from_skill, _skill_cast_id)
	pr.global_position = global_position + Vector2(facing * 36.0, -52.0 + y_off)
	get_tree().current_scene.add_child(pr)


## 当前该用的待机动画：残血形态（weak 之类）优先，其余回普通 stand
func _idle_anim() -> String:
	if _low_idle_anim != "" and _low_hp_ratio > 0.0 \
			and float(hp) / float(maxi(1, max_hp)) <= _low_hp_ratio:
		return _low_idle_anim
	return str(anim_map["idle"])


func _hurt_tick(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, accel * delta)
	# 倒地链（力僧）：逐段按动画真实时长接续，段与段之间无缝，起身段整段无敌
	if _hurt_phase == "chain":
		_hurt_seg_left -= delta
		while _hurt_seg_left <= 0.0:
			if _hurt_chain.is_empty():
				_end_hurt_chain()
				return
			_start_chain_seg()
		return
	_hurt_timer -= delta
	# 倒地流程分两段：fall 播完进 getup，起身段整段无敌（避免被压在倒地循环里起不来）
	if _hurt_phase == "fall" and _hurt_timer <= _hurt_getup_dur:
		_hurt_phase = "getup"
		_invincible = true
	if _hurt_timer <= 0.0:
		_hurt_phase = ""
		_hurt_getup_dur = 0.0
		_invincible = false
		_set_state(State.IDLE if is_on_floor() else State.FALL)


## 倒地链起手：把形态表 knock_chain 展开成带真实时长的段队列，立刻播第一段
func _start_hurt_chain(knockback: Vector2) -> void:
	state = State.HURT
	_hurt_phase = "chain"
	_hurt_chain.clear()
	for n in _knock_chain:
		var an := str(n)
		_hurt_chain.append({"anim": an, "dur": float(_anim_durations.get(an, 0.3))})
	_hurt_seg_left = 0.0
	velocity = knockback * 0.6
	_idle_queued = false
	_invincible = false
	_start_chain_seg()


## 播链里的下一段：起身段一开始就挂无敌（与普通倒地流程同一规则）
func _start_chain_seg() -> void:
	if _hurt_chain.is_empty():
		_end_hurt_chain()
		return
	var seg: Dictionary = _hurt_chain.pop_front()
	_hurt_seg_left = float(seg["dur"])
	if str(seg["anim"]) == str(anim_map.get("getup", "")):
		_invincible = true
	_play(str(seg["anim"]), false)


func _end_hurt_chain() -> void:
	_hurt_phase = ""
	_hurt_chain.clear()
	_hurt_seg_left = 0.0
	_invincible = false
	_set_state(State.IDLE if is_on_floor() else State.FALL)


## 给 HUD 查技能冷却进度：返回 0（就绪）~ 1（刚放完）。未知技能返回 0。
func get_skill_cd_ratio(n: String) -> float:
	var cfg: Dictionary = skill_config.get(n, {})
	if cfg.is_empty():
		return 0.0
	var total: float = cfg["cooldown"]
	if total <= 0.0:
		return 0.0
	var cd: float = _skill_cds.get(n, 0.0)
	return clampf(cd / total, 0.0, 1.0)


## 给 HUD 查技能对应的按键字母
func get_skill_key(n: String) -> String:
	var cfg: Dictionary = skill_config.get(n, {})
	var action := str(cfg.get("action", ""))
	if action == "":
		return "-"
	# 优先读 InputMap（设置里改键后 HUD 跟着变），读不到再退回写死表
	var s := Settings.action_label(action)
	return s if s != "-" else str(KEY_LABELS.get(action, "-"))


# ---------- 动作入口 ----------

func _try_jump() -> void:
	if _jump_seal <= 0.0 and _jump_buf > 0.0 and _coyote > 0.0:
		_jump_buf = 0.0
		_coyote = 0.0
		velocity.y = jump_velocity * _qg_jump_mul # 轻功：明显更高的起跳
		_hover_left = _qg_hover # 本次跳跃带一段顶点悬停
		_set_state(State.JUMP)


func _try_dash() -> void:
	if not Input.is_action_just_pressed("dash") or _dash_cd > 0.0 or _dash_seal > 0.0:
		return
	if skull_id == "z003" and _own("z003_returning_2") and _return_time > 0.0:
		_return_dash()
		return
	var anim := str(anim_map["dash"])
	var dur := _dash_time_base
	var speed := _dash_speed_base
	var cd := dash_cooldown
	# 双闪避池（剑仙）：站着不动就是原地闪（零位移），移动中就随机抽一段带位移的闪避
	if not _dash_pool.is_empty():
		var entry: Dictionary = {}
		if Input.get_axis("move_left", "move_right") != 0.0:
			var pool: Array = _dash_pool.get("move", [])
			if not pool.is_empty():
				entry = pool[randi() % pool.size()]
				cd = float(entry.get("cd", _dash_pool.get("move_cd", dash_cooldown)))
		else:
			entry = _dash_pool.get("still", {})
			cd = float(entry.get("cd", _dash_pool.get("still_cd", 1.0)))
		if not entry.is_empty():
			anim = str(entry.get("anim", anim))
			dur = float(entry.get("time", dur))
			speed = float(entry.get("speed", speed))
	state = State.DASH
	if skull_id == "c021" and Meta.has_form_node("c021_shadow_1"):
		_dash_attack_window = 2.0
	_dash_speed_now = speed
	_dash_cd_set = cd
	_dash_timer = dur * _dash_time_scale # 闪避时长 = 闪避动画长度（整段都是完美闪避）
	_play(anim, false, _dash_anim_speed)
	_play_sfx("dash_step") # 冲刺踏地声，补上原本只有画面没有声音的空档


## 去来：归痕中闪避沿原路返回，只留状态不重复结算 O 的伤害。
func _return_dash() -> void:
	var start := global_position
	var left := minf(start.x, _return_mark.x) - 30.0
	var right := maxf(start.x, _return_mark.x) + 30.0
	var did_hit := false
	for e in get_tree().get_nodes_in_group("enemies"):
		var p := e as Node2D
		if p == null or int(e.get("hp")) <= 0:
			continue
		if p.global_position.x < left or p.global_position.x > right or absf(p.global_position.y - start.y) > 170.0:
			continue
		did_hit = true
		p.call("apply_bleed", 1)
		p.call("root", 1.2)
		if _own("z003_returning_3") and _outbound_hits.has(p.get_instance_id()):
			p.call("stun", 1.5) # 去程与返程交叉命中：破招
	global_position = _return_mark
	_return_time = 0.0
	_outbound_hits.clear()
	_hurt_invincible = maxf(_hurt_invincible, 0.35)
	_dash_cd = 0.0 if did_hit and _own("z003_returning_3") else dash_cooldown * _dash_cd_scale
	FX.spawn(get_tree().current_scene, "speedline", (start + global_position) * 0.5, {"scale": 0.8})
	FX.spawn(get_tree().current_scene, "ink_hit", global_position + Vector2(0, -60), {"scale": 0.45})
	_play_sfx("dash_step")


func _start_attack(idx: int) -> void:
	if skull_id == "z000" and _wind_final and Meta.has_form_node("z000_wind_1"):
		idx = attacks.size() - 1
		_wind_final = false
	if idx < 0 or idx >= attacks.size():
		return
	var atk: Dictionary = attacks[idx]
	state = State.ATTACK
	_attack_idx = idx
	_attack_queued = false
	_final_wave_done = false
	_attack_dodge_bonus = skull_id == "c021" and Meta.has_form_node("c021_shadow_1") and _dash_attack_window > 0.0
	if _attack_dodge_bonus:
		_dash_attack_window = 0.0 # 只强化闪避后的下一段普攻
	# 随机池段（银夜三段普攻）：每段从 pool 抽一种动画，锁定时长 = 抽中动画的真实时长，
	# 命中时刻/判定范围也按抽中的动画查表（pool 段用 hit_at/range 字典逐动画标定）
	var anim := str(atk.get("anim", ""))
	if atk.has("pool"):
		var pool: Array = atk["pool"]
		anim = str(pool[randi() % pool.size()])
		var hit_map: Dictionary = atk.get("hit_at", {})
		var range_map: Dictionary = atk.get("range", {})
		var h := {
			"at": float(hit_map.get(anim, 0.3)),
			"range": float(range_map.get(anim, 100.0)),
			"damage": int(atk.get("damage", 1)),
		}
		if atk.has("launch"):
			h["launch"] = atk["launch"] # 击飞（段2）：敌人挑空
		if atk.has("knockback"):
			h["knockback"] = atk["knockback"]
		_attack_hits = [h]
		_attack_timer = float(_attack_durations.get(anim, 0.6))
	else:
		_attack_hits = (atk["hits"] as Array).duplicate() # 待弹出的命中时刻列表
		_attack_timer = float(atk["lock"])
	_attack_lock = _attack_timer
	_attack_anim = anim
	velocity.x = facing * float(atk["lunge"])
	_play(anim, false)
	_play_sfx("weapon_sword") # 起手嗖一声
	_queue(anim_map["idle"], true) # 打完自动回 idle，防止卡在收招帧
	_idle_queued = true # 与 _start_skill 一致：idle 已在队列里，收招超时别再 _play 重开淡化


func _try_skill() -> void:
	if skull_id == "c013" and _own("c013_bell_2") and _shield_hits > 0 and Input.is_action_just_pressed("skill"):
		_shatter_bell()
		return
	for n in skill_config:
		var cfg: Dictionary = skill_config[n]
		if not Input.is_action_just_pressed(cfg["action"]) or _skill_cds.get(n, 0.0) > 0.0:
			continue
		# 觉醒限定技（O/P）：剑仙看剑意觉醒窗口 _awaken_time，银夜看觉醒加伤 _buff_timer，都不在则按了也不响应
		if bool(cfg.get("require_buff", false)) and _awaken_time <= 0.0 and _buff_timer <= 0.0:
			continue
		_start_skill(n)
		return


func _start_skill(n: String) -> void:
	if skull_id == "c021" and n == "skill01" and _own("c021_return_2"):
		_recall_daggers()
	state = State.SKILL
	_skill_name = n
	_skill_cast_id += 1
	_skill_cancel_ready = false
	if skull_id == "z000" and n == "atk04":
		_edge_k_hits.clear()
	var cfg: Dictionary = skill_config[n]
	_parry_ready = skull_id == "c023" and n == "skill02" and _own("c023_counter_1")
	if skull_id == "z000" and _own("z000_score_1"):
		var seal: String = {"skill": "K", "skill_sweep": "L", "skill_ult": "U"}.get(str(cfg.get("action", "")), "")
		if seal != "":
			_sword_seals[seal] = true
	if skull_id == "z000" and n == "skill09" and _awaken_time > 0.0 and _own("z000_score_3"):
		for id in _seal_targets:
			var p: Node2D = _seal_targets[id]["target"]
			if is_instance_valid(p) and int(p.get("hp")) > 0:
				_pull_enemy(p, global_position.x + facing * 120.0)
	if skull_id == "z003" and n == "skill11" and _own("z003_returning_1"):
		_return_mark = global_position
		_return_time = 6.0
		_outbound_hits.clear()
	# 随机池技能（银夜 I/O）：每次从池里抽一种动画，时长按抽中的走；冷却/命中段全技能统一
	_skill_anim = n
	if cfg.has("pool"):
		var pool: Array = cfg["pool"]
		_skill_anim = str(pool[randi() % pool.size()])
	# speed：动画播放速度倍率（<1 慢放，如银夜 K 蓄力斩）。锁定/真实时长拉长到 1/speed，
	# 命中/stop/blink 等时刻表仍按动画秒标定，_skill_tick 里用动画时间对齐，不用逐个缩放
	_skill_speed = float(cfg.get("speed", 1.0))
	var base_dur: float = float(_skill_durations.get(_skill_anim, 2.0))
	# align_max（银夜 I 觉醒）：池内动画时长不齐时，短动画慢放撑满池内最长——觉醒时长恒定
	if cfg.has("pool") and bool(cfg.get("align_max", false)):
		var max_dur := base_dur
		for an in cfg["pool"]:
			max_dur = maxf(max_dur, float(_skill_durations.get(str(an), base_dur)))
		_skill_speed *= base_dur / max_dur
	_skill_dur = base_dur / _skill_speed
	_skill_timer = _skill_dur
	# per-anim 命中标定（hit_at/range 按抽中动画查表）：池技能各动画挥出时刻/范围不同。
	# 附加效果（projectile/bleed/stun/击飞/回血等）也一并带进这一段命中
	if cfg.has("hit_at"):
		var at_map: Dictionary = cfg["hit_at"]
		var range_map: Dictionary = cfg.get("range", {})
		var h := {
			"at": float(at_map.get(_skill_anim, 0.5)),
			"range": float(range_map.get(_skill_anim, 100.0)),
			"height": float(cfg.get("height", 100.0)),
			"damage": int(cfg.get("damage", 1)),
			"both": bool(cfg.get("both", false)),
			"path": bool(cfg.get("path", false)),
			"sfx": str(cfg.get("sfx", "")),
		}
		for extra in ["projectile", "bleed", "poison", "stun", "root", "knockback", "launch",
				"heal", "heal_ratio", "self_buff", "self_shield", "full_screen", "room_buff"]:
			if cfg.has(extra):
				h[extra] = cfg[extra]
		_skill_hits = [h]
	else:
		_skill_hits = cfg.get("hits", []).duplicate(true)
	_skill_start_x = global_position.x
	# root_motion：节点跟着动画根骨走（双刺 U：动画自己后跃约 170px，节点必须跟到那儿，收招才不会滑回原点）
	_skill_root_follow = bool(cfg.get("root_motion", false))
	_skill_root_x = global_position.x
	if sprite:
		sprite.position = Vector2.ZERO # 清掉上一招残留的根骨补偿
	_skill_poise = bool(cfg.get("poise", false)) or (skull_id == "c023" and n == "skill02" and Meta.has_form_node("c023_patience_1"))
	_skill_reflect = bool(cfg.get("reflect", false))
	_skill_ranged_guard = bool(cfg.get("ranged_guard", false))
	_skill_tick_acc = 0.0
	_stop_done = false
	var room_penalty := float(_room_cd_uses.get(n, 0)) if _room_cd_cursed else 0.0
	_skill_cd_set = float(cfg["cooldown"]) * cooldown_scale * _mastery_cd * _form_cd_scale * float(_skill_cd_mod.get(n, 1.0)) + room_penalty
	_skill_cds[n] = _skill_cd_set
	if _room_cd_cursed:
		_room_cd_uses[n] = int(_room_cd_uses.get(n, 0)) + 1
	if skull_id == "c013" and n == "skill02" and _precepts >= 3 and _own("c013_ascetic_3"):
		_skill_cds[n] = 0.0
		_apply_self_shield({"hits": 1, "time": 6.0})
	_skill_damage_total = 0 # O 第三段按本次技能总伤害比例回血
	_awaken_pending = float(cfg.get("awaken_time", 0.0)) # I 觉醒：动画播完才开始计时
	if _awaken_pending > 0.0:
		_awaken_stacks = 0
	_invincible = false
	# 自带位移动画（银夜 O 抽到 #87 skill11-cankao）：原地播放，收招瞬间瞬移整段冲刺距离（闪现窗口×速度）
	_skill_teleport = 0.0
	if _skill_anim in cfg.get("teleport_anims", []):
		_skill_teleport = float(cfg.get("blink_speed", 800.0)) * (float(cfg.get("blink_to", 0.9)) - float(cfg.get("blink_from", 0.15))) * _blink_dist_scale + _blink_bonus_dist
	# 觉醒（银夜 I）：起手即回血 + 限时加伤
	if cfg.has("heal"):
		_apply_skill_heal({"heal": cfg["heal"]})
	if cfg.has("buff_damage"):
		_buff_damage = int(cfg["buff_damage"])
		_buff_timer = float(cfg.get("buff_time", 8.0))
		if skull_id == "z003" and n == "skill10" and Meta.has_form_node("z003_return_2"):
			_buff_timer += 2.0
	velocity.x = facing * float(attacks[0]["lunge"]) * 0.6 # 起手小前冲
	_play(_skill_anim, false, _skill_speed)
	_play_sfx("voice_skill_cast") # 技能起手嗡一声
	# 其他技能排队 stand 防止收招空窗；银夜 I 必须保留原轨道供 _skill_tick 监听完成，收招时再切 stand。
	if skull_id != "z003" or _skill_name != "skill10":
		_queue(anim_map["idle"], true)
		_idle_queued = true
	else:
		_idle_queued = false


## 立刻换成指定形态：拆旧骨架 → 重装形态数据 → 重建骨架
func swap_skull(id: String) -> void:
	if not Skulls.SKULLS.has(id) or id == skull_id:
		return
	_set_blink(false) # 换头瞬间收掉闪现的碰撞例外
	_invincible = false
	_idle_queued = false
	_attack_idx = -1
	_skill_name = ""
	_skill_timer = 0.0
	_skill_poise = false
	_skill_reflect = false
	_skill_ranged_guard = false
	_skill_tick_acc = 0.0
	_skill_teleport = 0.0
	_skill_root_follow = false # 新骨架自带 position 0，这里只清标记，别把旧形态的位移带过来
	_shield_hits = 0 # 金钟罩属于形态技能，换头即散
	_shield_time = 0.0
	_buff_timer = 0.0 # 觉醒属于银夜，换头即散
	_awaken_time = 0.0 # 剑仙觉醒与剑意层数同理，换头即散
	_awaken_pending = 0.0
	_awaken_stacks = 0
	_skill_damage_total = 0
	_stop_buff_timer = 0.0 # 时停加伤同理
	_hover_left = 0.0
	_feathers = 0
	_daggers.clear()
	if is_instance_valid(_bait):
		_bait.queue_free()
	_bait = null
	_bait_time = 0.0
	_branch_zones.clear()
	_plum_marks.clear()
	_parry_ready = false
	_bell_shell = false
	_precepts = 0
	_openings.clear()
	_edge_k_hits.clear()
	_k_sealed.clear()
	_skill_cancel_ready = false
	_wind_final = false
	_air_follow = 0.0
	_air_floats = 0
	_air_slam = false
	_air_combo_reset = false
	_delayed.clear()
	_sword_seals.clear()
	_seal_targets.clear()
	_outbound_hits.clear()
	_return_time = 0.0
	_time_marks.clear()
	_apply_profile(id)
	_setup_spine()
	Run.skull_id = id # 局外养成的击杀/通关记账按当前形态归属，换头后立刻同步
	_play_sfx("voice_skill_cast")
	# 化身光柱从脚下冲天而起，盖住拆骨换形的一瞬间（pillar 贴条底部留白已裁，bottom 锚点即脚底）
	FX.spawn(get_tree().current_scene, "pillar", global_position, {"scale": 0.75, "z": 30})
	if is_on_floor():
		state = State.IDLE
		_play(anim_map["idle"], true)
	else:
		state = State.FALL
		_play(anim_map["air"], true)
	skull_changed.emit(id)


## 回环：收鞭挡下首次近战；初/续会收招，极阶保持花域并续缚。
func _counter_attack(attacker: Node) -> bool:
	var p := attacker as Node2D
	if p == null or int(attacker.get("hp")) <= 0:
		return false
	_parry_ready = false
	var boss := attacker.has_method("stop_tier") and str(attacker.call("stop_tier")) == "boss"
	if boss:
		p.call("stun", 0.8)
	elif _own("c023_counter_2"):
		var old_pos := global_position
		global_position = p.global_position
		p.global_position = old_pos
		_hurt_invincible = maxf(_hurt_invincible, 0.6)
	else:
		_pull_enemy(p, global_position.x + facing * 90.0)
	if _own("c023_counter_3"):
		p.call("root", 2.5)
	else:
		_skill_hits.clear()
		_skill_poise = false
		_skill_reflect = false
		_skill_ranged_guard = false
		_invincible = false
		_idle_queued = false
		_set_state(State.IDLE)
	_hurt_invincible = maxf(_hurt_invincible, 0.25)
	FX.spawn(get_tree().current_scene, "slash", (global_position + p.global_position) * 0.5 + Vector2(0, -65), {"scale": 0.55})
	_play_sfx("voice_fan_hit")
	Feel.hitstop(0.06)
	return true


## 同招连段钥匙必须同时匹配攻击者实例与起手编号，不能凭相同动画名穿透无敌。
func _enemy_cast_key(attacker: Node, move: Dictionary) -> String:
	if attacker == null or not is_instance_valid(attacker):
		return ""
	var cast_id := int(move.get("cast_id", 0))
	if cast_id <= 0:
		return ""
	# 青笠分身与本体同招同段共用出手钥匙，镜像剑才能穿过彼此造成的受击无敌。
	var cast_owner_id := int(move.get("cast_owner_id", attacker.get_instance_id()))
	return "%d:%d" % [cast_owner_id, cast_id]


func _record_last_hit(attacker: Node, move: Dictionary, amount: int) -> void:
	Run.last_hit = {}
	if attacker != null and is_instance_valid(attacker):
		var enemy_type = attacker.get("type_id")
		if enemy_type != null:
			Run.last_hit = {
				"type_id": str(enemy_type),
				"anim": str(move.get("anim", attacker.get("_current_anim"))),
				"hit_at": maxf(0.05, float(move.get("hit_at", 0.65))),
				"damage": amount,
			}


func _apply_room_cd_curse() -> void:
	if _room_cd_cursed:
		return
	_room_cd_cursed = true
	var dn := DAMAGE_NUMBER.new()
	dn.setup("魔诅 · 冷却滋长", Color(0.62, 0.38, 0.72))
	dn.global_position = global_position + Vector2(0, -180)
	get_tree().current_scene.add_child(dn)


func hurt(amount: int = 1, knockback: Vector2 = Vector2.ZERO, attacker: Node = null, move: Dictionary = {}) -> void:
	if state == State.DEAD or _invincible:
		return
	# 完美闪避：冲刺途中碰到"本应命中"的伤害——全部闪掉并发收益
	# （小怪/Boss/投射物的伤害都走 hurt 这一个入口，挂这里全覆盖）
	if state == State.DASH:
		_perfect_dodge(attacker)
		return
	# 刀客「亡命三刀」前两刀：只演受击、不扣血，也不进入受伤无敌/消耗护盾，
	# 这样三刀能各自重播受击动画，最后的实伤不会被前两刀的无敌窗口吞掉。
	if bool(move.get("feedback_only", false)):
		_set_blink(false)
		_reset_root_follow()
		state = State.HURT
		_hurt_phase = ""
		_hurt_getup_dur = 0.0
		var feedback_anim := str(anim_map["hurt"])
		_hurt_timer = maxf(hurt_time, float(_anim_durations.get(feedback_anim, hurt_time)))
		velocity = knockback
		_idle_queued = false
		_play_sfx("hit_fist")
		FX.spawn(get_tree().current_scene, "ink_hit", global_position + Vector2(0, -70), {"scale": 0.35, "flip": knockback.x > 0.0})
		Feel.hitstop(0.025)
		Feel.shake(2.0, 0.08)
		_play(feedback_anim, false)
		return
	if _parry_ready and attacker != null and is_instance_valid(attacker) and _counter_attack(attacker):
		return
	if _bell_shell:
		_bell_shell = false
		_hurt_invincible = maxf(_hurt_invincible, 0.35)
		if attacker != null and is_instance_valid(attacker) and int(attacker.get("hp")) > 0:
			attacker.call("stun", 1.2)
			var ap := attacker as Node2D
			if ap != null:
				FX.spawn(get_tree().current_scene, "ink_hit", ap.global_position + Vector2(0, -70), {"scale": 0.55})
		_play_sfx("gold")
		Feel.hitstop(0.06)
		Feel.shake(5.0, 0.16)
		return
	# 定山·反伤：技能期间自身无敌，挨多少就原样弹回攻击者多少
	# 放在 _hurt_invincible 之前——刚受过伤的 0.8s 无敌期内照样反弹
	if _skill_reflect and attacker != null and is_instance_valid(attacker) \
			and attacker.has_method("take_damage"):
		var reflected := amount + _reflect_bonus # 金刚·初/极：反弹额外加伤
		attacker.call("take_damage", reflected, global_position.x)
		var ap := attacker as Node2D
		if ap != null:
			FX.spawn(get_tree().current_scene, "ink_hit", ap.global_position + Vector2(0, -60), {"scale": 0.4})
			var dn := DAMAGE_NUMBER.new()
			dn.setup(str(reflected), Color(0.72, 0.45, 0.3)) # 赭石：反伤数字挂在攻击者头上
			dn.global_position = ap.global_position + Vector2(0, -140)
			get_tree().current_scene.add_child(dn)
		_play_sfx("voice_fan_hit")
		Feel.shake(3.0, 0.1)
		return
	var cast_key := _enemy_cast_key(attacker, move)
	if _hurt_invincible > 0.0:
		# 只放行同一名攻击者、同一次起手且明确配置的后续段；其他防御仍在各自分支结算。
		if not bool(move.get("pierce_hurt_invincible", false)) or cast_key.is_empty() or cast_key != _hurt_cast_key:
			return
	# 金钟罩（力僧 K 第二段）：免疫这一下，挡完即散（8 秒没挨打也会自动消失）
	if _shield_hits > 0:
		_shield_hits -= 1 # 苦行可把多枚戒印转成多层护盾，一次攻击只挡一层
		if _shield_hits <= 0:
			_shield_time = 0.0
		var shield_dn := DAMAGE_NUMBER.new()
		shield_dn.setup("金钟罩", Color(0.9, 0.75, 0.3)) # 金：与完美闪避同色系
		shield_dn.global_position = global_position + Vector2(0, -150)
		get_tree().current_scene.add_child(shield_dn)
		FX.spawn(get_tree().current_scene, "ink_hit", global_position + Vector2(0, -70), {"scale": 0.5})
		_play_sfx("gold")
		Feel.hitstop(0.06)
		Feel.shake(3.0, 0.1)
		_shield_heal_once()
		return
	# 镰意绽花是无直伤的特殊命中：必须先经过闪避、反震、反伤、受击无敌与护盾，全部防御无效后才结算。
	if bool(move.get("bloom", false)):
		_apply_bloom(attacker, move)
		return
	var temporary_reduce := int(skull_id == "c013" and Meta.has_form_node("c013_meditation_2") and _hurt_guard_timer > 0.0)
	if Run.guard_available:
		temporary_reduce += 1
		Run.guard_available = false # 护砚只在实际扣血时消耗，闪避/护盾不会浪费
	amount = maxi(1, amount - _damage_reduce - temporary_reduce) # 所有减伤都遵守最低 1 伤
	# 只记录真正扣血的一击：闪避、护盾、受伤无敌与反伤都不会污染终局对演。
	_record_last_hit(attacker, move, amount)
	if skull_id == "c013" and Meta.has_form_node("c013_meditation_2"): 
		_hurt_guard_timer = 2.0
	if skull_id == "c023" and Meta.has_form_node("c023_patience_3") and _hurt_cd_refund_cd <= 0.0:
		_hurt_cd_refund_cd = 5.0
		_skill_cds["skill02"] = maxf(0.0, float(_skill_cds.get("skill02", 0.0)) - 2.0)
	_hurt_invincible = 0.8
	_hurt_cast_key = cast_key
	_set_blink(false) # 受击打断技能：闪现的碰撞例外一并清掉，别带着穿怪状态进硬直
	_reset_root_follow() # 技能被受击打断：把根骨位移结算进节点，别把骨架留在偏移位置
	var dealt := mini(amount, hp) # 过量伤害不计入镰碎回血；反伤/护盾/闪避在上方已直接返回
	hp -= amount
	if attacker != null and is_instance_valid(attacker) and attacker.has_method("on_player_hit"):
		attacker.call("on_player_hit", dealt, move, self)
	if hp > 0 and bool(move.get("room_cd_curse", false)):
		_apply_room_cd_curse()
	if hp > 0 and bool(move.get("cut", false)):
		_apply_cut(attacker, move, cast_key)
	if hp > 0 and int(move.get("bleed", 0)) > 0:
		_apply_bleed(int(move.get("bleed", 0)), attacker, move)
	if skull_id == "c013" and _own("c013_ascetic_1"):
		_precepts = mini(3, _precepts + 1)
		var precept_dn := DAMAGE_NUMBER.new()
		precept_dn.setup("戒印 %d/3" % _precepts, Color(0.9, 0.75, 0.3))
		precept_dn.global_position = global_position + Vector2(0, -165)
		get_tree().current_scene.add_child(precept_dn)
	hp_changed.emit(hp, max_hp)
	_spawn_number(amount, DMG_COLOR, 130.0)
	_play_sfx("hit_fist") # 玩家受伤闷拳声
	# 水墨受击花在胸口炸开，flip 跟击退方向（击退朝右 = 攻击来自左侧）
	FX.spawn(get_tree().current_scene, "ink_hit", global_position + Vector2(0, -70), {"scale": 0.45, "flip": knockback.x > 0.0})
	Feel.hitstop(0.05) # 挨打也要"一僵"：受击反馈和打人一样重要
	Feel.shake(8.0, 0.24)
	if hp <= 0:
		if _try_revive(knockback):
			return
		die()
		return
	# 升龙刀等实伤击飞：在普通受击与倒地链分支前覆盖竖直初速；防御与霸体规则不变。
	var launch_y := float(move.get("launch_velocity_y", 0.0))
	if launch_y < 0.0:
		knockback.y = launch_y
	var jump_seal := float(move.get("jump_seal", 0.0))
	if jump_seal > 0.0:
		_jump_seal = maxf(_jump_seal, jump_seal)
		var seal_dn := DAMAGE_NUMBER.new()
		seal_dn.setup("封跳", Color(0.85, 0.72, 0.42))
		seal_dn.global_position = global_position + Vector2(0, -150)
		get_tree().current_scene.add_child(seal_dn)
	var dash_seal := float(move.get("dash_seal", 0.0))
	if dash_seal > 0.0:
		_dash_seal = maxf(_dash_seal, dash_seal)
		var seal_dn := DAMAGE_NUMBER.new()
		seal_dn.setup("封闪", Color(0.85, 0.72, 0.42))
		seal_dn.global_position = global_position + Vector2(0, -150)
		get_tree().current_scene.add_child(seal_dn)
	# 霸体（力僧形态专属 + 定山技能自带）：技能期间挨打开着招式硬吃，掉血但不进硬直、不打断技能
	if (poise or _skill_poise) and state == State.SKILL:
		return
	# 伤害过阈值直接倒地：播 fall → getup（起身段无敌），重型攻击的惩罚更直观；
	# 形态表配了 knock_chain（力僧：重受击→浮空重受击→倒地→起身）就走整条链
	if _knock_at < 999 and amount >= _knock_at:
		if not _knock_chain.is_empty():
			_start_hurt_chain(knockback)
			return
		if _fall_anim != "":
			_start_knockdown(knockback)
			return
	# 受击分档：轻击 atked / 重击 atked_heavy，状态时长按动画真实长度锁
	var hurt_anim := str(anim_map["hurt"])
	if _hurt_heavy_at < 999 and amount >= _hurt_heavy_at:
		hurt_anim = _hurt_heavy_anim
	state = State.HURT
	_hurt_phase = ""
	_hurt_getup_dur = 0.0
	_hurt_timer = maxf(hurt_time, float(_anim_durations.get(hurt_anim, hurt_time)))
	velocity = knockback
	_idle_queued = false # set_animation 已清掉队列里的 stand
	_invincible = false
	_play(hurt_anim, false)


## 绽花只结算特殊效果：不扣当前生命、不消耗护砚，也不写入普通最后一击。
func _apply_bloom(attacker: Node, move: Dictionary) -> void:
	var ap := attacker as Node2D
	if ap == null:
		return
	_set_blink(false)
	_reset_root_follow()
	var actual := Run.lose_max_hp(int(move.get("max_hp_loss", 2)), self)
	global_position = ap.global_position + Vector2(0.0, -float(move.get("lift_height", 120.0)))
	velocity = Vector2.ZERO
	state = State.HURT
	_hurt_phase = ""
	_hurt_getup_dur = 0.0
	_hurt_timer = maxf(hurt_time, float(_anim_durations.get(str(anim_map["hurt"]), hurt_time)))
	_idle_queued = false
	_play(anim_map["hurt"], false)
	_play_sfx("hit_fist")
	FX.spawn(get_tree().current_scene, "ink_hit", global_position + Vector2(0, -70), {"scale": 0.45})
	Feel.hitstop(0.05)
	Feel.shake(6.0, 0.18)
	if actual > 0:
		var loss_dn := DAMAGE_NUMBER.new()
		loss_dn.setup("上限 -%d" % actual, Color(0.85, 0.72, 0.42))
		loss_dn.global_position = global_position + Vector2(0, -165)
		get_tree().current_scene.add_child(loss_dn)
	if attacker.has_method("on_player_hit"):
		attacker.call("on_player_hit", 0, move, self)


## 普通流血：每层每秒 1 伤、持续 3 秒、最多 5 层，新层刷新持续时间；双镰与青笠共用。
func _apply_bleed(layers: int, attacker: Node, move: Dictionary) -> void:
	if layers <= 0 or state == State.DEAD:
		return
	_bleed_stacks = mini(BLEED_MAX, _bleed_stacks + layers)
	_bleed_time = BLEED_DUR
	_bleed_source = {"attacker": attacker, "move": move.duplicate()}


func _bleed_tick(delta: float) -> void:
	if _bleed_stacks <= 0 or state == State.DEAD:
		return
	# 只累计仍处在流血期内的时间；结束帧先结算到期的整秒伤害，再清除状态。
	var active_delta := minf(delta, maxf(0.0, _bleed_time))
	_bleed_time -= delta
	_bleed_acc += active_delta
	while _bleed_acc >= 1.0 and _bleed_stacks > 0:
		_bleed_acc -= 1.0
		_bleed_damage()
		if state == State.DEAD or _bleed_stacks <= 0:
			return
	if _bleed_time <= 0.0:
		_clear_bleed()


func _bleed_damage() -> void:
	if state == State.DEAD:
		return
	var dealt := mini(_bleed_stacks, hp)
	hp -= _bleed_stacks
	hp_changed.emit(hp, max_hp)
	_spawn_number(dealt, DMG_COLOR, 130.0)
	FX.spawn(get_tree().current_scene, "ink_hit", global_position + Vector2(0, -70), {"scale": 0.22})
	if hp > 0:
		return
	var attacker = _bleed_source.get("attacker") as Node
	_record_last_hit(attacker, _bleed_source.get("move", {}), dealt)
	if _try_revive(Vector2.ZERO):
		return
	die()


func _clear_bleed() -> void:
	_bleed_stacks = 0
	_bleed_time = 0.0
	_bleed_acc = 0.0
	_bleed_source.clear()


## 镖去实伤后登记一组割伤；同招第二段只扣直伤，不会重复登记。
func _apply_cut(attacker: Node, move: Dictionary, cast_key: String) -> void:
	if bool(move.get("cut_per_segment", false)):
		cast_key += ":seg:%d" % int(move.get("seg", 0))
	if cast_key.is_empty() or _cut_casts.has(cast_key):
		return
	_cut_casts[cast_key] = true
	_cuts.append({
		"left": [3.0, 6.0],
		"attacker": attacker,
		"move": move.duplicate(),
		"key": cast_key,
	})


## 每组割伤各自倒计时：3 秒、6 秒各固定失去 1 血，多组之间不刷新也不合并。
func _cut_tick(delta: float) -> void:
	for i in range(_cuts.size() - 1, -1, -1):
		if _cuts.is_empty() or state == State.DEAD:
			return
		var cut: Dictionary = _cuts[i]
		var left: Array = cut["left"]
		for j in left.size():
			left[j] = float(left[j]) - delta
		while not left.is_empty() and float(left[0]) <= 0.0:
			left.pop_front()
			_cut_damage(cut)
			if _cuts.is_empty() or state == State.DEAD:
				return
		if left.is_empty():
			_cut_casts.erase(str(cut["key"]))
			_cuts.remove_at(i)


## 割伤是流血的细分结算：无硬直、无受击无敌、无击退，也不重新进入 hurt/阴影。
func _cut_damage(cut: Dictionary) -> void:
	if state == State.DEAD:
		return
	hp -= 1
	hp_changed.emit(hp, max_hp)
	_spawn_number(1, DMG_COLOR, 130.0)
	FX.spawn(get_tree().current_scene, "ink_hit", global_position + Vector2(0, -70), {"scale": 0.22})
	if hp > 0:
		return
	var attacker = cut.get("attacker") as Node
	_record_last_hit(attacker, cut.get("move", {}), 1)
	if _try_revive(Vector2.ZERO):
		_cuts.clear()
		_cut_casts.clear()
		return
	die()


## 赐福与复活墨符相互独立；优先消耗赐福，两者齐备时一局可以起身两次。
func _try_revive(knockback: Vector2) -> bool:
	var can_revive := false
	if Run.blessing == "revive" and not Run.blessing_used:
		Run.blessing_used = true
		can_revive = true
	elif Run.supply_revive and not Run.supply_revive_used:
		Run.supply_revive_used = true
		can_revive = true
	if not can_revive:
		return false
	_clear_bleed()
	hp = mini(4, max_hp)
	_hurt_invincible = 1.5 # 起身喘口气，别立刻又被围殴
	hp_changed.emit(hp, max_hp)
	state = State.HURT
	_hurt_phase = ""
	_hurt_getup_dur = 0.0
	_hurt_timer = float(_anim_durations.get(str(anim_map["getup"]), hurt_time))
	_skill_poise = false
	_skill_reflect = false
	_skill_ranged_guard = false
	velocity = knockback
	_play(anim_map["getup"], false)
	_queue(anim_map["idle"], true)
	_idle_queued = true
	return true


## 倒地：播倒地动画 → 接起身动画（起身段无敌）。hp 已扣完且未死亡时才走这里
func _start_knockdown(knockback: Vector2) -> void:
	var getup_anim := str(anim_map.get("getup", anim_map["hurt"]))
	var fall_dur := float(_anim_durations.get(_fall_anim, 0.5))
	_hurt_getup_dur = float(_anim_durations.get(getup_anim, 0.5))
	state = State.HURT
	_hurt_phase = "fall"
	_hurt_timer = fall_dur + _hurt_getup_dur
	velocity = knockback * 0.6
	_idle_queued = false
	_invincible = false
	_play(_fall_anim, false)
	_queue(getup_anim, false)
	_queue(anim_map["idle"], true)
	_idle_queued = true # 起身后 stand 已在队列里，_set_state 只同步不重开


func _spawn_number(amount: int, color: Color, height: float) -> void:
	var dn := DAMAGE_NUMBER.new()
	dn.setup(str(amount), color)
	dn.global_position = global_position + Vector2(randf_range(-12.0, 12.0), -height)
	get_tree().current_scene.add_child(dn)


## 完美闪避：冲刺中"本应命中"的伤害全部闪掉，并给收益——
## 冲刺冷却立刻回零（能接着连闪）、4s 全伤害 +2（与觉醒共用 buff 槽，取高者）、
## 0.5s 短无敌防同一轮攻击的后段在冲刺结束后立刻命中。
func _perfect_dodge(attacker: Node = null) -> void:
	_dash_cd = 0.0 # 收益一：冷却回零
	_hurt_invincible = maxf(_hurt_invincible, 0.5 + _dodge_time_bonus) # 冲刺窗口只有 0.16s，垫一层防后续段
	_buff_damage = maxi(_buff_damage, 2 + _dodge_bonus) # 收益二：限时加伤（掠影加档）
	_buff_timer = maxf(_buff_timer, 4.0 + _dodge_time_bonus)
	var cd_refund := _dodge_cd_refund
	if skull_id == "c021" and Meta.has_form_node("c021_shadow_2"):
		cd_refund += 1.0
	if cd_refund > 0.0:
		for n in _skill_cds:
			_skill_cds[n] = maxf(0.0, float(_skill_cds[n]) - cd_refund)
	if skull_id == "c021" and _own("c021_bait_1"):
		_spawn_bait()
	if skull_id == "z000" and Meta.has_form_node("z000_wind_1"):
		_wind_final = true
	if skull_id == "z000" and _own("z000_listen_1") and attacker != null and is_instance_valid(attacker):
		var p := attacker as Node2D
		if p != null and int(attacker.get("hp")) > 0:
			_openings[p.get_instance_id()] = {"target": p, "time": 5.0}
	_play_sfx("weapon_sword") # 侧身擦过的嗖声当闪避音
	var dn := DAMAGE_NUMBER.new()
	dn.setup("完美闪避", Color(0.9, 0.75, 0.3)) # 金：奖励时刻
	dn.global_position = global_position + Vector2(0, -150)
	get_tree().current_scene.add_child(dn)
	Feel.hitstop(0.04) # 顿一瞬强调"擦过去了"
	Feel.shake(2.0, 0.1)


func die() -> void:
	state = State.DEAD
	_set_blink(false) # 尸体也别穿怪
	_reset_root_follow() # 死亡时收掉根骨补偿，尸体倒在实际站位
	_shield_hits = 0 # 死了金钟罩也散
	_shield_time = 0.0
	_cuts.clear()
	_cut_casts.clear()
	_clear_bleed()
	velocity = Vector2.ZERO
	_idle_queued = false
	_invincible = false
	_buff_timer = 0.0 # 死亡收掉觉醒
	_play(anim_map["dead"], false)
	# 银夜：倒地动画播完接躺尸定格循环（dead 只有 0.083s，不循环会闪回 setup pose）
	var hold := str(anim_map.get("dead_hold", ""))
	if hold != "":
		_queue(hold, true)
	died.emit()


# ---------- 内部工具 ----------

func _post_move() -> void:
	match state:
		State.IDLE, State.RUN:
			if not is_on_floor() and _coyote <= 0.0:
				_set_state(State.FALL)
		State.JUMP:
			if velocity.y > 0.0:
				_set_state(State.FALL)
		State.FALL:
			if is_on_floor():
				_hover_left = 0.0 # 落地收掉残余悬停
				# 分段跳跃：落地瞬间补一帧落地动画（只在不移动时播，跑动着地直接接 run 更顺）
				var land := str(anim_map.get("jump_land", ""))
				if _jump_seg and land != "" and absf(velocity.x) <= 10.0:
					_play(land, false)
					_queue(anim_map["idle"], true)
					_idle_queued = true
					_set_state(State.IDLE)
					return
				_set_state(State.RUN if absf(velocity.x) > 10.0 else State.IDLE)


func _set_state(new_state: int) -> void:
	if state == new_state:
		return
	state = new_state
	match state:
		State.IDLE:
			if _idle_queued:
				# stand 已被 Spine 自动接续播放，只同步记录，不重复 set（重开会重开淡化）
				_current_anim = anim_map["idle"]
			else:
				_play(anim_map["idle"], true)
			_idle_queued = false
		State.RUN:
			_idle_queued = false
			_play(anim_map["run"], true)
		State.JUMP, State.FALL:
			_idle_queued = false # set_animation 会清掉队列里的 stand
			if _jump_seg:
				# 分段跳跃（剑仙）：起跳跳一帧起跳动画，空中换上升/下降姿态，落地另有落地帧
				if state == State.JUMP:
					_play(anim_map["jump_start"], false)
					_queue(anim_map.get("jump_mid", anim_map["air"]), true)
				else:
					_play(anim_map.get("jump_down", anim_map["air"]), true)
			else:
				_play(anim_map["air"], true)


func _apply_facing() -> void:
	if sprite:
		sprite.scale.x = base_scale * facing


## spd：播放速度倍率（<1 慢放）。set_animation 返回本条轨道，time_scale 只作用于它，不污染后续排队动画
func _play(anim: String, loop: bool, spd := 1.0) -> void:
	if _anim_state == null:
		return
	if loop and anim == _current_anim:
		return # 循环动画同名重放 = 从头再来一遍，跳跃顶点会抽搐
	_current_anim = anim
	var entry = _anim_state.call("set_animation", anim, loop, 0)
	if spd != 1.0 and entry != null and entry.has_method("set_time_scale"):
		entry.call("set_time_scale", spd)


func _queue(anim: String, loop: bool) -> void:
	if _anim_state:
		_anim_state.call("add_animation", anim, 0.0, loop, 0)


## 轻功悬停（银夜）：把当前轨道冻成"漂浮静止"姿态（time_scale=0），悬停结束恢复播放。
## 只动当前轨道，不影响队列里排好的待机动画
func _set_hover_freeze(on: bool) -> void:
	if on == _hover_frozen or _anim_state == null:
		return
	_hover_frozen = on
	if not _anim_state.has_method("get_current"):
		return
	var entry = _anim_state.call("get_current", 0)
	if entry != null and entry.has_method("set_time_scale"):
		entry.call("set_time_scale", 0.0 if on else 1.0)
