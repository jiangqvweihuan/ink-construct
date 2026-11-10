class_name Player
extends CharacterBody2D

## 玩家控制器 · 形态数据见 scripts/player/skulls.gd
## 每个形态自带骨架 / 缩放 / 动画名映射 / 普攻段 / 技能表，换头时按 profile 重建 SpineSprite。
## 缩放按"游戏内角色高 128px"反推，换头不会突然变大变小。

const DAMAGE_NUMBER := preload("res://scripts/ui/damage_number.gd")
const Skulls := preload("res://scripts/player/skulls.gd")
const PlayerAudio := preload("res://scripts/player/player_audio.gd")
const PlayerFx := preload("res://scripts/player/player_fx.gd")
const PROJECTILE := preload("res://scripts/systems/projectile.gd") # 远程形态的普攻/技能发投射物
const FX := preload("res://scripts/systems/fx.gd") # 精灵条特效：斩击/化身光柱/受击墨花
const SPINE_FX := preload("res://scripts/systems/spine_fx.gd")
const SpinePoseMixer := preload("res://scripts/systems/spine_pose_mixer.gd")
const Settings = preload("res://scripts/ui/settings.gd") # 改键后 HUD 键名要读 InputMap
const LocalCoop = preload("res://scripts/systems/local_coop.gd") # 本机双人：P2 走 p2_ 前缀动作
const BossTypes := preload("res://scripts/enemies/boss_types.gd")
const PvpTuning := preload("res://scripts/pvp/pvp_tuning.gd") # 对战数值：治疗/控制/持续伤害共用
const DMG_COLOR := Color(0.18, 0.36, 0.43) # 石青：玩家受伤数字

## 击倒保护：任意形态触发倒地动作后，5 秒内不再被击倒（全形态默认原则，不写进被动）
const KNOCK_COOLDOWN := 5.0


## 队列动画提前接管的时长：spine 在结束前一个混合时长（default_mix=0.2）就把下一段混进来，
## root_motion 技能必须在此之前结算位移，否则读到的是被 stand 拉回途中的根骨值（多留一帧余量）
const ROOT_MIX_LEAD := 0.24

## 场景未标注 battle_width 时的兜底地图宽度（正式房间 / 对战竞技场均为 1920）
const DEFAULT_BATTLE_W := 1920.0

## 技能 action -> HUD 按键字母
const KEY_LABELS := {"skill": "K", "skill_sweep": "L", "skill_ult": "U", "skill_i": "I", "skill_o": "O", "skill_p": "P"}

## 技能配置里 hits.at 是动画开始后多少秒判定命中，按逐帧截图标定：
## skill01：0.75s 前冲突刺后起跳隐身（0.75~1.28s 闪现位移+无敌），1.30s 现身一刀，path=沿闪现路径全判。
## skill03：1.0s 平刺一段，2.0s 双手分枪横扫一段（大范围）。
## skill04：举枪过顶连斩，1.2/2.1/3.0s 各一段。
## 锁定时长用动画真实时长（_skill_durations 运行时查表），不用手填。
## 音效命名与预载清单见 player_audio.gd。

var _skill_audio_events: Array = []
var _footstep_timer := 0.0

## 输入槽：0 = P1（沿用 project.godot 原键位），1 = 本机双人 P2（方向键 + 小键盘）
@export var input_slot := 0
## 联机镜像：为 true 时跳过整段物理/AI，只由 NetSync 用主机快照写入表现状态
var net_puppet := false
## 玩家对战：伤害改由 pvp_rules.gd 结算，并广播 pvp_strike；回合间隙用 pvp_frozen 定身
var pvp_mode := false
var pvp_frozen := false
# ---------- PVP 状态（仅 pvp_mode 读写；与 PvE 的受伤/控制计时完全分离） ----------
var _pvp_stop_time := 0.0
var _pvp_stop_caster: Node = null
var _pvp_root_time := 0.0
var _pvp_stun_time := 0.0
var _pvp_slow_time := 0.0
var _pvp_slow_scale := 1.0
var _pvp_bleed_time := 0.0
var _pvp_bleed_stacks := 0
var _pvp_bleed_acc := 0.0
var _pvp_poison_time := 0.0
var _pvp_poison_acc := 0.0
var _pvp_vuln_time := 0.0
var _pvp_frenzy_time := 0.0
var _pvp_pressure := false
var _pvp_cd_cursed := false
## 红蝶在 PVP 中按回合计一次，不写 Run 的全局标记（两位玩家同选 c021 也不会互相吞掉）
var _pvp_butterfly_used := false
## 红蝶复活起身保护：这段时间内双方伤害都不结算，避免刚复活就被同一套连段秒回
var _pvp_revive_guard := 0.0
## 红蝶复活后的每秒生命流失（与 PvE 同一套机制，PVP 同样生效）
var _pvp_butterfly_drain := false
var _pvp_butterfly_tick := 0.0
## 红尘：被绛弦实际伤害后叠在攻击方身上的怨层，每 3 层使其每段伤害 -1
var _pvp_grudge := 0
## 剑宗：被剑仙实际伤害后治疗减半，持续到本回合结束
var _pvp_heal_cut := false
var net_anim_loop := true
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
## 玩家对战：普攻/技能到命中帧时广播本次判定参数，由 pvp_rules.gd 结算；PvE 不监听
signal pvp_strike(spec: Dictionary)

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
var _dash_gap := 0.0 # 闪避结束后的最小间隔；冷却返还也不能绕过
var _attack_idx := -1
var _attack_timer := 0.0
var _attack_queued := false
var _attack_recovery := 0.0 # 全体化身：连段结束或中断后，0.7 秒内不能重新起手普攻
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
const C013_BUDDHA_MAX := 3 # 镇岳佛陀层数上限；满层后再获得层数改为恢复 1 点生命
var _jump_seal := 0.0 # 辟地实伤附加：封跳剩余秒数，不影响闪避与其他动作
var _dash_seal := 0.0 # 旋斩实伤附加：只封 Shift 闪避，不影响移动、跳跃与攻击
var _cripple_time := 0.0 # 墨霆致残：封跳跃、Shift 闪避与所有带位移的技能
var _mo_ting_burn_stacks := 0 # 贯昼灼烧：只提高墨霆后续激光伤害，不独立跳伤
var _mo_ting_burn_time := 0.0
const FEN_DING_BURN_INTERVALS := [60.0, 58.0, 54.0, 48.0, 40.0, 30.0, 18.0, 10.0]
var _fen_ding_burn_stacks := 0 # 焚鼎怒焰：永久无限叠层，共用一个逐渐加速的扣血计时器
var _fen_ding_burn_left := 0.0
var _fen_ding_burn_source: Node = null
var wu_che_wanted := false # 武车通缉：仅一层，召唤物实伤 +1；闪避武撞或武车死亡解除
var _mo_ting_grabbed := false # 墨颤抓取：由墨霆显式释放，时停/破招/死亡都不能留下锁定
var _ming_zhong_holder: Node2D = null # 鸣钟四连击：首段实伤后固定在 Boss 正前方并随其根骨位移
var _ming_zhong_vulnerable_time := 0.0 # 易伤：每层仅一份，受实伤固定 +1 并刷新到 12 秒
var _ming_zhong_holy := 0 # 神眷圣光：觉醒后的零伤命中累计，36 层直接秒杀
var _passive_seal_time := 0.0 # 碎岳剥离：15 秒内禁止全部局内强化与永久修炼
var _stolen_passives: Dictionary = {} # 佛眼取走的被动 id；下次扫描或碎岳死亡时归还
var _sui_yue_pressure := false # 邪佛压场：封自身增益，保留基础形态、回血与觉醒
var _stun_time := 0.0 # 万佛手：实伤附加眩晕，锁定操作但不制造额外伤害
var _room_awaken_damage := 0 # 影殇 P 觉醒强化：与局内加伤分槽，邪佛不能抹去
var _awaken_buff_damage := 0 # 当前觉醒动作提供的加伤，供邪佛下单独保留
var _red_butterfly_left := 1.0 # 红蝶复活后的每秒生命流失
var _c023_frost_bonus := 0 # 霜梅：本房 K 尾鞭加伤，下次进房按实际恢复量重算
var _z000_lady_timer := 20.0 # 淑女：每 20 秒自检
var _z000_confidence_time := 0.0 # 自信：10 秒内技能冷却减半、伤害 +1
var _charm_summon: Node2D = null # 魅唤：同时最多一名，独立于武车自身召唤列表
var _stolen_regen_left := 5.0
var _stolen_bloodthirst := false
var _stolen_sword_intent := 0
var _stolen_sword_clone: Node2D = null # 夺取剑意：三层后的唯一同步凝华虚影
var _stolen_block := 0
var _stolen_bell := 0 # 佛曰：每层两点抵挡，独立于有时限的形态金钟罩
var _stolen_divine := false
var _stolen_holy: Dictionary = {}
var _stolen_flame_awakened := false
var _stolen_wall_free := true # 墨徒信仰：夺取后首次撞墙免耐久
var _stolen_wall_latch := false
var _stolen_history: Array = [] # 璀璨时代：记录本实体两秒前的位置
var _stolen_history_time := 0.0
var _stolen_era_contacts: Dictionary = {} # 每次闪避接触同一目标只回溯一次
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
var _knock_chain: Array = [] # 倒地链（形态表 knock_chain）：重受击逐段接续，最后一段起身（镇岳）
var _hurt_chain: Array = [] # 倒地链剩余段：[{anim, dur}]
var _hurt_seg_left := 0.0 # 当前段剩余时间
var _knock_cd := 0.0 # 击倒保护剩余时间：> 0 时只吃伤害与普通受击，不再触发倒地
var _shield_hits := 0 # 金钟罩剩余免伤次数（镇岳 K 第二段）
var _shield_time := 0.0 # 金钟罩剩余秒数（到点自动消失）
var _mastery_cd := 1.0 # 契合 Lv1：该形态技能冷却倍率
var _mastery_dmg := 0 # 契合 Lv2：该形态普攻加伤
var body_radius := 30.0 # 受击半径：挨打按"攻击方射程 + 本半径"判定（与小怪/Boss 同一规则）
var _fx_scale := 0.0 # 通用身体特效的体型倍率覆盖（形态显式配置；0 = 按 body_radius 自动换算）
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
var _skill_poise := false # 当前技能自带的霸体（镇岳定山：蓄力期间自身霸体，不依赖强化）
var _skill_reflect := false # 当前技能自带的反伤（镇岳定山：技能期间无敌，伤害原样弹回攻击者）
var _skill_ranged_guard := false # 当前技能的远程格挡（梅剑转鞭：技能期间免疫并反弹敌方投射物）
var _skill_tick_acc := 0.0 # 技能持续伤害段的计时累计（每 interval 秒结算一次）
# ---------- 局外永久修炼的运行时状态（配置在 Meta.FORM_NODES） ----------
var _attack_range_scale := 1.0 # 梅剑·鞭势：只放大普攻，不影响技能
var _skill_range_scale := 1.0 # 镇岳·震岳：只放大 K
var _blink_bonus_dist := 0.0 # 银夜·无还：O 固定位移增量
var _perm_lifesteal_cd := 0.0 # 绯刃·血舞：独立 8 秒回血计时
var _shield_heal_used := false # 镇岳·金刚：每房一次护盾回血
var _hurt_guard_timer := 0.0 # 镇岳·禅定：受击后的短暂减伤
var _hurt_cd_refund_cd := 0.0 # 梅剑·静守：受击减 K 冷却的内置间隔
var _dash_attack_window := 0.0 # 绯刃·无影：闪避后下一普攻的生效窗口
var _attack_dodge_bonus := false # 本段普攻是否已拿到上述加伤
var _final_wave_done := false # 绯刃·连刃：末段追加剑气每段普攻至多一次
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
var _branch_zones: Array = [] # 白疏影·枝界：{x, y, radius, time}
var _plum_zones: Array = [] # 梅烙·极花域：{x, y, radius, time, node}
var _plum_marks: Dictionary = {} # 梅烙：目标 id -> {target, hits, marked}
var _parry_ready := false # 回环：每次 K 只格挡首次近战
var _bell_shell := false # 定山·碎钟后的一次反震壳
var _precepts := 0 # 苦行戒印
var _openings: Dictionary = {} # 洛惊鸿·破绽：目标 id -> {target, time}
var _air_follow := 0.0 # 挑月 / 踏霄的空中追身窗口
var _air_chase_free := false # 踏霄·初：每段滞空可免费追身一次
var _air_floats := 0 # 挑月每次起跳的续浮空次数
var _air_slam := false # 银夜空中第三段是否按砸落结算
var _air_combo_reset := false # 砸落反弹后可再接二段挑飞
var _sword_seals: Dictionary = {} # 惊鸿谱自身 K/L/U 三诀
var _seal_targets: Dictionary = {} # 带诀敌人：id -> {target}
var _outbound_hits: Dictionary = {} # 银夜 O 去程命中者，返程交叉判破招
var _return_mark := Vector2.ZERO # 去来归痕
var _return_mark_node: Node2D = null # 去来·初：可见归痕
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
# ---------- 绛弦·苏挽音：觉醒次数、八音递减与每房被动 ----------
var _skill_runtime: Dictionary = {} # 双形态 U 本次实际配置；冷却仍记在同一个技能键上
var _pipa_awaken_count := 0
var _pipa_o_used := false
var _pipa_wave_hits: Dictionary = {} # 本次 O：目标实例 id -> 已命中段数
var _pipa_sorrow_timer := 30.0
# ---------- 烬生·赤烬专属：燃尽 / 战意 ----------
var _z001_burnout := false # 生命归零后进入燃尽：后续伤害改为扣生命上限
var _z001_fury := 0 # 战意层数：每层使全部伤害 +N，不设上限
var _z001_kill_acc := 0 # 本房累计击杀（每 5 次 +1 层战意）
var _z001_hit_acc := 0 # 本房累计受击（每 5 次 +1 层战意）
# ---------- 银夜·将去未还专属机制（形态表注入，其他形态全为默认值=关闭） ----------
var _qg_jump_mul := 1.0 # 轻功：跳跃初速倍率（明显跳得更高）
var _qg_hover := 0.0 # 轻功：跃过顶点后空中滞留时长
var _qg_jump_mul_base := 1.0 # 形态表原始跳跃倍率（流派卡在其上叠加）
var _qg_hover_base := 0.0 # 形态表原始悬停时长
var _hover_left := 0.0 # 本次跳跃剩余悬停时间
var _hover_frozen := false # 悬停期间动画已定格（time_scale=0 冻成漂浮姿态）
var _room_buff_used := false # 银夜 P：本房间的觉醒强化是否已加持（玩家随房间重建 = 天然一房一次）
# 银夜 K「斩影」：蓄力起点会留下一道刀痕，短暂停留后自主回响第二刀
var _scar_x := 0.0 # 刀痕中心（记在蓄力起点：挥斩时人已向前，刀痕便留在身后）
var _scar_facing := 1
var _scar_range := 0.0
var _scar_time := 0.0 # 刀痕停留（也是回响倒计时）
var _scar_echo_done := false
var _scar_damage := 0
var _scar_bleed := 1
var _scar_refund := 1.0
var _scar_fx: Node2D = null
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
var _skill_cd_totals := {} # 技能名 -> 本次实际总冷却（各技能独立，供 HUD 比例使用）
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
var _pose_mixer = null # 绛弦：沿用山民最终方案，同帧补齐缺 key 骨骼的视觉混合
var _pending_anim := ""
var _pending_loop := false
var _pending_speed := 1.0
var _pending_queue: Array = []
var audio: PlayerAudio
var fx: PlayerFx


func _ready() -> void:
	add_to_group("player")
	_ignore_player_volume()
	if input_slot != 0:
		LocalCoop.ensure_input() # P2 动作运行时注册，早于本帧任何轮询
	max_hp = Run.form_base_hp(skull_id)
	hp = max_hp
	_register_pipa_passives()
	fx = PlayerFx.new(self)
	_apply_profile(skull_id)
	_setup_spine()
	audio = PlayerAudio.new(self)


## 多人同屏：玩家之间不做实体碰撞，避免互相挤开/卡位；地面、敌人与投射物不受影响
func _ignore_player_volume() -> void:
	for other in get_tree().get_nodes_in_group("player"):
		if other == self or not (other is PhysicsBody2D):
			continue
		add_collision_exception_with(other)
		other.add_collision_exception_with(self)


func _register_pipa_passives() -> void:
	Meta.register_battle_passive("c021_flash", {"form": "c021", "owned": true, "name": "闪身",
		"desc": "闪避不受 0.5 秒最小间隔限制；闪避攻击时将该段伤害回敬攻击者。", "boss_effect": {}})
	Meta.register_battle_passive("c021_red_butterfly", {"form": "c021", "owned": true, "name": "红蝶",
		"desc": "每局首次死亡满血复活并将上限提升至 100，此后每秒失去 1 生命，仍可受击。", "boss_effect": {}})
	Meta.register_battle_passive("c013_saint", {"form": "c013", "owned": true, "name": "圣僧",
		"desc": "免疫全部负面效果，单次受到的伤害最多为 3。", "boss_effect": {}})
	Meta.register_battle_passive("c013_demon", {"form": "c013", "owned": true, "name": "降魔",
		"desc": "每造成 4 次实际伤害获得一层可跨房保留的佛陀（最多 3 层，每层全伤 +1）；已满 3 层时改为恢复 1 点生命。当结算后的实际伤害恰好为 3 且此次攻击会倒地时，消耗一层只免除倒地。", "boss_effect": {}})
	Meta.register_battle_passive("c023_ink_plum", {"form": "c023", "owned": true, "name": "墨梅",
		"desc": "每次造成实际伤害额外积累 1 墨锭，终局一并结算。", "boss_effect": {}})
	Meta.register_battle_passive("c023_frost_plum", {"form": "c023", "owned": true, "name": "霜梅",
		"desc": "生命上限为 60；进新房间恢复全部损失生命，每恢复不足 10 点也按 10 点计，为本房 K 尾鞭提供等量段数加伤；普攻无 1 秒恢复限制。", "boss_effect": {}})
	Meta.register_battle_passive("z000_immortal", {"form": "z000", "owned": true, "name": "不朽",
		"desc": "所有生命恢复双倍，并允许溢出为不超过生命上限一半的额外生命。", "boss_effect": {}})
	Meta.register_battle_passive("z000_sword_sect", {"form": "z000", "owned": true, "name": "剑宗",
		"desc": "造成实际伤害后，使目标在当前房间的恢复效果永久减半；重复命中不继续叠乘。", "boss_effect": {}})
	Meta.register_battle_passive("z000_lady", {"form": "z000", "owned": true, "name": "淑女",
		"desc": "每 20 秒恢复 10% 最大生命（受不朽加成），并获得 10 秒自信：期间释放的技能冷却减半、伤害 +1。", "boss_effect": {}})
	Meta.register_battle_passive("z002_red_dust", {"form": "z002", "owned": true, "name": "红尘",
		"desc": "伤害她的敌人获得当前房永久怨；每 3 层使其每段伤害 -1，最低 1。", "boss_effect": {}})
	Meta.register_battle_passive("z002_ephemeral", {"form": "z002", "owned": true, "name": "须臾 · 红粉骷髅",
		"desc": "致命伤由一名未替死过的癫狂目标承受双倍溢出伤害，自身保留 1 生命。", "boss_effect": {}})
	Meta.register_battle_passive("z002_sorrow", {"form": "z002", "owned": true, "name": "神伤",
		"desc": "每 30 秒全房 5 伤并施加心灵震撼，强化目标全部减益。", "boss_effect": {}})
	Meta.register_battle_passive("z003_night", {"form": "z003", "owned": true, "name": "暗夜",
		"desc": "被攻击命中有 20% 概率不受伤害。", "boss_effect": {}})
	Meta.register_battle_passive("z003_blood_cut", {"form": "z003", "owned": true, "name": "血色切割",
		"desc": "本局击败同类型杂兵 6 次、精英 3 次或 Boss 1 次后，夺取其全部被动；接口同样支持化身与未来联机对手。", "boss_effect": {}})
	Meta.register_battle_passive("z003_charm_call", {"form": "z003", "owned": true, "name": "魅唤",
		"desc": "使用 P 时随机召唤一名已夺取被动的实体协助作战；召唤物数值不变，只攻击敌人。", "boss_effect": {}})
	Meta.register_battle_passive("z001_burnout", {"form": "z001", "owned": true, "name": "燃尽一切吧",
		"desc": "生命归零时不死亡，后续受到的伤害改为扣除生命上限，直至上限清零才判定死亡；期间获得任意回血即恢复正常的生命扣除逻辑。", "boss_effect": {}})
	Meta.register_battle_passive("z001_war_fury", {"form": "z001", "owned": true, "name": "战狂",
		"desc": "当前房间每累计击杀 5 名敌人或累计受到 5 次伤害，获得 1 层无上限的战意；每层使全部伤害附加等量焚烧伤害。切换房间清空层数。", "boss_effect": {}})


## 把形态表里的动画映射 / 普攻段 / 技能表 / HUD 顺序装到实例上
func _apply_profile(id: String) -> void:
	fx.clear_all()
	var profile: Dictionary = Skulls.get_profile(id)
	# 局外养成的契合度加成随形态一起装上（Meta 是 autoload，测试场景里也在）
	skull_id = id if Skulls.SKULLS.has(id) else Skulls.DEFAULT_ID
	_refresh_mastery()
	anim_map = profile["anim"]
	attacks = profile["attacks"]
	skill_config = profile["skills"]
	hud_skills = profile["hud_skills"]
	base_scale = float(profile["scale"])
	body_radius = float(profile.get("body_radius", 30.0)) # 形态表可按体型覆盖（未来大型化身）
	_fx_scale = float(profile.get("fx_scale", 0.0)) # 通用身体特效的体型倍率：不配 = 按受击半径自动换算
	# 轻功（银夜）：没有该配置的形态倍率 1.0、不悬停，手感不受影响
	var qg: Dictionary = profile.get("qinggong", {})
	_qg_jump_mul_base = float(qg.get("jump_mul", 1.0))
	_qg_hover_base = float(qg.get("hover", 0.0))
	_dash_anim_speed = float(profile.get("dash_anim_speed", 1.0)) # 短冲刺动画可慢放（银夜 autorush 只有 0.083s）
	# 双闪避池（剑仙）：站定/移动各一套，不配就走下方通用的单段闪避
	_dash_pool = profile.get("dash_pool", {})
	_jump_seg = anim_map.has("jump_start") or bool(profile.get("jump_no_start", false))
	_awaken_time = 0.0
	_awaken_pending = 0.0
	_awaken_stacks = 0
	_skill_damage_total = 0
	_c023_frost_bonus = 0
	_skill_runtime.clear()
	_pipa_awaken_count = 0
	_pipa_o_used = false
	_pipa_wave_hits.clear()
	_pipa_sorrow_timer = 27.0 if skull_id == "z002" and Meta.has_form_node("z002_grudge_1") else 30.0
	_z001_burnout = false
	_z001_fury = 0
	_z001_kill_acc = 0
	_z001_hit_acc = 0
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
	# 倒地链（镇岳）：不配就退回"单段 fall → getup"的老流程
	_knock_chain = profile.get("knock_chain", []).duplicate()
	_hurt_chain.clear()
	_hurt_seg_left = 0.0
	_shield_hits = 0
	_shield_time = 0.0
	# 换头后按新形态重算流派强化：旧形态的卡休眠，新形态的卡生效
	_apply_form_mods()


## 邪佛压场时只卸下增益，不改 Run / Meta 中的真实解锁与存档。
func set_sui_yue_pressure(active: bool) -> void:
	if active and _saint_immune():
		_sui_yue_pressure = false
		return
	_sui_yue_pressure = active
	_refresh_mastery()
	set_upgrades(_upgrades)
	if Run.active:
		max_hp = effective_max_hp(Run.max_hp)
		hp = mini(hp, max_hp)
		hp_changed.emit(hp, max_hp)


func effective_max_hp(raw_max: int) -> int:
	if _passives_disabled():
		var sealed_base := _sealed_base_hp()
		return maxi(1, sealed_base - (Run.max_hp_loss if Run.active else 0))
	var stolen_hp := int(_stolen_passives.has("c013_meditation_1")) + int(_stolen_passives.has("c023_patience_2"))
	return maxi(1, raw_max - stolen_hp)


## 被动被邪佛压制时的基础生命：红蝶 100 与梅剑 60 都写在被动里，压制后回落到基准；
## 其余角色的基础生命是定位分档，不属于被动，保留。
func _sealed_base_hp() -> int:
	if skull_id == "c021" and Run.c021_red_butterfly_used:
		return Run.RED_BUTTERFLY_HP
	if skull_id == "c023":
		return Run.BASE_HP
	return Run.form_base_hp(skull_id)


func extra_hp_cap() -> int:
	return int(floor(float(max_hp) * 0.5)) if skull_id == "z000" and has_battle_passive("z000_immortal") else 0


## HUD 白色尾段：超额生命由血条根据 hp/max_hp 自行拆分，这里只报额外护盾与格挡。
func hud_extra_hp() -> int:
	return _shield_hits + int(ceil(_stolen_bell / 2.0)) + _stolen_block + int(_parry_ready) + int(_bell_shell)


## 每次正式进房调用：霜梅先复原，再把本房实际恢复量转换为 K 尾鞭加伤。
func on_room_enter() -> void:
	# 战狂只认当前房间：换房即清空战意与两条累计线；燃尽状态随新房间重建一起复原
	if skull_id == "z001":
		_z001_fury = 0
		_z001_kill_acc = 0
		_z001_hit_acc = 0
		_z001_burnout = false
	_c023_frost_bonus = 0
	if skull_id != "c023" or not has_battle_passive("c023_frost_plum"):
		return
	var before := hp
	_restore_hp(maxi(0, max_hp - hp))
	var restored := maxi(0, hp - before)
	_c023_frost_bonus = int(ceil(float(restored) / 10.0))
	if Run.active:
		Run.set_slot_hp(input_slot, hp)


func _refresh_mastery() -> void:
	var mods: Dictionary = Meta.mods(skull_id)
	_mastery_cd = 1.0 if _passives_disabled() else float(mods["cd"])
	_mastery_dmg = 0 if _passives_disabled() else int(mods["damage"])


## 重算所有会被邪佛、剥离或佛眼暂时改变的战斗数值，不碰 Run / Meta 存档。
func _refresh_passive_loadout() -> void:
	_refresh_mastery()
	set_upgrades(_upgrades)
	if Run.active:
		max_hp = effective_max_hp(Run.max_hp)
	hp = mini(hp, max_hp)
	hp_changed.emit(hp, max_hp)


func apply_sui_yue_seal(dur := 15.0) -> void:
	if _saint_immune():
		return
	_passive_seal_time = maxf(_passive_seal_time, dur)
	_refresh_passive_loadout()


## 化身与敌方实体共用血色切割被动包；未来联机击败化身可直接提交此结构。
func export_passives() -> Dictionary:
	return {
		"type_id": skull_id,
		"tier": "boss",
		"passives": Meta.battle_passive_candidates(skull_id),
		"scene": "",
		"script": "",
	}


func sui_yue_passive_candidates() -> Array:
	var out: Array = []
	if _saint_immune():
		return out
	for id in Meta.battle_passive_candidates(skull_id):
		if not _stolen_passives.has(str(id)):
			out.append(str(id))
	return out


## 未来形态战斗被动统一查询：注册与永久修炼都经过失窃、剥离和邪佛判定。
func has_battle_passive(id: String) -> bool:
	if _passives_disabled() or _stolen_passives.has(id):
		return false
	if Meta.battle_passives.has(id):
		var info := Meta.battle_passive_info(id)
		return str(info.get("form", "")) == skull_id and bool(info.get("owned", true))
	return _form_node(id)


func steal_sui_yue_passive(id: String) -> bool:
	if _saint_immune() or not sui_yue_passive_candidates().has(id):
		return false
	_stolen_passives[id] = true
	_refresh_passive_loadout()
	return true


func return_sui_yue_passive(id: String) -> void:
	if not _stolen_passives.erase(id):
		return
	_refresh_passive_loadout()


func return_all_sui_yue_passives() -> void:
	if _stolen_passives.is_empty():
		return
	_stolen_passives.clear()
	_refresh_passive_loadout()


func clear_sui_yue_effects() -> void:
	_passive_seal_time = 0.0
	_stun_time = 0.0
	_stolen_passives.clear()
	_sui_yue_pressure = false
	_refresh_passive_loadout()


## 局内强化注入：通用卡（伤害/冷却/生命/冲刺/闪避）+ 当前形态的流派卡。换房间时由 Run.apply_to 重新调用
func set_upgrades(up: Dictionary) -> void:
	_upgrades = up.duplicate()
	var cd := int(up.get("cooldown", 0)) if not _passives_disabled() else 0
	damage_bonus = int(up.get("damage", 0)) if not _passives_disabled() else 0
	run_speed = 240.0 # 上一房间石碑的"疾风"随换房清掉（原位漂移不跨房）
	# 称号的冷却缩减不受邪佛压制（成就底子），与局内强化叠加
	cooldown_scale = maxf(0.5, 1.0 - 0.15 * cd + Achievements.bonus("cooldown"))
	max_hp = (Run.form_base_hp(skull_id) + int(up.get("hp", 0))) if not _passives_disabled() else _sealed_base_hp()
	# 疾影：冲刺时长/距离 +20%，完美闪避判定窗口同步变长；冷却 -10%
	var dash_lv := int(up.get("dash", 0)) if not _passives_disabled() else 0
	_dash_time_scale = (1.0 + 0.2 * dash_lv) * (1.0 + Achievements.bonus("dash"))
	_dash_cd_scale = maxf(0.6, 1.0 - 0.1 * dash_lv)
	# 掠影：完美闪避收益加档
	var dodge_lv := int(up.get("dodge", 0)) if not _passives_disabled() else 0
	_dodge_bonus = dodge_lv
	_dodge_time_bonus = 0.2 * dodge_lv + Achievements.bonus("dodge_window")
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
			_reflect_bonus += int(_form_node("c013_guard_1"))
			_skill_range_scale = 1.15 if _form_node("c013_seismic_1") else 1.0
		"c023":
			_attack_range_scale = 1.15 if _form_node("c023_lash_1") else 1.0
		"z003":
			_stop_bonus += 0.25 if _form_node("z003_time_1") else 0.0
			if _form_node("z003_time_2"):
				_stop_buff_damage = maxi(_stop_buff_damage, 1)
			_blink_bonus_dist = 100.0 if _form_node("z003_return_1") else 0.0
	# 轻功：形态表原值 + 流派加成（跳跃更高、悬停更久）
	_qg_jump_mul = _qg_jump_mul_base * (1.0 + _qg_jump_bonus)
	_qg_hover = _qg_hover_base + _qg_hover_bonus
	# 苦行·初：进房自带一层戒印，第一波不用先挨打才有收益
	if skull_id == "c013" and _own("c013_ascetic_1"):
		_precepts = maxi(_precepts, 1)


## 当前形态是否拥有某张局内卡。卡键按形态唯一，换头后旧卡自然休眠。
func _passives_disabled() -> bool:
	return _sui_yue_pressure or _passive_seal_time > 0.0


func _form_node(id: String) -> bool:
	return not _passives_disabled() and not _stolen_passives.has(id) and Meta.has_form_node(id)


func _move_speed() -> float:
	return 240.0 if _passives_disabled() else run_speed * (1.0 + Achievements.bonus("move_speed"))


func _own(key: String) -> bool:
	return not _passives_disabled() and int(_upgrades.get(key, 0)) > 0


## 流派状态计时。节点本身不另开 Timer，换房/死亡时随玩家实例一起销毁。
func _build_tick(delta: float) -> void:
	_air_follow = maxf(0.0, _air_follow - delta)
	if _return_time > 0.0:
		_return_time = maxf(0.0, _return_time - delta)
		if _return_time <= 0.0:
			_outbound_hits.clear()
			_clear_return_mark()
	if is_on_floor():
		_air_floats = 0
		_air_combo_reset = false
		_air_chase_free = false
	for i in range(_daggers.size() - 1, -1, -1):
		_daggers[i]["time"] = float(_daggers[i]["time"]) - delta
		if float(_daggers[i]["time"]) <= 0.0:
			var gone = _daggers[i].get("node")
			if is_instance_valid(gone):
				gone.queue_free()
			_daggers.remove_at(i)
	for i in range(_branch_zones.size() - 1, -1, -1):
		_branch_zones[i]["time"] = float(_branch_zones[i]["time"]) - delta
		if float(_branch_zones[i]["time"]) <= 0.0:
			_branch_zones.remove_at(i)
	_plum_zone_tick(delta)
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
		for e in _foes():
			var p := e as Node2D
			if p == null or int(e.get("hp")) <= 0:
				continue
			if absf(p.global_position.x - float(zone["x"])) <= float(zone["radius"]) + _radius_of(p) \
					and absf(p.global_position.y - float(zone.get("y", global_position.y))) <= 150.0 and e.has_method("contain"):
				var dur := 0.12 if not e.has_method("stop_tier") or str(e.call("stop_tier")) != "boss" else 0.06
				e.call("contain", dur)
	_scar_tick(delta)


## 银夜 K 斩影：刀痕留在蓄力起点，短暂预警后自主回响一次，再自行散去。
func _scar_tick(delta: float) -> void:
	if _scar_time <= 0.0:
		return
	_scar_time = maxf(0.0, _scar_time - delta)
	if _scar_time <= 0.0 and not _scar_echo_done:
		_scar_ring()
		_clear_scar()


## 落刀即留痕：刀痕中心取本次 K 的蓄力起点，因此向前挥斩时它正好封住身后的退路。
func _arm_scar(x: float, skill_range: float) -> void:
	_clear_scar()
	var cfg: Dictionary = _skill_runtime.get("scar", {})
	_scar_x = x
	_scar_facing = facing
	_scar_range = skill_range * float(cfg.get("range_scale", 1.15))
	_scar_time = float(cfg.get("delay", 0.55))
	_scar_damage = int(cfg.get("damage", 2))
	_scar_bleed = int(cfg.get("bleed", 1))
	_scar_refund = float(cfg.get("refund", 1.0))
	_scar_echo_done = false
	var scene := get_tree().current_scene
	if scene == null:
		return
	_scar_fx = FX.spawn(scene, "telegraph", Vector2(_scar_x, global_position.y),
		{"scale": maxf(0.55, _scar_range / 150.0), "loop": true, "z": -1,
		"mod": Color(0.40, 0.28, 0.32, 0.70)})


func _scar_ring() -> void:
	_scar_echo_done = true
	if is_instance_valid(_scar_fx):
		_scar_fx.queue_free()
	_scar_fx = null
	var scene := get_tree().current_scene
	if scene != null:
		FX.spawn(scene, "slash", Vector2(_scar_x, global_position.y - 52.0),
			{"scale": 1.15, "flip": _scar_facing < 0, "z": 21})
	_play_sfx("skill_blade")
	# PVP：刀痕中心可能不在脚下，按“与刀痕中心的距离 + 刀痕射程”近似成双向判定
	if pvp_mode:
		var center_dx := _scar_x - global_position.x
		_emit_pvp_strike({
			"damage": _scar_damage + damage_bonus + _buff_now(),
			"range": absf(center_dx) + _scar_range,
			"height": 120.0,
			"both": true,
		})
	var hits := 0
	for e in _foes():
		var p := e as Node2D
		if p == null or int(e.get("hp")) <= 0:
			continue
		if absf(p.global_position.x - _scar_x) > _scar_range + _radius_of(p):
			continue
		if absf(p.global_position.y - global_position.y) > 120.0:
			continue
		# PVP：伤害由 pvp_strike 统一结算，这里只负责挂流血与命中反馈
		if pvp_mode:
			_apply_hit_bleed(p, {"bleed": _scar_bleed})
			hits += 1
			continue
		var dealt := _damage_enemy(p, _scar_damage + damage_bonus + _buff_now())
		if dealt <= 0:
			continue
		hits += 1
		_apply_hit_bleed(p, {"bleed": _scar_bleed})
	if hits > 0:
		Feel.hitstop(0.04)
		Feel.shake(6.0, 0.16)
		if _scar_refund > 0.0 and _skill_cds.has("skill14_02"):
			_skill_cds["skill14_02"] = maxf(0.0, float(_skill_cds["skill14_02"]) - _scar_refund)
		var label := DAMAGE_NUMBER.new()
		label.setup("斩影 · 回响", Color(0.86, 0.68, 0.42))
		label.global_position = Vector2(_scar_x, global_position.y - 78.0)
		if scene != null:
			scene.add_child(label)


func _clear_scar() -> void:
	if is_instance_valid(_scar_fx):
		_scar_fx.queue_free()
	_scar_fx = null
	_scar_time = 0.0
	_scar_echo_done = true


## 场景切换瞬间 current_scene 可能为空：生成物宁可丢弃也不崩，返回是否成功挂载。
func _world_add(node: Node) -> bool:
	var root := get_tree().current_scene
	if root == null:
		node.queue_free()
		return false
	root.add_child(node)
	return true


## 梅烙·极：K 催花后在地面留下 3 秒花域，域内持续中毒，结束时把域内敌人拉回。
func _spawn_plum_zone(pos: Vector2) -> void:
	var ring := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in range(20):
		var a := TAU * float(i) / 20.0
		pts.append(Vector2(cos(a) * 150.0, sin(a) * 42.0))
	ring.polygon = pts
	ring.color = Color(0.92, 0.62, 0.66, 0.26)
	ring.global_position = pos + Vector2(0, -20)
	if not _world_add(ring):
		return
	var tw := ring.create_tween()
	tw.tween_property(ring, "modulate:a", 0.0, 0.6).set_delay(2.4)
	tw.tween_callback(ring.queue_free)
	_plum_zones.append({"x": pos.x, "y": pos.y, "radius": 150.0, "time": 3.0, "node": ring})


func _plum_zone_tick(delta: float) -> void:
	for i in range(_plum_zones.size() - 1, -1, -1):
		var zone: Dictionary = _plum_zones[i]
		zone["time"] = float(zone["time"]) - delta
		var ending := float(zone["time"]) <= 0.0
		for e in _foes():
			var p := e as Node2D
			if p == null or int(e.get("hp")) <= 0:
				continue
			if absf(p.global_position.x - float(zone["x"])) > float(zone["radius"]) + _radius_of(p) \
					or absf(p.global_position.y - float(zone["y"])) > 150.0:
				continue
			if ending:
				_pull_enemy(p, global_position.x + facing * 100.0)
			elif p.has_method("apply_poison"):
				p.call("apply_poison", 0.6)
		if ending:
			var node = zone.get("node")
			if is_instance_valid(node):
				node.queue_free()
			_plum_zones.remove_at(i)


func _clear_plum_zones() -> void:
	for zone in _plum_zones:
		var node = zone.get("node")
		if is_instance_valid(node):
			node.queue_free()
	_plum_zones.clear()


## 去来·初：归痕必须有可见实体，玩家才知道可以从这里返程。
func _spawn_return_mark() -> void:
	_clear_return_mark()
	var mark := Polygon2D.new()
	mark.polygon = PackedVector2Array([
		Vector2(-5, -8), Vector2(5, -8), Vector2(5, -220), Vector2(-5, -220),
	])
	mark.color = Color(0.62, 0.82, 0.9, 0.5)
	mark.global_position = _return_mark
	if not _world_add(mark):
		return
	_return_mark_node = mark
	var tw := mark.create_tween()
	tw.tween_property(mark, "modulate:a", 0.0, 0.6).set_delay(5.4)
	tw.tween_callback(mark.queue_free)


func _clear_return_mark() -> void:
	if is_instance_valid(_return_mark_node):
		_return_mark_node.queue_free()
	_return_mark_node = null


## 影饵只是一段可被敌人索敌的墨影，不是第二个玩家，也不承受伤害。
func _spawn_bait() -> void:
	if is_instance_valid(_bait):
		_expire_bait()
	_bait = Node2D.new()
	_bait.add_to_group("player_decoy")
	_bait.global_position = global_position
	if not _world_add(_bait):
		_bait = null
		return
	if not _spawn_bait_ghost(_bait):
		_make_bait_silhouette(_bait)
	_bait_time = 3.0 # 残影要撑到 L 首段（0.79s 起手）之后，否则影饵·极的交叉窗口几乎吃不到
	_bait_root = _own("c021_bait_2")


## 骨架加载失败时的兜底剪影：影饵·初至少要让玩家看见一个残影
func _make_bait_silhouette(host: Node2D) -> void:
	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([
		Vector2(-16, 0), Vector2(16, 0), Vector2(20, -62), Vector2(0, -104), Vector2(-20, -62),
	])
	body.color = Color(0.74, 0.9, 1.0, 0.4)
	host.add_child(body)


## 影饵的视觉是本体骨架的淡化复制：定格在闪避当下的姿势，而不是一团墨雾。
func _spawn_bait_ghost(host: Node2D) -> bool:
	var profile: Dictionary = Skulls.get_profile(skull_id)
	var data = load(str(profile.get("data", "")))
	if data == null or not data.call("is_skeleton_data_loaded"):
		return false
	var ghost = ClassDB.instantiate("SpineSprite")
	if ghost == null:
		return false
	host.add_child(ghost)
	ghost.set("skeleton_data_res", data)
	ghost.scale = Vector2(base_scale * facing, base_scale)
	ghost.modulate = Color(0.74, 0.90, 1.0, 0.55)
	var state = ghost.call("get_animation_state")
	if _current_anim.is_empty():
		return false
	var entry = state.call("set_animation", _current_anim, false, 0)
	var src = _anim_state.call("get_current", 0) if _anim_state != null else null
	if entry == null or src == null:
		return false
	# 与本体的当前轨道时间对齐后冻帧，残影就是闪避那一刻的姿势
	if entry.has_method("set_track_time") and src.has_method("get_track_time"):
		entry.call("set_track_time", float(src.call("get_track_time")))
	if entry.has_method("set_time_scale"):
		entry.call("set_time_scale", 0.0)
	return true


func _expire_bait() -> void:
	if not is_instance_valid(_bait):
		_bait = null
		_bait_time = 0.0
		return
	if _bait_root:
		for e in _foes():
			if int(e.get("hp")) > 0 and e.get("_target") == _bait:
				e.call("root", 1.5)
	_bait.queue_free()
	_bait = null
	_bait_time = 0.0
	_bait_root = false


func _play_sfx(sfx_name: String) -> void:
	audio.play(sfx_name)


## 完整施法音独占临时通道，收招和其他短音都不会把它截断。
func _play_full_sfx(sfx_name: String, volume_db := 0.0) -> AudioStreamPlayer:
	return audio.play_full(sfx_name, volume_db)


func _start_skill_loop(sfx_name: String) -> void:
	audio.start_loop(sfx_name)


func _stop_skill_loop() -> void:
	audio.stop_loop()


func _setup_spine() -> void:
	var profile: Dictionary = Skulls.get_profile(skull_id)
	var data_path := str(profile["data"])
	var data = load(data_path)
	if data == null or not data.call("is_skeleton_data_loaded"):
		push_error("Player: 骨架数据加载失败 " + data_path)
		return
	# 换头时先把旧骨架与待切换轨道拆掉，避免两套骨架或旧动画同时在场
	_pose_mixer = null
	_pending_anim = ""
	_pending_queue.clear()
	if sprite != null and is_instance_valid(sprite):
		sprite.queue_free()
		sprite = null
		_anim_state = null
	sprite = ClassDB.instantiate("SpineSprite")
	add_child(sprite)
	sprite.set("skeleton_data_res", data)
	# 绛弦沿用山民方案关闭原生混合，避免旧轨道销毁时把缺 key 骨骼瞬写回 setup pose。
	data.call("set_default_mix", 0.0 if skull_id == "z002" else 0.2)
	sprite.scale = Vector2(base_scale * facing, base_scale)
	_anim_state = sprite.call("get_animation_state")
	if skull_id == "z002":
		_pose_mixer = SpinePoseMixer.new(sprite)
	_root_bone = sprite.call("get_skeleton").call("get_root_bone") # root_motion 技能靠它读动画的位移量
	_root_bone_base = float(_root_bone.call("get_x")) if _root_bone != null else 0.0
	# 缓存技能动画真实时长，技能锁定必须按实际时长走（C016 的教训：手填时长收招会抽搐）
	# 随机池技能（银夜 I/O）：池里每个动画都要缓存，时长按抽中的那个走
	_skill_durations.clear()
	_skill_cds.clear()
	_skill_cd_totals.clear()
	for n in skill_config:
		var names: Array = (skill_config[n].get("pool", [skill_config[n].get("anim", n)]) as Array).duplicate()
		var alternate: Dictionary = skill_config[n].get("awaken", {})
		for an in alternate.get("pool", [alternate.get("anim", "")]):
			if str(an) != "" and not names.has(str(an)):
				names.append(str(an))
		for an in names:
			var a = data.call("find_animation", str(an))
			if a != null:
				_skill_durations[str(an)] = a.call("get_duration")
			else:
				push_error("Player: 技能动画不存在 " + str(an))
		_skill_cds[n] = 0.0
		_skill_cd_totals[n] = 0.0
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
	# 倒地链里的每段也要有真实时长（镇岳：重受击 / 浮空重受击 / 倒地 / 起身）
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


func _start_skill_spine(n: String) -> void:
	fx.clear_skill()
	if skull_id == "z000" and n == "skill08":
		# I 觉醒：脚底水平线、身体垂直中心浮现的地面法阵
		fx.skill_spine = fx.attach("E54057", Vector2.ZERO, "action", false,
			{"scale": 0.6, "center": true, "fx_role": "skill"})
	elif skull_id == "c013" and n == "skill02":
		# 头顶佛像只属于 U 立地听禅；K 钟荡群山、L 金刚怒目起手不显示
		fx.attach("E100182", Vector2(0.0, -150.0), "action", false,
			{"fx_role": "skill_start"})
	elif skull_id == "c021" and n == "skill5-":
		# L 罗刹旋舞：闪电劈在起手位置的地面上，世界坐标固定、不随角色移动；
		# 不再用 bottom 逐帧贴地——骨架包围盒随动画变化会让闪电一直上下跳。
		fx.skill_spine = fx.world("E54151", global_position, "action1", true,
			{"scale": 0.35, "fx_role": "skill"})
	elif skull_id == "z002" and n == "skill07_02":
		fx.attach("E53174", Vector2.ZERO, "action", false,
			{"scale": 0.5, "fx_role": "awaken_cast"})
	elif skull_id == "z003" and n == "skill06":
		fx.release(fx.world_skill_spine)
		fx.world_skill_spine = fx.world("E100006", global_position + Vector2(0.0, -64.0), "action", true,
			{"scale": 0.35, "center": true, "fx_role": "world_skill"})
		fx.world_skill_left = 5.0
	elif skull_id == "z003" and n == "skill10":
		fx.silver_awaken_ready = false
	elif skull_id == "z003" and n == "sky_skill18_02":
		# 人物标准高 128，太极居中后半高约 167；-310 可让其下沿留在头顶上方。
		fx.skill_spine = fx.attach("E100105", Vector2(0.0, -310.0), "action", true,
			{"center": true, "fx_role": "skill"})
	fx.sync_persistent(state == State.DEAD)


func _exit_tree() -> void:
	if fx != null:
		fx.clear_stop_targets()
		fx.release(fx.world_skill_spine)


func _process(delta: float) -> void:
	if _pose_mixer == null or _anim_state == null:
		return
	# 时停期间冻结骨骼推进，与 Boss 的 sprite 停帧一致
	if pvp_mode and _pvp_stop_time > 0.0:
		return
	var step := delta
	if not _pending_anim.is_empty():
		var entry = _anim_state.call("set_animation", _pending_anim, _pending_loop, 0)
		if _pending_speed != 1.0 and entry != null and entry.has_method("set_time_scale"):
			entry.call("set_time_scale", _pending_speed)
		for queued in _pending_queue:
			_anim_state.call("add_animation", queued["anim"], 0.0, queued["loop"], 0)
		_pending_anim = ""
		_pending_queue.clear()
		step = 0.0 # 新轨道先应用，再恢复旧姿势；不把未补偿的第 0 帧送去渲染
	_pose_mixer.update(step)


func _physics_process(delta: float) -> void:
	if net_puppet or pvp_frozen:
		return
	_pvp_status_tick(delta)
	# 时停：完全静止（不跑重力/状态机/技能计时），只保留计时本身
	if pvp_mode and _pvp_stop_time > 0.0:
		velocity = Vector2.ZERO
		return
	fx.tick(delta, state == State.DEAD)
	if _saint_immune():
		_clear_saint_debuffs()
	_mo_ting_burn_tick(delta)
	_fen_ding_burn_tick(delta)
	_ming_zhong_vulnerable_time = maxf(0.0, _ming_zhong_vulnerable_time - delta)
	var had_seal := _passive_seal_time > 0.0
	_passive_seal_time = maxf(0.0, _passive_seal_time - delta)
	if had_seal and _passive_seal_time <= 0.0:
		_refresh_passive_loadout()
	# 受击与死亡动画不消耗眩晕；起身后再保留完整的操作锁。
	if state != State.HURT and state != State.DEAD:
		_stun_time = maxf(0.0, _stun_time - delta)
	if _mo_ting_grabbed:
		velocity = Vector2.ZERO
		return
	if is_instance_valid(_ming_zhong_holder):
		velocity = Vector2.ZERO
		return
	_ming_zhong_holder = null
	_build_tick(delta)
	_pipa_passive_tick(delta)
	_innate_passive_tick(delta)
	_coyote = maxf(0.0, _coyote - delta)
	_jump_buf = maxf(0.0, _jump_buf - delta)
	_dash_cd = maxf(0.0, _dash_cd - delta)
	_dash_gap = maxf(0.0, _dash_gap - delta)
	_attack_recovery = maxf(0.0, _attack_recovery - delta)
	_hurt_invincible = maxf(0.0, _hurt_invincible - delta)
	_knock_cd = maxf(0.0, _knock_cd - delta)
	_cut_tick(delta) # 割伤是延迟直扣：不吃受击无敌，也不触发受击硬直或阴影
	_bleed_tick(delta) # 普通流血独立计时，与割伤互不合并且不重复进入 hurt
	_jump_seal = maxf(0.0, _jump_seal - delta)
	_dash_seal = maxf(0.0, _dash_seal - delta)
	_cripple_time = maxf(0.0, _cripple_time - delta)
	_lifesteal_cd = maxf(0.0, _lifesteal_cd - delta) # 饮血内置冷却
	_perm_lifesteal_cd = maxf(0.0, _perm_lifesteal_cd - delta)
	_hurt_guard_timer = maxf(0.0, _hurt_guard_timer - delta)
	_hurt_cd_refund_cd = maxf(0.0, _hurt_cd_refund_cd - delta)
	_dash_attack_window = maxf(0.0, _dash_attack_window - delta)
	_o_kill_window = maxf(0.0, _o_kill_window - delta)
	# 金钟罩（镇岳 K 第二段）：8 秒内没挨打就自动散
	if _shield_hits > 0:
		_shield_time = maxf(0.0, _shield_time - delta)
		if _shield_time <= 0.0:
			_shield_hits = 0
			_shield_heal_once()
	_buff_timer = maxf(0.0, _buff_timer - delta) # 觉醒 buff 倒计时
	if _buff_timer <= 0.0:
		_awaken_buff_damage = 0
	# 剑仙觉醒：到点清空剑意层数（层数只在觉醒期内有效）
	_awaken_time = maxf(0.0, _awaken_time - delta)
	if _awaken_time <= 0.0:
		_awaken_stacks = 0
	fx.sync_persistent(state == State.DEAD)
	_stop_buff_timer = maxf(0.0, _stop_buff_timer - delta) # 时停加伤倒计时
	var cd_recovery := delta
	if skull_id == "c013" and hp <= 4 and _form_node("c013_meditation_3"):
		cd_recovery *= 1.2 # 禅定·极：残血时冷却恢复 +20%
	for n in _skill_cds:
		_skill_cds[n] = maxf(0.0, float(_skill_cds[n]) - cd_recovery)
	if is_on_floor():
		_coyote = coyote_time
	if _just("jump"):
		_jump_buf = jump_buffer

	if _stun_time > 0.0 and state != State.HURT and state != State.DEAD:
		velocity.x = move_toward(velocity.x, 0.0, brake * delta)
	elif _pvp_stun_time > 0.0 and state != State.HURT and state != State.DEAD:
		velocity.x = move_toward(velocity.x, 0.0, brake * delta)
	else:
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

	# PVP 定身/减速：定身只锁位移，仍可照常出手；减速按系数削弱水平速度
	if pvp_mode and state != State.DEAD:
		if _pvp_root_time > 0.0:
			velocity.x = 0.0
		elif _pvp_slow_time > 0.0:
			velocity.x *= _pvp_slow_scale

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


## 神伤只跟随当前房间的玩家实体计时；换房自然重置，暂停菜单则随场景树暂停。
func _pipa_passive_tick(delta: float) -> void:
	if skull_id != "z002" or state == State.DEAD or not has_battle_passive("z002_sorrow"):
		return
	_pipa_sorrow_timer -= delta
	if _pipa_sorrow_timer > 0.0:
		return
	_pipa_sorrow_timer = 27.0 if _form_node("z002_grudge_1") else 30.0
	# PVP：全房神伤没有碰撞体，按全屏判定广播一次（伤害由 pvp_rules 结算）
	if pvp_mode:
		_emit_pvp_strike({"damage": 5, "full_screen": true, "both": true, "height": 9999.0, "knockback": 0.0})
	for e in _foes():
		var p := e as Node2D
		if p == null or int(e.get("hp")) <= 0:
			continue
		if not pvp_mode:
			_damage_enemy(p, 5)
		if int(e.get("hp")) > 0 and p.has_method("amplify_debuffs"):
			p.call("amplify_debuffs")
	fx.world("E54061", global_position + Vector2(0.0, -180.0), "action", false,
		{"width": get_viewport().get_visible_rect().size.x, "center": true, "fx_role": "sorrow"})
	FX.spawn(get_tree().current_scene, "telegraph", global_position, {"scale": 2.0, "mod": Color(0.65, 0.38, 0.72, 0.55)})
	_play_sfx("pipa_sorrow")


func _innate_passive_tick(delta: float) -> void:
	_z000_confidence_time = maxf(0.0, _z000_confidence_time - delta)
	if state == State.DEAD:
		return
	if skull_id == "c021" and Run.c021_red_butterfly_used and has_battle_passive("c021_red_butterfly"):
		_red_butterfly_left -= delta
		if _red_butterfly_left <= 0.0:
			_red_butterfly_left += 1.0
			hp -= 1 # 红蝶的生命流失不是敌方攻击，不触发闪避、护盾或受击无敌
			hp_changed.emit(hp, max_hp)
			_spawn_number(1, DMG_COLOR, 130.0)
			if hp <= 0 and not _try_revive(Vector2.ZERO):
				_record_last_hit(null, {}, 0) # 红蝶燃尽不是敌方击杀，不能重演历史最后一次受击
				die()
	if skull_id == "z003" and state != State.DEAD:
		if _stolen("c016_mountain"):
			_stolen_regen_left -= delta
			if _stolen_regen_left <= 0.0:
				_stolen_regen_left += 5.0
				_restore_hp(1)
		if _stolen("c018_bloodthirst") and not _stolen_bloodthirst and hp * 10 < max_hp * 3:
			_stolen_bloodthirst = true
			_spawn_passive_text("嗜血 · 觉醒", Color(0.78, 0.3, 0.38))
		if _stolen("c015a1_flame_bone") and not _stolen_flame_awakened and hp * 2 < max_hp:
			_stolen_flame_awakened = true
			_spawn_passive_text("炎骨 · 觉醒", Color(0.9, 0.38, 0.2))
			FX.spawn(get_tree().current_scene, "fire_pillar", global_position, {"scale": 0.8})
		if _stolen("c008_evil_buddha"):
			for e in _foes():
				if int(e.get("hp")) > 0 and e.has_method("set_evil_buddha_pressure"):
					e.call("set_evil_buddha_pressure", true)
		_stolen_history_time += delta
		_stolen_history.append({"time": _stolen_history_time, "position": global_position})
		while _stolen_history.size() > 1 and float(_stolen_history[1]["time"]) <= _stolen_history_time - 2.0:
			_stolen_history.pop_front()
	if skull_id != "z000" or state == State.DEAD or not has_battle_passive("z000_lady"):
		return
	_z000_lady_timer -= delta
	if _z000_lady_timer > 0.0:
		return
	_z000_lady_timer += 20.0
	_restore_hp(maxi(1, int(ceil(float(max_hp) * 0.1))))
	_z000_confidence_time = 10.0


func _spawn_passive_text(text: String, color: Color) -> void:
	var dn := DAMAGE_NUMBER.new()
	dn.setup(text, color)
	dn.global_position = global_position + Vector2(0, -175)
	_world_add(dn)


func _saint_immune() -> bool:
	return skull_id == "c013" and has_battle_passive("c013_saint")


## 圣僧只免疫负面状态，不免除伤害与倒地；佛陀对倒地的反制另行结算。
func _clear_saint_debuffs() -> void:
	_cuts.clear()
	_cut_casts.clear()
	_clear_bleed()
	clear_fen_ding_burn()
	_mo_ting_burn_stacks = 0
	_mo_ting_burn_time = 0.0
	_jump_seal = 0.0
	_dash_seal = 0.0
	_cripple_time = 0.0
	_room_cd_cursed = false
	_room_cd_uses.clear()
	_ming_zhong_vulnerable_time = 0.0
	_ming_zhong_holy = 0
	_stun_time = 0.0
	_mo_ting_grabbed = false
	_ming_zhong_holder = null
	wu_che_wanted = false
	var refresh := _passive_seal_time > 0.0 or _sui_yue_pressure or not _stolen_passives.is_empty()
	_passive_seal_time = 0.0
	_sui_yue_pressure = false
	_stolen_passives.clear()
	if refresh:
		_refresh_passive_loadout()


func _consume_buddha_guard(amount: int, move: Dictionary) -> bool:
	if skull_id != "c013" or amount != 3 or Run.c013_buddha <= 0 or not has_battle_passive("c013_demon"):
		return false
	var would_knock := _knock_cd <= 0.0 and (bool(move.get("force_knockdown", false)) or (_knock_at < 999 and amount >= _knock_at))
	if not would_knock:
		return false
	Run.c013_buddha -= 1
	var dn := DAMAGE_NUMBER.new()
	dn.setup("佛陀 · 不倒", Color(0.9, 0.75, 0.3))
	dn.global_position = global_position + Vector2(0, -175)
	_world_add(dn)
	return true


# ---------- 各状态逻辑 ----------

func _ground_move(delta: float) -> void:
	var dir := _move_axis()
	if dir != 0.0:
		var target := dir * _move_speed()
		var acc := accel if signf(velocity.x) == dir else turn_accel # 反向转弯给更大加速度，避免"踩住刹车"的粘滞
		facing = 1 if dir > 0.0 else -1
		_apply_facing()
		velocity.x = move_toward(velocity.x, target, acc * delta)
		_set_state(State.RUN)
	else:
		# 松油门立刻重刹，跟动作游戏的手感走——停下比起步快
		velocity.x = move_toward(velocity.x, 0.0, brake * delta)
		_set_state(State.IDLE)
	_footstep_timer = maxf(0.0, _footstep_timer - delta)
	if state == State.RUN and is_on_floor() and absf(velocity.x) > 20.0:
		if _footstep_timer <= 0.0:
			_play_sfx("player_footstep")
			_footstep_timer = 0.32
	else:
		_footstep_timer = 0.0
	_try_jump()
	_try_dash()
	if _just("attack") and not _attack_recovery_active():
		_start_attack(0)
	else:
		_try_skill()


func _air_move(delta: float) -> void:
	var dir := _move_axis()
	if dir != 0.0:
		facing = 1 if dir > 0.0 else -1
		_apply_facing()
		velocity.x = move_toward(velocity.x, dir * _move_speed(), accel * 0.7 * delta)
	else:
		# 空中松油门轻微制动，比地面刹得慢（不锁死空中控制）
		velocity.x = move_toward(velocity.x, 0.0, brake * 0.4 * delta)
	if _just("attack") and not _attack_recovery_active() and _cripple_time <= 0.0:
		if _air_follow > 0.0:
			if skull_id == "z000" and (_own("z000_moon_1") or _form_node("z000_volley_2")):
				_chase_air_target()
				_start_attack(0)
				return
			if skull_id == "z003" and _own("z003_sky_1"):
				_chase_air_target()
				_start_attack(1 if _air_combo_reset else 2)
				_air_combo_reset = false
				return
		elif skull_id == "z003" and _own("z003_sky_1") and not _air_chase_free and _chase_air_target():
			# 踏霄·初：没有挑飞窗口时，每段滞空也允许免费追身一次
			_air_chase_free = true
			_start_attack(1 if _air_combo_reset else 2)
			_air_combo_reset = false
			return
	_try_dash()


func _chase_air_target() -> bool:
	var best: Node2D = null
	var best_dist := 420.0
	for e in _foes():
		var p := e as Node2D
		if p == null or int(e.get("hp")) <= 0:
			continue
		var d := global_position.distance_to(p.global_position)
		if d < best_dist and absf(p.global_position.y - global_position.y) <= 260.0:
			best = p
			best_dist = d
	if best != null:
		global_position = best.global_position + Vector2(-facing * 75.0, 0.0)
		global_position.x = _clamp_battle_x(global_position.x)
		velocity = Vector2.ZERO
		return true
	return false


func _dash_tick(delta: float) -> void:
	_dash_timer -= delta
	velocity = Vector2(facing * _dash_speed_now, 0.0)
	if _dash_timer <= 0.0:
		_set_blink(false) # 闪避全程可穿过敌人，结束后立即恢复碰撞
		var cut := _dash_attack() # 疾刃：冲刺收尾斩身前一刀
		_sword_dash_sweep()
		_dash_gap = 0.5
		_dash_cd = 0.0 if (cut and _dash_attack_refund) else _dash_cd_set * _dash_cd_scale
		velocity.x = facing * _move_speed() * 0.5
		_set_state(State.IDLE if is_on_floor() else State.FALL)


## 游身：闪避结束回身扫身后；极阶把浮空者砸落、地面者挑飞，Boss 只受短破招。
func _sword_dash_sweep() -> void:
	if skull_id != "z000" or not _form_node("z000_wind_2"):
		return
	# PVP：游身回身扫是闪避结束的独立判定，不在普攻/技能命中帧内
	if pvp_mode:
		_emit_pvp_strike({
			"damage": 1 + damage_bonus + _mastery_dmg + _buff_now(),
			"range": 150.0, "height": 100.0, "both": true,
		})
	var did_hit := false
	for e in _foes():
		var p := e as Node2D
		if p == null or int(e.get("hp")) <= 0:
			continue
		var dx: float = p.global_position.x - global_position.x
		var behind := dx != 0.0 and (dx > 0.0) != (facing > 0)
		if not behind or absf(dx) > 150.0 + _radius_of(p) or absf(p.global_position.y - global_position.y) > 100.0:
			continue
		_damage_enemy(p, 1 + damage_bonus + _mastery_dmg + _buff_now() + _target_damage_bonus(p))
		hit_scored()
		if int(e.get("hp")) > 0 and _form_node("z000_wind_3"):
			var boss := p.has_method("stop_tier") and str(p.call("stop_tier")) == "boss"
			var airborne := p.has_method("is_on_floor") and not bool(p.call("is_on_floor"))
			if boss:
				p.call("stun", 0.8)
			elif airborne and p.has_method("slam"):
				p.call("slam")
			else:
				p.call("launch", -facing, 120.0, 430.0)
		did_hit = true
	if did_hit:
		_play_sfx("skill_blade")
		Feel.hitstop(0.05)
		Feel.shake(5.0, 0.15)


## 疾刃（绯刃流派）：冲刺终点斩身前敌人；返回是否命中（供"命中即回满冲刺"判定）
func _dash_attack() -> bool:
	if _dash_attack_dmg <= 0:
		return false
	# PVP：疾刃是冲刺结束后的独立判定，不在普攻/技能命中帧内，需要单独广播
	if pvp_mode:
		_emit_pvp_strike({
			"damage": _dash_attack_dmg + damage_bonus + _buff_now(),
			"range": 130.0, "height": 80.0,
		})
	var did_hit := false
	for e in _foes():
		var p := e as Node2D
		if p == null or int(e.get("hp")) <= 0:
			continue
		var dx: float = p.global_position.x - global_position.x
		var dy: float = absf(p.global_position.y - global_position.y)
		var in_front := dx == 0.0 or (dx > 0.0) == (facing > 0)
		if not in_front or absf(dx) > 130.0 + _radius_of(p) or dy > 80.0:
			continue
		_damage_enemy(p, _dash_attack_dmg + damage_bonus + _buff_now() + _target_damage_bonus(p))
		hit_scored()
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
	if _just("attack"):
		_attack_queued = true
	# 到点结算命中（支持一段动画多次命中，如 atk03 绯刃）
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
		if _move_axis() != 0.0:
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
		var shot_damage := int(atk["damage"]) + damage_bonus + _mastery_dmg + _proj_damage_bonus + _buff_now()
		for i in proj_extra + 1:
			_spawn_projectile(atk["projectile"], shot_damage, "voice_sword_hit", i * 26.0)
		# PVP 近似：远程普攻按发射瞬间的射程与伤害结算
		_emit_pvp_strike({
			"damage": shot_damage,
			"range": float((atk["projectile"] as Dictionary).get("range", 420.0)),
			"height": 140.0, "both": true,
		})
		return
	# 命中段：旧格式是纯秒数（沿用本段统一 damage/range），
	# 新格式是字典（一段动画里多段不同伤害/范围，如梅剑鞭击后接突刺）
	var spec: Dictionary = h if h is Dictionary else atk
	if spec.has("projectile"):
		var spec_damage := int(spec.get("damage", atk.get("damage", 1))) + damage_bonus + _mastery_dmg + _proj_damage_bonus + _buff_now()
		for i in proj_extra + 1:
			_spawn_projectile(spec["projectile"], spec_damage, "voice_sword_hit", i * 26.0)
		_emit_pvp_strike({
			"damage": spec_damage,
			"range": float((spec["projectile"] as Dictionary).get("range", 420.0)),
			"height": 140.0, "both": true,
		})
		return
	var dmg := int(spec.get("damage", atk.get("damage", 1))) + damage_bonus + _mastery_dmg + _attack_damage_bonus + _buff_now()
	var final_attack := _attack_idx == attacks.size() - 1
	if final_attack and ((skull_id == "c021" and _form_node("c021_combo_1")) \
			or (skull_id == "z003" and _form_node("z003_chase_1"))):
		dmg += 1
	if _attack_dodge_bonus:
		dmg += 1 # 无影·初：闪避后的下一次普攻
	var reach := float(spec.get("range", atk.get("range", 100.0))) * range_scale * _attack_range_scale
	var side_any := bool(spec.get("both", atk.get("both", false)))
	# PVP：与 PvE 使用同一套射程/高度/朝向参数，交给 pvp_rules 判定对手是否被扫到
	_emit_pvp_strike({
		"damage": dmg, "range": reach,
		"height": float(spec.get("height", atk.get("height", 70.0))),
		"both": side_any, "path": false,
	})
	var pull := float(spec.get("pull", 0.0)) # 鞭击拉回：命中后把敌人拽到身前这个距离
	if pull > 0.0 and skull_id == "c023" and _form_node("c023_lash_2"):
		pull = 120.0
	var did_hit := false
	var pulled := 0 # 已拉回的敌人数，多目标依次错开 34px 免得叠成一坨
	for e in _foes():
		var p := e as Node2D
		if p == null:
			continue
		# 尸体不结算：怪死了但尸体还在场（dead_min 停留），打上去不该涨连击/触发顿帧
		if int(e.get("hp")) <= 0:
			continue
		var dx: float = p.global_position.x - global_position.x
		var dy: float = absf(p.global_position.y - global_position.y)
		var in_front := dx == 0.0 or (dx > 0.0) == (facing > 0)
		# 纵向容差默认 70（普攻几乎贴地判定），个别招式可用 height 单独放宽/收紧
		var reach_h := float(spec.get("height", atk.get("height", 70.0)))
		# both = 回身横扫：动画把武器甩到身后，前后两侧都算命中，否则"动画打到却没判上"
		# 射程 + 目标受击半径：体型大的 Boss 在身体边缘就能被够到，不用贴到原点
		if not (in_front or side_any) or absf(dx) > reach + _radius_of(p) or dy > reach_h:
			continue
		_damage_enemy(p, dmg + _target_damage_bonus(p))
		hit_scored() # 命中一只算一次连击
		_on_build_hit(p, "attack%d" % _attack_idx)
		# 普攻末段易伤（烬生 J 第三段）：只对仍存活的目标生效
		if spec.has("vulnerable") and int(e.get("hp")) > 0 and p.has_method("apply_vulnerable"):
			var vuln: Dictionary = spec["vulnerable"]
			p.call("apply_vulnerable", float(vuln.get("time", 5.0)), float(vuln.get("ratio", 0.25)))
		if skull_id == "z003" and _attack_idx == 1 and _own("z003_sky_1"):
			_air_follow = 4.0
		# 击飞（银夜段2）：敌人往空中挑起，落地硬直；打死的尸体不再挑
		var lc: Dictionary = spec.get("launch", {})
		var silver_slam := skull_id == "z003" and _attack_idx == 2 and not is_on_floor() and _own("z003_sky_2")
		var sword_slam := skull_id == "z000" and _attack_idx == 3 and not is_on_floor() and _form_node("z000_volley_3")
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
				p.call("root", 0.5) # 缠枝·初：即使没撞到近敌，被拉者也必定定身
				for other_e in _foes():
					var other := other_e as Node2D
					if other == null or other == p or int(other_e.get("hp")) <= 0:
						continue
					if other.global_position.distance_to(p.global_position) <= _radius_of(p) + _radius_of(other) + 45.0:
						p.call("root", 1.2)
						other.call("root", 1.2)
						break
			pulled += 1
		did_hit = true
	if did_hit:
		if final_attack:
			_try_unification()
		_play_sfx(str(spec.get("sfx", "voice_sword_hit")))
		Feel.hitstop(0.045) # 命中一僵，普攻比技能轻
		Feel.shake(4.0, 0.13)
		if final_attack and skull_id == "c021" and _form_node("c021_combo_3") and not _final_wave_done:
			_final_wave_done = true
			_combo_finish_wave()


## 连刃·极：末段首次命中追加一次双向范围斩，固定 1 伤。
func _combo_finish_wave() -> void:
	# PVP：追加斩独立于技能命中帧，必须单独广播一次判定，否则对手永远收不到这段伤害
	if pvp_mode:
		_emit_pvp_strike({"damage": 1, "range": 240.0, "height": 120.0, "both": true})
	for e in _foes():
		var p := e as Node2D
		if p == null or int(e.get("hp")) <= 0:
			continue
		if absf(p.global_position.x - global_position.x) <= 240.0 + _radius_of(p) \
				and absf(p.global_position.y - global_position.y) <= 120.0:
			_damage_enemy(p, 1)
			hit_scored()


## 所有玩家直伤统一携带真实来源；魅惑减伤在受击方结算，投射物也走同一入口。
## 返回实际扣血，供八音总伤与测试核对，不靠 source_x 猜测攻击者身份。
func _damage_enemy(target: Node, amount: int) -> int:
	if target == null or not is_instance_valid(target) or amount <= 0 or int(target.get("hp")) <= 0:
		return 0
	# PVP：伤害只在 pvp_rules.handle_strike 里按对战系数结算一次；
	# 这里被 _foes() 遍历到对手玩家时只负责挂状态，绝不重复扣血。
	if pvp_mode and ("pvp_mode" in target) and bool(target.get("pvp_mode")):
		return 0
	amount += Achievements.bonus_int("damage") # 称号加伤：统一在伤害入口加，覆盖普攻/技能/持续段
	if _stolen_divine and _stolen("c032_divine_favor"):
		return _stolen_holy_hit(target)
	if _stolen("c035_shadow"):
		var target_facing = target.get("facing")
		if target_facing != null and (global_position.x - (target as Node2D).global_position.x) * float(target_facing) < 0.0:
			amount *= 2 # 阴影只放大玩家直接伤害，目标自身的持续伤害不会经过这里
	if target.has_method("damage_taken_scale"):
		var taken_scale := float(target.call("damage_taken_scale"))
		if taken_scale > 1.0:
			amount = maxi(1, int(round(float(amount) * taken_scale))) # 易伤统一在攻击方换算，敌人内部不再重复放大
	# 敌方防御：按人数表折算玩家直伤（未开局为 1.0，不影响单测/斗蛐蛐）
	if target.is_in_group("enemies"):
		var defend := Run.enemy_taken_scale()
		if defend < 1.0:
			amount = maxi(1, int(round(float(amount) * defend)))
	if skull_id == "z001" and _z001_fury > 0:
		amount += _z001_fury # 战意：每层追加等量焚烧伤害，不参与敌方减伤倍率
	var before := int(target.get("hp"))
	if target.has_method("take_damage_from"):
		target.call("take_damage_from", amount, self)
	else:
		target.call("take_damage", amount, global_position.x)
	var dealt := maxi(0, before - int(target.get("hp")))
	if dealt > 0:
		_on_innate_damage(target, dealt)
		Achievements.event("damage_dealt", dealt)
		Achievements.max_event("max_hit", dealt)
	return dealt


func _stolen_holy_hit(target: Node) -> int:
	var id := target.get_instance_id()
	_stolen_holy[id] = int(_stolen_holy.get(id, 0)) + (2 if _buff_timer > 0.0 else 1)
	var stacks := int(_stolen_holy[id])
	var p := target as Node2D
	if p != null:
		var dn := DAMAGE_NUMBER.new()
		dn.setup("圣光 · %d/36" % stacks, Color(0.95, 0.82, 0.38))
		dn.global_position = p.global_position + Vector2(0, -160)
		_world_add(dn)
	_stolen_war_god_hit()
	if stacks >= 36 and int(target.get("hp")) > 0:
		var lethal := int(target.get("hp"))
		if target.has_method("take_damage_from"):
			target.call("take_damage_from", lethal, self)
		else:
			target.call("take_damage", lethal, global_position.x)
	return 0


## 固有与夺取被动只响应真实扣血：被格挡、无敌或零伤命中不会累计。
func _on_innate_damage(target: Node, dealt: int) -> void:
	if skull_id == "z001" and dealt > 0 and int(target.get("hp")) <= 0:
		_z001_on_kill()
	if skull_id == "c013" and has_battle_passive("c013_demon"):
		Run.c013_damage_hits += 1
		if Run.c013_damage_hits % 4 == 0:
			if Run.c013_buddha >= C013_BUDDHA_MAX:
				# 佛陀已满 3 层：不再叠全伤，改为恢复 1 点生命。
				_restore_hp(1)
			else:
				Run.c013_buddha += 1
				var dn := DAMAGE_NUMBER.new()
				dn.setup("佛陀 %d" % Run.c013_buddha, Color(0.9, 0.75, 0.3))
				dn.global_position = global_position + Vector2(0, -165)
				_world_add(dn)
	if skull_id == "c023" and Run.active and has_battle_passive("c023_ink_plum"):
		Run.c023_ink_bonus += 1
	if skull_id == "z000" and has_battle_passive("z000_sword_sect") and target.has_method("apply_sword_sect"):
		target.call("apply_sword_sect")
	if skull_id != "z003":
		return
	if _stolen_bloodthirst and _stolen("c018_bloodthirst"):
		_restore_hp(1)
	if _stolen("c032_war_god"):
		_stolen_war_god_hit()
	if _stolen("c009_madness"):
		max_hp += 1
		hp = max_hp
		if Run.active:
			Run.z003_madness_hp += 1
			Run.max_hp = max_hp
			Run.set_slot_hp(input_slot, hp)
		hp_changed.emit(hp, max_hp)
	if _stolen("c012_sword_intent"):
		var echo := _stolen_sword_intent >= 3
		if not echo:
			_stolen_sword_intent += 1
			_spawn_passive_text("剑意凝华" if _stolen_sword_intent >= 3 else "剑意 %d/3" % _stolen_sword_intent, Color(0.55, 0.78, 0.82))
			if _stolen_sword_intent >= 3:
				_spawn_stolen_sword_clone()
		elif is_instance_valid(_stolen_sword_clone) and int(target.get("hp")) > 0:
			# 凝华镜像复写本次直伤；不再回到玩家命中钩子，避免无限递归与重复叠层。
			if target.has_method("take_damage_from"):
				target.call("take_damage_from", dealt, self)
			else:
				target.call("take_damage", dealt, global_position.x)
	if int(target.get("hp")) > 0:
		if _stolen("c017_brute") and target.has_method("knock_back"):
			var dir := signf((target as Node2D).global_position.x - global_position.x)
			target.call("knock_back", int(dir if dir != 0.0 else facing), 110.0, 0)
		if _stolen("c015a1_burning_heart") and target.has_method("apply_player_burn"):
			target.call("apply_player_burn", self)


# ---------- 烬生·赤烬：战狂 / 燃尽 ----------

func _z001_add_fury() -> void:
	if skull_id != "z001" or not has_battle_passive("z001_war_fury"):
		return
	_z001_fury += 1
	_spawn_passive_text("战意 ×%d" % _z001_fury, Color(0.95, 0.55, 0.25))
	FX.spawn(get_tree().current_scene, "ink_hit", global_position + Vector2(0, -120),
		{"scale": 0.4, "mod": Color(1.0, 0.55, 0.25, 0.85)})


func _z001_on_kill() -> void:
	if skull_id != "z001" or not has_battle_passive("z001_war_fury"):
		return
	_z001_kill_acc += 1
	if _z001_kill_acc >= 5:
		_z001_kill_acc -= 5
		_z001_add_fury()


func _z001_on_hit_taken() -> void:
	if skull_id != "z001" or not has_battle_passive("z001_war_fury"):
		return
	_z001_hit_acc += 1
	if _z001_hit_acc >= 5:
		_z001_hit_acc -= 5
		_z001_add_fury()


## 致命伤：生命归零但不死亡，进入燃尽。返回 true 表示这次致命伤已被燃尽接管。
func _z001_enter_burnout() -> bool:
	if skull_id != "z001" or pvp_mode or _z001_burnout or not has_battle_passive("z001_burnout"):
		return false
	_z001_burnout = true
	hp = 0
	hp_changed.emit(hp, max_hp)
	_spawn_passive_text("燃尽", Color(1.0, 0.55, 0.25))
	FX.spawn(get_tree().current_scene, "ink_hit", global_position + Vector2(0, -70),
		{"scale": 0.7, "mod": Color(1.0, 0.5, 0.2, 0.9)})
	_play_sfx("voice_skill_cast")
	return true


## 燃尽期间受到的伤害改为扣除生命上限；上限清零才真正死亡。
func _z001_burnout_take_damage(amount: int) -> void:
	if amount <= 0 or state == State.DEAD:
		return
	max_hp = maxi(0, max_hp - amount)
	hp = 0
	if Run.active:
		Run.set_slot_hp(input_slot, hp)
		if input_slot == 0:
			Run.max_hp = max_hp
	hp_changed.emit(hp, max_hp)
	_z001_on_hit_taken()
	var dn := DAMAGE_NUMBER.new()
	dn.setup("上限 -%d" % amount, Color(1.0, 0.6, 0.25))
	dn.global_position = global_position + Vector2(0, -160)
	_world_add(dn)
	_spawn_number(amount, Color(1.0, 0.5, 0.2), 130.0)
	_play_sfx("hit_fist")
	Feel.hitstop(0.04)
	Feel.shake(5.0, 0.16)
	if max_hp <= 0:
		die()


## 燃尽期间获得回血：立即退出燃尽，后续伤害重新扣生命。
func _z001_exit_burnout() -> void:
	if not _z001_burnout:
		return
	_z001_burnout = false
	_spawn_passive_text("余烬复燃", Color(1.0, 0.72, 0.35))


func _spawn_stolen_sword_clone() -> void:
	if is_instance_valid(_stolen_sword_clone):
		return
	var clone = load("res://scenes/enemies/c012_elite.tscn").instantiate()
	clone.set("_is_sword_clone", true)
	clone.set("_sword_player_clone", true)
	clone.set("_sword_owner", self)
	clone.position = global_position + Vector2(-facing * 58.0, 0.0)
	clone.set("facing", facing)
	if not _world_add(clone):
		return
	_stolen_sword_clone = clone
	clone.call("_sword_sync_player_action")


func _sync_stolen_sword_clone() -> void:
	if is_instance_valid(_stolen_sword_clone):
		_stolen_sword_clone.call("_sword_sync_player_action")


func _dismiss_stolen_sword_clone() -> void:
	if is_instance_valid(_stolen_sword_clone):
		_stolen_sword_clone.queue_free()
	_stolen_sword_clone = null


func _stolen_war_god_hit() -> void:
	for n in _skill_cds:
		_skill_cds[n] = maxf(0.0, float(_skill_cds[n]) - 3.0)
	_stolen_block += 2


## 目标的受击半径：体型越大挨打面越大；没有该属性的测试替身按 30 兜底
func _radius_of(e) -> float:
	var r = e.get("body_radius")
	return float(r) if r != null else 30.0


## 通用身体锚定特效的体型倍率：以常规体型（受击半径 30）为 1.0，不按具体特效写死尺寸。
## 形态表可用 fx_scale 显式覆盖；与受击半径同源的"体积"决定金钟罩/觉醒/复活特效大小。
func _body_fx_scale() -> float:
	if _fx_scale > 0.0:
		return _fx_scale
	return maxf(0.25, body_radius / 30.0)


## 目标状态加伤：毒梅看中毒，逐影看击飞；投射物命中时也会查询同一入口。
func _target_damage_bonus(p: Node2D) -> int:
	var bonus := 0
	if skull_id == "c023" and _form_node("c023_venom_2"):
		var poison_left = p.get("_poison_time")
		if poison_left != null and float(poison_left) > 0.0:
			bonus += 1
	if skull_id == "z003" and _form_node("z003_chase_2"):
		var enemy_state = p.get("state")
		if enemy_state != null and int(enemy_state) == 6: # c016.State.FLY
			bonus += 1
	return bonus


## 限时加伤：觉醒、完美闪避、血饮与时停共用"取最高"；条件修炼与首房强化另行叠加。
func _buff_now() -> int:
	# 邪佛只封普通增益；觉醒动作、剑意与银夜 P 的觉醒房强化始终保留。
	if _passives_disabled():
		return _room_awaken_damage + _awaken_stacks + (_awaken_buff_damage if _buff_timer > 0.0 else 0)
	var v := _buff_damage if _buff_timer > 0.0 else 0
	if _stop_buff_timer > 0.0:
		v = maxi(v, _stop_buff_damage)
	var total := v + _awaken_stacks + _room_awaken_damage
	if _stolen("c012_sword_intent"):
		total += _stolen_sword_intent
	if skull_id == "c021":
		if _form_node("c021_combo_2") and Score.combo >= 10:
			total += 1
		if _form_node("c021_shadow_3") and not is_on_floor():
			total += 1
	if skull_id == "c013" and has_battle_passive("c013_demon"):
		total += Run.c013_buddha
	if skull_id == "z000" and _z000_confidence_time > 0.0 and has_battle_passive("z000_lady"):
		total += 1
	if Meta.shop_level("start_edge") > 0 and Run.room_index == 0 and Run.depth == 1:
		total += 1 # 初锋：每局首个普通房全部伤害 +1
	return total


## 命中计数：连击数 +（剑仙觉醒期间）剑意叠层。玩家造成的每次命中都走这里
func hit_scored() -> void:
	Score.add_hit()
	if skull_id == "z000" and _awaken_time > 0.0 and _awaken_stacks < 5:
		_awaken_stacks += 1


## 把敌人直接牵到指定横坐标；所有"拉回/牵引"共用同一个站位规则。
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


## 技能效果作用目标：PvE 为 enemies 组；PVP 为另一名对手玩家。
## 目标抽象只负责"挂状态"，PVP 伤害仍由 pvp_rules 统一结算（见 _damage_enemy 的去重）。
func _foes() -> Array:
	if pvp_mode:
		var out: Array = []
		for n in get_tree().get_nodes_in_group("pvp_players"):
			if n == self or not is_instance_valid(n):
				continue
			if int(n.get("hp")) <= 0:
				continue
			out.append(n)
		return out
	return get_tree().get_nodes_in_group("enemies")


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


## 搬山·初：被击退/击飞的敌人在落地那一刻定身，没撞到人也有控制收益。
func on_knock_landing(victim: Node2D) -> void:
	if skull_id != "c013" or not _own("c013_mountain_1"):
		return
	if is_instance_valid(victim) and int(victim.get("hp")) > 0:
		victim.call("root", 0.6)


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
	for e in _foes():
		var p := e as Node2D
		if p == null or p == exclude or int(e.get("hp")) <= 0:
			continue
		if absf(p.global_position.x - pos.x) > 180.0 + _radius_of(p) or absf(p.global_position.y - pos.y) > 150.0:
			continue
		var is_boss: bool = e.has_method("stop_tier") and str(e.call("stop_tier")) == "boss"
		if stun_only or is_boss:
			p.call("stun", 1.5 if not is_boss else 0.8)
		else:
			p.call("launch", 1 if p.global_position.x >= pos.x else -1, 130.0, 430.0)
	FX.spawn(get_tree().current_scene, "ink_hit", pos + Vector2(0, -40), {"scale": 1.0})
	Feel.shake(7.0, 0.2)


## 每次近战/技能命中后的流派钩子：标记、回收、破招与空中派生都从这里进入。
func _on_build_hit(p: Node2D, move_id: String) -> void:
	if int(p.get("hp")) <= 0:
		# 砸落类招式打死目标时尸体不会再起跳，落点冲击要当场结算，否则踏霄·续/极整段失效
		if skull_id == "z003" and move_id == "attack2" and not is_on_floor() and _own("z003_sky_2"):
			_slam_aoe(p.global_position, true)
			if _own("z003_sky_3"):
				velocity.y = -520.0
				state = State.JUMP
				_air_follow = 4.0
				_air_combo_reset = true
		return
	var id := p.get_instance_id()
	if skull_id == "c021":
		if move_id == "skill01" and _own("c021_feather_1"):
			# 绯羽·初：不再剥掉流血，改为保留流血并额外凝一羽——单买也有净收益
			if int(p.get("_bleed_stacks")) > 0 and p.has_method("apply_bleed"):
				p.call("apply_bleed", 1)
			_feathers = mini(3, _feathers + 1)
			var dn := DAMAGE_NUMBER.new()
			dn.setup("绯羽 %d/3" % _feathers, Color(0.9, 0.55, 0.55))
			dn.global_position = global_position + Vector2(0, -150)
			_world_add(dn)
	elif skull_id == "c023":
		var poison_left = p.get("_poison_time")
		if move_id.begins_with("attack") and _own("c023_plum_1") and poison_left != null and float(poison_left) > 0.0:
			var mark: Dictionary = _plum_marks.get(id, {"target": p, "hits": 0, "marked": false})
			mark["hits"] = mini(2, int(mark["hits"]) + 1)
			var was_marked := bool(mark["marked"])
			mark["marked"] = int(mark["hits"]) >= 2
			_plum_marks[id] = mark
			if mark["marked"] and not was_marked:
				# 梅烙·初：结烙瞬间就要有可见收益，否则单买等于没选
				if p.has_method("take_damage_from"):
					p.call("take_damage_from", 1, self)
				var dn := DAMAGE_NUMBER.new()
				dn.setup("梅烙", Color(0.92, 0.62, 0.66))
				dn.global_position = p.global_position + Vector2(0, -60)
				_world_add(dn)
		if move_id == "skill02" and _own("c023_plum_2") and bool(_plum_marks.get(id, {}).get("marked", false)):
			_plum_marks.erase(id)
			p.call("root", 2.0)
			for e in _foes():
				var other := e as Node2D
				if other != null and other != p and int(e.get("hp")) > 0 and other.global_position.distance_to(p.global_position) <= 280.0:
					other.call("apply_poison", 4.0)
			if _own("c023_plum_3"):
				_spawn_plum_zone(p.global_position)
	elif skull_id == "c013":
		if move_id.begins_with("attack") and _own("c013_mountain_2"):
			var stun_left = p.get("_stun_timer")
			if stun_left != null and float(stun_left) > 0.0:
				p.call("knock_back", facing, 480.0, 1)
	elif skull_id == "z000":
		if move_id == "atk04" and _form_node("z000_edge_1"):
			_pull_enemy(p, global_position.x + facing * 105.0)
			if _form_node("z000_edge_2"):
				_edge_k_hits[id] = int(_edge_k_hits.get(id, 0)) + 1
				if int(_edge_k_hits[id]) >= 3 and not _k_sealed.has(id):
					_k_sealed[id] = p
					p.call("stun", 1.5) # 封招：三段打全立即断招，并留下一次 L 引爆机会
					var dn := DAMAGE_NUMBER.new()
					dn.setup("封脉", Color(0.85, 0.72, 0.42))
					dn.global_position = p.global_position + Vector2(0, -140)
					_world_add(dn)
		if move_id == "skill02-" and _k_sealed.has(id):
			_k_sealed.erase(id)
			p.call("stun", 1.2)
			if _form_node("z000_edge_3"):
				for e in _foes():
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
				var entry: Dictionary = _seal_targets.get(id, {"target": p})
				entry["target"] = p
				_seal_targets[id] = entry
				# 惊鸿谱·初：留诀当场补 1 伤并飘字，否则单买只有一段看不见的记录
				if p.has_method("take_damage_from"):
					p.call("take_damage_from", 1, self)
				var dn := DAMAGE_NUMBER.new()
				dn.setup("%s 诀" % seal, Color(0.9, 0.75, 0.3))
				dn.global_position = p.global_position + Vector2(0, -150)
				_world_add(dn)
		var final_slam := move_id == "attack3" and not is_on_floor() and _form_node("z000_volley_3")
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
				# 漏刻·初：留刻当场补 1 伤并飘字，时停中才有即时收益
				if p.has_method("take_damage_from"):
					p.call("take_damage_from", 1, self)
				var dn := DAMAGE_NUMBER.new()
				dn.setup("刻 %d/3" % (entry["moves"] as Array).size(), Color(0.62, 0.82, 0.9))
				dn.global_position = p.global_position + Vector2(0, -140)
				_world_add(dn)
			_time_marks[id] = entry
		if move_id == "skill11" and _own("z003_returning_1") and not _outbound_hits.has(id):
			_outbound_hits[id] = true
			# 去来·初：去程留痕并补 1 伤，返程才有"记住"的实感
			if p.has_method("take_damage_from"):
				p.call("take_damage_from", 1, self)
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
	for e in _foes():
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
	_world_add(dn)


func _skill_tick(delta: float) -> void:
	_skill_timer -= delta
	if _mix_restore:
		# 上一帧的瞬移切换已经随渲染应用完毕，恢复默认混合（下一帧物理 tick 时渲染侧必然已跑过）
		_mix_restore = false
		sprite.get("skeleton_data_res").call("set_default_mix", 0.0 if _pose_mixer != null else 0.2)
	var cfg: Dictionary = _skill_runtime if not _skill_runtime.is_empty() else skill_config[_skill_name]
	if _skill_cancel_ready and _dash_cd <= 0.0 and _dash_gap <= 0.0 and _just("dash"):
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
	while not _skill_audio_events.is_empty() and t >= float(_skill_audio_events[0].get("at", 0.0)):
		var event: Dictionary = _skill_audio_events.pop_front()
		_play_sfx(str(event.get("sfx", "")))
	# 根骨跟随（root_motion）：动画把根骨挪了多远，节点就跟着挪多远，再用 sprite 反向抵消同一份量——
	# 画面看到的动作与原来一模一样，但人物真的走到了动画终点（命中判定 / 投射物出手点也都在正确位置）
	if _skill_root_follow and _root_bone != null:
		var off := _root_offset()
		# 根骨位移同样不能越过地图墙：夹住后把 sprite 补偿量按实际落点重算，画面不抖
		var px := _clamp_battle_x(_skill_root_x + off)
		sprite.position.x = -(px - _skill_root_x)
		global_position.x = px
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
		global_position.x = _clamp_battle_x(global_position.x + facing * _skill_teleport)
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
		# 位置直接由根骨驱动；只有显式配置 phase 的纯机动技穿过敌人，普通根位移技不穿。
		_set_blink(bool(cfg.get("phase", false)))
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
		var stop_dur := float(stop.get("mob", 10.0)) + _stop_bonus # 时停·初：全档位 +0.25 秒
		for e in _foes():
			if int(e.get("hp")) <= 0:
				continue
			var tier := str(e.call("stop_tier")) if e.has_method("stop_tier") else "mob"
			var dur := float(stop.get(tier, 10.0)) + _stop_bonus
			if ("pvp_mode" in e) and bool(e.get("pvp_mode")):
				# 敌方玩家按 BOSS 档位处理（stop_tier 返回 boss），并把施法者交给对方，
				# 让时停自然结束时能回报 on_time_stop_end（止时·极的定身与尾伤）。
				e.call("time_stop", dur, self)
			else:
				e.call("time_stop", dur)
			if e is Node2D:
				fx.attach_stop_target(e)
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
		if skull_id == "z003" and _skill_name == "skill10" and not fx.silver_awaken_ready:
			fx.silver_awaken_ready = true
			fx.world("E100186", global_position + Vector2(0.0, -150.0), "action", false,
				{"z": -1, "center": true, "fx_role": "awaken_cast"})
			fx.sync_persistent(state == State.DEAD)
		# 自带位移动画兜底：正常尾声已提前 0.12s 瞬移+切 stand（见上），这里只兜底位置
		if _skill_teleport > 0.0:
			global_position.x = _clamp_battle_x(global_position.x + facing * _skill_teleport)
			_skill_teleport = 0.0
		# 收招兜底：命中段 at 略晚于动画时长时（镇岳定山 at=3.12 > 3.05），
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
			fx.sync_persistent(state == State.DEAD)
			if skull_id == "z002":
				_pipa_awaken_count += 1
				_pipa_o_used = false
				_restore_hp(int(ceilf((max_hp - hp) * 0.5)))
		if skull_id == "z000" and _skill_name == "skill04":
			if _own("z000_moon_1"):
				_air_follow = 4.0
			elif _form_node("z000_volley_2"):
				_air_follow = 2.0
		_skill_cancel_ready = false
		_parry_ready = false
		_set_state(State.IDLE if is_on_floor() else State.FALL)


func _set_blink(on: bool) -> void:
	if on == _blink_active:
		return
	_blink_active = on
	# 穿怪豁免只针对 PvE 敌人：PVP 中双方不应互相穿透
	for e in get_tree().get_nodes_in_group(&"enemies"):
		if not e is PhysicsBody2D:
			continue
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
		global_position.x = _clamp_battle_x(_skill_root_x + off)
		_root_bone.call("set_x", _root_bone_base)
	if sprite:
		sprite.position = Vector2.ZERO


## 地图内可站立 x 范围：场景在 _ready 写入 battle_width；未标注时按 1920 兜底。
func _battle_width() -> float:
	var scene := get_tree().current_scene
	if scene != null and scene.has_meta("battle_width"):
		return float(scene.get_meta("battle_width"))
	return DEFAULT_BATTLE_W


func _clamp_battle_x(x: float) -> float:
	var pad := maxf(24.0, body_radius)
	return clampf(x, pad, _battle_width() - pad)


func _deal_skill_hit(h: Dictionary) -> void:
	var low_hp_skill := skull_id == "c021" and _form_node("c021_dance_2") and hp * 2 <= max_hp
	if bool(h.get("mind_detonate", false)):
		_deal_mind_detonate()
		return
	if bool(h.get("charm", false)):
		_deal_charm()
		return
	# 远程技能：发投射物，命中由投射物自己结算
	if h.has("projectile"):
		var shot_damage := _stolen_skill_damage(int(h["damage"]) + damage_bonus + _proj_damage_bonus + _buff_now() + int(low_hp_skill))
		var shot_spec: Dictionary = (h["projectile"] as Dictionary).duplicate(true)
		if skull_id == "z000" and _skill_name == "skill04":
			shot_spec["first_damage"] = shot_damage
			shot_spec["later_damage"] = maxi(1, shot_damage - 3)
		if skull_id == "c021" and _skill_name == "skill02-cankao" and _own("c021_feather_2") and _feathers > 0:
			shot_spec["split"] = int(shot_spec.get("split", 0)) + _feathers
			_feathers = 0
		# PVP 近似：远程技能按发射瞬间的射程与伤害结算，不追踪飞行中的投射物
		_emit_pvp_strike({
			"damage": shot_damage,
			"range": float(shot_spec.get("range", 420.0)),
			"height": 140.0, "both": true,
		})
		for i in proj_extra + 1:
			_spawn_projectile(shot_spec, shot_damage, str(h.get("sfx", "")), i * 26.0)
		var shot_heal := h.duplicate(true)
		if skull_id == "z002" and _skill_name == "skill03" and _form_node("z002_echo_3") and shot_heal.has("heal"):
			shot_heal["heal"] = int(shot_heal["heal"]) + 1
		_apply_skill_heal(shot_heal) # 黍离在曲终发音时回血，不要求魔音必须命中
		return
	# 免伤护罩段（镇岳 K 第二段）：不打伤害，给自己挂金钟罩
	if h.has("self_shield"):
		_apply_self_shield(h["self_shield"])
	# 纯回血段（镇岳定山砸地）：不打伤害，只结算回血与砸地音
	if not h.has("damage"):
		_apply_skill_heal(h)
		return
	var did_hit := false
	var dmg := _stolen_skill_damage(int(h["damage"]) + damage_bonus + _buff_now() + int(_skill_damage_mod.get(_skill_name, 0)) + int(low_hp_skill))
	if skull_id == "z002" and _skill_name == "skill13-" and _awaken_time > 0.0 and _form_node("z002_charm_2"):
		dmg += 1 # 缚心·续：众生同狂全房伤害 +1
	if skull_id == "c023" and _skill_name == "skill02":
		dmg += _c023_frost_bonus # 霜梅只加强本房 K 的唯一尾鞭，持续段不受影响
		if _form_node("c023_lash_3"):
			dmg += 1 # 鞭势·极
	# 觉醒强化（银夜 P）：释放即加持本房间全伤 +N，与是否命中无关；一房一次，再放只剩伤害
	var rb: Dictionary = h.get("room_buff", {})
	if not rb.is_empty() and not _room_buff_used:
		_room_buff_used = true
		_room_awaken_damage += int(rb.get("damage", 0))
		var bn := DAMAGE_NUMBER.new()
		bn.setup("觉醒·全伤+%d" % int(rb.get("damage", 0)), Color(0.9, 0.75, 0.3)) # 金字提示
		bn.global_position = global_position + Vector2(0, -160)
		_world_add(bn)
	var full := bool(h.get("full_screen", false)) # 全屏伤害（银夜 P 觉醒）：无视距离/朝向/高度
	var skill_range := float(h.get("range", 0.0)) * range_scale
	if skull_id == "c013" and _skill_name == "skill01":
		skill_range *= _skill_range_scale # 震岳·初：只放大 K
		fx.world("E54063", global_position, "action1", false,
			{"width": skill_range * 2.0, "center": true, "fx_role": "skill_hit"})
	elif skull_id == "c013" and _skill_name == "skill03":
		# L 金刚怒目：落点石柱按伤害范围横向适配，底部贴地不陷进地面
		fx.world("E53201", global_position + Vector2(facing * skill_range, 0.0), "action", false,
			{"width": skill_range, "bottom": true, "flip": facing < 0, "fx_role": "skill_hit"})
	elif skull_id == "z000" and _skill_name == "skill02-":
		# L 月华斩末端：在挥剑落点从地面喷出火焰。固定缩放保证整段动画都能完整显示，
		# 底部对齐让火头始终贴住脚底水平线，不随 bounds 变化上下漂移。
		fx.world("E54145", global_position + Vector2(facing * skill_range * 0.72, 0.0), "action", false,
			{"scale": 0.2, "bottom": true, "offset": Vector2(0.0, 22.0), "flip": facing < 0, "fx_role": "skill_hit"})
	if full and skull_id == "z003" and _skill_name == "sky_skill18_02":
		fx.fullscreen("E54012", "action3")
	# PVP：技能命中帧只报一次参数（射程已含 c013 震岳初的额外放大），由 pvp_rules 结算
	_emit_pvp_strike({
		"damage": dmg, "range": skill_range,
		"height": float(h["height"]),
		"both": bool(h.get("both", false)),
		"full_screen": full, "path": bool(h.get("path", false)),
		"start_x": _skill_start_x,
	})
	for e in _foes():
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
				# both = 回身横扫（镇岳狼牙棒、绯刃回身刺）：动画扫到身后也照样判定
				hit_ok = (in_front or bool(h.get("both", false))) and absf(dx) <= skill_range + _radius_of(p)
		if hit_ok:
			if skull_id == "z003" and _skill_name == "skill11":
				fx.world("E54012", p.global_position + Vector2(0.0, -60.0), "action1", false,
					{"scale": 0.35, "flip": facing < 0, "fx_role": "skill_hit"})
			if skull_id == "z003" and _skill_name == "skill11" and _form_node("z003_return_3") and _buff_timer > 0.0:
				_o_kill_window = 0.3 # 必须在扣血前开窗口，直接击杀也会归给本次 O
			# 烬生 O：路径上的普通小怪直接秒杀，精英 / Boss 固定 8 伤
			if h.has("dash_kill") and not (pvp_mode and ("pvp_mode" in p) and bool(p.get("pvp_mode"))):
				var tier := str(p.call("stop_tier")) if p.has_method("stop_tier") else "mob"
				var dash_before := int(p.get("hp"))
				var fixed := maxi(1, dash_before) if tier != "boss" and tier != "elite" \
					else int((h["dash_kill"] as Dictionary).get("elite_damage", 8)) + _z001_fury
				if p.has_method("take_damage_from"):
					p.call("take_damage_from", fixed, self)
				else:
					p.call("take_damage", fixed, global_position.x)
				var dealt_dash := maxi(0, dash_before - int(p.get("hp")))
				_skill_damage_total += dealt_dash
				if dealt_dash > 0 and int(p.get("hp")) <= 0:
					_z001_on_kill()
				hit_scored()
				FX.spawn(get_tree().current_scene, "speedline", p.global_position + Vector2(0, -60),
					{"scale": 0.6, "flip": facing < 0})
				did_hit = true
				continue
			var hit_damage := dmg
			# 烬生 L：斩杀——按目标已损生命追加 20%（Boss 10%）
			if h.has("execute"):
				var ex: Dictionary = h["execute"]
				var is_boss := p.has_method("stop_tier") and str(p.call("stop_tier")) == "boss" \
					and not (pvp_mode and ("pvp_mode" in p) and bool(p.get("pvp_mode")))
				var ratio := float(ex.get("boss", 0.1)) if is_boss else float(ex.get("normal", 0.2))
				var lost_hp := maxi(0, int(p.get("max_hp")) - int(p.get("hp")))
				hit_damage += int(floor(float(lost_hp) * ratio))
			hit_damage += _target_damage_bonus(p)
			var dealt_now := _damage_enemy(p, hit_damage)
			_skill_damage_total += dealt_now
			hit_scored()
			_apply_hit_bleed(p, h)
			_apply_hit_poison(p, h)
			if h.has("vulnerable") and int(e.get("hp")) > 0 and p.has_method("apply_vulnerable"):
				var vuln: Dictionary = h["vulnerable"]
				p.call("apply_vulnerable", float(vuln.get("time", 5.0)), float(vuln.get("ratio", 0.25)))
			_skill_kinetic(p, h)
			_apply_hit_control(p, h)
			# 剑仙 P：实际造成伤害后才追加 3 秒眩晕与该目标的专属受击特效
			if skull_id == "z000" and _skill_name == "skill20_03" and dealt_now > 0 and int(e.get("hp")) > 0 \
					and p.has_method("stun"):
				p.call("stun", 3.0)
				# 地裂爆炸烟尘：脚底对齐、固定缩放，完整呈现整段特效（原来按体型算太小）。
				# 骨骼包围盒底部比实际墨迹低，再往下压 22px 让最低端真正落在目标脚中心。
				fx.world("E54181", p.global_position, "action", false,
					{"scale": 0.12, "bottom": true, "offset": Vector2(0.0, 22.0), "z": -1, "fx_role": "skill_hit"})
			if int(e.get("hp")) > 0 and h.has("frenzy") and p.has_method("apply_frenzy"):
				p.call("apply_frenzy", float(h["frenzy"]) + (2.0 if _form_node("z002_echo_1") else 0.0), bool(h.get("frenzy_empower", false)))
			_on_build_hit(p, _skill_name)
			if skull_id == "c023" and _skill_name == "skill02" and _own("c023_bind_2") and int(e.get("hp")) > 0:
				_pull_enemy(p, global_position.x + facing * 110.0)
			did_hit = true
	if did_hit:
		if skull_id == "z003" and _skill_name == "skill14_02":
			_arm_scar(_skill_start_x, skill_range) # K 落地即留痕，第二刀从蓄力点回响
		if skull_id == "z000" and _skill_name == "skill02-" and _form_node("z000_volley_1"):
			_skill_cancel_ready = true
		if skull_id == "c023" and _skill_name == "skill02" and _own("c023_bind_3"):
			_branch_zones.append({"x": global_position.x, "y": global_position.y, "radius": 260.0, "time": 5.0})
			FX.spawn(get_tree().current_scene, "telegraph", global_position, {"scale": 1.4, "mod": Color(0.5, 0.8, 0.55, 0.7)})
		if skull_id == "c021" and _skill_name == "skill5-" and _own("c021_bait_3") and _bait_time > 0.0 and is_instance_valid(_bait):
			var left := minf(global_position.x, _bait.global_position.x) - 35.0
			var right := maxf(global_position.x, _bait.global_position.x) + 35.0
			for e in _foes():
				var p := e as Node2D
				if p != null and int(e.get("hp")) > 0 and p.global_position.x >= left and p.global_position.x <= right \
						and absf(p.global_position.y - global_position.y) <= 120.0:
					p.call("apply_bleed", 1)
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
	if h.has("sfx") and (did_hit or bool(h.get("sfx_on_release", false))):
		_play_sfx(str(h["sfx"]))
	_apply_skill_heal(h)


## 摄心：选取正前方最靠近的敌人；Boss 不回血，其他目标回满后再转为临时同伴。
func _deal_charm() -> void:
	var target: Node2D = null
	var nearest := INF
	for e in _foes():
		var p := e as Node2D
		if p == null or int(e.get("hp")) <= 0:
			continue
		var dx: float = p.global_position.x - global_position.x
		if (dx < 0.0) == (facing > 0) and dx != 0.0:
			continue
		if absf(dx) > 520.0 + _radius_of(p) or absf(p.global_position.y - global_position.y) > 160.0:
			continue
		if absf(dx) < nearest:
			nearest = absf(dx)
			target = p
	if target == null:
		return
	var tier := str(target.call("stop_tier")) if target.has_method("stop_tier") else "mob"
	var duration := 5.0 if tier == "boss" else (10.0 if tier == "elite" else 15.0)
	if tier != "boss":
		duration += 3.0 if _form_node("z002_charm_1") else 0.0
		target.set("hp", int(target.get("max_hp")))
		if target.has_method("_update_hp_bar"):
			target.call("_update_hp_bar")
	if target.has_method("apply_charm"):
		target.call("apply_charm", duration)
	if _own("z002_allure_1"):
		var extra: Node2D = null
		var extra_nearest := INF
		for e in _foes():
			var other := e as Node2D
			if other == null or other == target or int(e.get("hp")) <= 0 or not e.has_method("apply_charm"):
				continue
			if e.has_method("stop_tier") and str(e.call("stop_tier")) == "boss":
				continue
			var dist := other.global_position.distance_to(target.global_position)
			if dist <= 240.0 and dist < extra_nearest:
				extra = other
				extra_nearest = dist
		if extra != null:
			extra.call("apply_charm", 6.0)
			FX.spawn(get_tree().current_scene, "telegraph", extra.global_position + Vector2(0, -60), {"scale": 0.5, "mod": Color(0.68, 0.38, 0.72, 0.8)})
		else:
			# 同梦·初：附近没有第二只敌人时，把主目标的魅惑延长 3 秒，整卡不空放
			target.call("apply_charm", duration + 3.0)
	hit_scored()
	FX.spawn(get_tree().current_scene, "telegraph", target.global_position + Vector2(0, -60), {"scale": 0.65, "mod": Color(0.68, 0.38, 0.72, 0.8)})
	var dn := DAMAGE_NUMBER.new()
	dn.setup("摄心 · %d秒" % int(duration), Color(0.72, 0.48, 0.8))
	dn.global_position = target.global_position + Vector2(0, -150)
	_world_add(dn)
	_play_sfx("voice_skill_cast")
	Feel.hitstop(0.05)


## 心魔引：先快照自身减益，再引爆全房状态；转移只发给引爆后仍存活的目标。
func _deal_mind_detonate() -> void:
	var transferred := _player_debuff_snapshot()
	var base_damage := 8 + (2 if _form_node("z002_grudge_2") else 0)
	var hit_any := false
	var mind_bursts: Array = []
	for e in _foes():
		var p := e as Node2D
		if p == null or int(e.get("hp")) <= 0 or not p.has_method("detonate_mind"):
			continue
		var before := int(e.get("hp"))
		if _own("z002_mind_1") and int(e.get("_six_senses")) <= 0:
			# 心魔·初：引爆时自带一层六感，否则没觉醒就完全用不上这张卡
			e.set("_six_senses", 1)
		p.call("detonate_mind", base_damage, global_position.x, _own("z002_mind_1"))
		_skill_damage_total += maxi(0, before - int(e.get("hp")))
		hit_scored()
		hit_any = true
		FX.spawn(get_tree().current_scene, "ink_hit", p.global_position + Vector2(0, -70), {"scale": 0.65})
		if int(e.get("hp")) <= 0:
			if _own("z002_mind_2") and _skill_cds.has(_skill_name):
				_skill_cds[_skill_name] = maxf(0.0, float(_skill_cds[_skill_name]) - 3.0)
			if _own("z002_mind_3"):
				mind_bursts.append(p.global_position)
	# 溅射统一在全房引爆后结算；溅射击杀只返冷却，不再递归产生溅射。
	for pos in mind_bursts:
		for other_e in _foes():
			var other := other_e as Node2D
			if other == null or int(other_e.get("hp")) <= 0 or other.global_position.distance_to(pos) > 240.0:
				continue
			var splash_before := int(other_e.get("hp"))
			_skill_damage_total += _damage_enemy(other, 3)
			if int(other_e.get("hp")) > 0 and other_e.has_method("apply_frenzy"):
				other_e.call("apply_frenzy", 6.0)
			elif int(other_e.get("hp")) <= 0 and splash_before > 0 and _own("z002_mind_2") and _skill_cds.has(_skill_name):
				_skill_cds[_skill_name] = maxf(0.0, float(_skill_cds[_skill_name]) - 3.0)
			FX.spawn(get_tree().current_scene, "ink_hit", other.global_position + Vector2(0, -60), {"scale": 0.35})
	var survivors: Array = []
	for e in _foes():
		if int(e.get("hp")) > 0 and e.has_method("apply_transferred_debuff"):
			survivors.append(e)
	for target in survivors:
		for info in transferred:
			target.call("apply_transferred_debuff", info)
	_purify_player_debuffs()
	FX.spawn(get_tree().current_scene, "telegraph", global_position, {"scale": 2.2, "mod": Color(0.65, 0.32, 0.72, 0.65)})
	_play_sfx("skill_boom")
	if hit_any:
		Feel.hitstop(0.08)
		Feel.shake(9.0, 0.25)


## 当前所有可转移减益；永久生命上限损耗与局外存档不属于战斗状态，不在此净化。
func _player_debuff_snapshot() -> Array:
	var out: Array = []
	if _bleed_stacks > 0:
		out.append({"id": "bleed", "stacks": _bleed_stacks, "time": _bleed_time})
	for cut in _cuts:
		var left: Array = cut.get("left", [])
		var time := 0.0
		for t in left:
			time = maxf(time, float(t))
		out.append({"id": "cut", "stacks": 1, "time": time})
	for info in [
		{"id": "jump_seal", "time": _jump_seal}, {"id": "dash_seal", "time": _dash_seal},
		{"id": "cripple", "time": _cripple_time}, {"id": "stun", "time": _stun_time},
		{"id": "ming_zhong_vulnerability", "time": _ming_zhong_vulnerable_time},
		{"id": "passive_seal", "time": _passive_seal_time},
	]:
		if float(info["time"]) > 0.0:
			info["stacks"] = 1
			out.append(info)
	if _mo_ting_burn_stacks > 0:
		out.append({"id": "mo_ting_burn", "stacks": _mo_ting_burn_stacks, "time": _mo_ting_burn_time})
	if _fen_ding_burn_stacks > 0:
		out.append({"id": "fen_ding_burn", "stacks": _fen_ding_burn_stacks, "time": _fen_ding_burn_left})
	if wu_che_wanted:
		out.append({"id": "wu_che_wanted", "stacks": 1, "time": 0.0})
	if _mo_ting_grabbed:
		out.append({"id": "mo_ting_grab", "stacks": 1, "time": 1.0})
	if is_instance_valid(_ming_zhong_holder):
		out.append({"id": "ming_zhong_hold", "stacks": 1, "time": 1.0})
	if _ming_zhong_holy > 0:
		out.append({"id": "ming_zhong_holy", "stacks": _ming_zhong_holy, "time": 0.0})
	if not _stolen_passives.is_empty():
		out.append({"id": "stolen_passives", "stacks": _stolen_passives.size(), "time": 0.0})
	if _sui_yue_pressure:
		out.append({"id": "sui_yue_pressure", "stacks": 1, "time": 0.0})
	if _room_cd_cursed:
		out.append({"id": "room_cd_curse", "stacks": 1, "time": 0.0})
	return out


func _purify_player_debuffs() -> void:
	_clear_bleed()
	_cuts.clear()
	_cut_casts.clear()
	_jump_seal = 0.0
	_dash_seal = 0.0
	_cripple_time = 0.0
	_mo_ting_burn_stacks = 0
	_mo_ting_burn_time = 0.0
	clear_fen_ding_burn()
	wu_che_wanted = false
	if _mo_ting_grabbed:
		mo_ting_release()
	if is_instance_valid(_ming_zhong_holder):
		release_ming_zhong_hold(_ming_zhong_holder)
	_ming_zhong_holder = null
	_ming_zhong_vulnerable_time = 0.0
	_ming_zhong_holy = 0
	_room_cd_cursed = false
	_room_cd_uses.clear()
	clear_sui_yue_effects()


## 红尘按实际伤害段叠怨；多段攻击与持续伤害各自调用，不因玩家是否死亡而漏记。
func _on_pipa_damaged(attacker: Node) -> void:
	if skull_id != "z002" or not has_battle_passive("z002_red_dust"):
		return
	if attacker != null and is_instance_valid(attacker) and int(attacker.get("hp")) > 0 and attacker.has_method("add_grudge"):
		attacker.call("add_grudge", 1)


## 须臾：致命伤改为保留 1 生命，溢出量双倍转给一名未替死过的癫狂目标。
## 返回玩家本次实际应承受的数值，供直伤与持续伤共用同一结算路径。
func _try_pipa_scapegoat(amount: int, _attacker: Node = null) -> int:
	if skull_id != "z002" or amount < hp or hp <= 0 or not has_battle_passive("z002_ephemeral"):
		return amount
	var candidates: Array = []
	for e in _foes():
		if e.has_method("can_red_scapegoat") and bool(e.call("can_red_scapegoat")):
			candidates.append(e)
	if candidates.is_empty():
		return amount
	var target: Node = candidates[randi() % candidates.size()]
	target.call("consume_red_scapegoat")
	var transferred := (amount - hp + 1) * 2
	var p := target as Node2D
	target.call("take_damage", transferred, p.global_position.x if p != null else global_position.x)
	if p != null:
		FX.spawn(get_tree().current_scene, "ink_hit", p.global_position + Vector2(0, -70), {"scale": 0.8})
		var dn := DAMAGE_NUMBER.new()
		dn.setup("红粉骷髅 · 替承%d" % transferred, Color(0.72, 0.42, 0.78))
		dn.global_position = p.global_position + Vector2(0, -165)
		_world_add(dn)
	_play_sfx("gold")
	Feel.hitstop(0.08)
	return hp - 1


## 技能命中的续航：局内血饮与永久血舞各自拥有独立冷却，近段和剑气命中共用。
func _skill_hit_sustain() -> void:
	if skill_lifesteal and _lifesteal_cd <= 0.0:
		_lifesteal_cd = _lifesteal_cd_max
		_restore_hp(_lifesteal_heal)
		if _lifesteal_buff > 0:
			_buff_damage = maxi(_buff_damage, _lifesteal_buff)
			_buff_timer = maxf(_buff_timer, 4.0)
	if skull_id == "c021" and _form_node("c021_dance_1") and _perm_lifesteal_cd <= 0.0:
		_perm_lifesteal_cd = 8.0
		_restore_hp(1)


func _restore_hp(amount: int) -> void:
	# PVP：治疗效果按对战系数折算，避免续航型角色无限拉血
	if pvp_mode and amount > 0:
		amount = maxi(1, int(roundf(float(amount) * PvpTuning.HEAL_SCALE)))
		if _pvp_heal_cut:
			amount = maxi(1, int(ceilf(float(amount) * 0.5))) # 剑宗：治疗减半
	var cap := max_hp + extra_hp_cap()
	if state == State.DEAD or hp >= cap or amount <= 0:
		return
	var received := amount * (2 if skull_id == "z000" and has_battle_passive("z000_immortal") else 1)
	var heal := mini(received, cap - hp)
	if heal > 0 and _z001_burnout:
		_z001_exit_burnout() # 燃尽期间获得回血：立即恢复正常扣血逻辑
	hp += heal
	hp_changed.emit(hp, max_hp)
	_spawn_number(heal, Color(0.45, 0.75, 0.5), 130.0, false)
	_play_sfx("heal")


## 投射物统一回报：连击与技能回血；具体流派派生由各自的命中回调处理。
func on_projectile_hit(_p: Node2D, from_skill: bool, _cast_id: int) -> void:
	hit_scored()
	if from_skill:
		_skill_hit_sustain()
		# 剑仙 U 已改为投射物，砸落判定必须在投射物命中处补上，否则挑月·极永远不生效
		if _cast_id == _skill_cast_id and _skill_name == "skill04":
			_moon_slam(_p)


## 挑月·极：U 命中浮空目标时改按砸落结算；返回 true 表示本次位移已接管。
func _moon_slam(p: Node2D) -> bool:
	if skull_id != "z000" or not _own("z000_moon_3") or int(p.get("hp")) <= 0:
		return false
	var airborne := int(p.get("state")) == 6 or (p.has_method("is_on_floor") and not bool(p.call("is_on_floor")))
	if not airborne:
		return false
	var boss := p.has_method("stop_tier") and str(p.call("stop_tier")) == "boss"
	if boss:
		p.call("stun", 0.8)
		_slam_aoe(p.global_position, true)
	elif p.has_method("slam"):
		p.call("slam")
	return true


## 八音断识：每颗火弹只在真实碰撞时结算一次； miss 的弹不触碰此回调。
func on_pipa_wave_hit(target: Node2D, base_damage: int) -> void:
	var id := target.get_instance_id()
	var hit_count := int(_pipa_wave_hits.get(id, 0)) + 1
	_pipa_wave_hits[id] = hit_count
	var hit_damage := maxi(1, base_damage - mini(hit_count - 1, 3)) # 单目标 4/3/2/1，之后保底 1
	hit_damage += _target_damage_bonus(target)
	_skill_damage_total += _damage_enemy(target, hit_damage)
	if int(target.get("hp")) > 0 and target.has_method("apply_six_senses"):
		var senses := int(_pipa_awaken_count <= 1 or hit_count % 2 == 0)
		target.call("apply_six_senses", senses)
	_on_build_hit(target, "skill10_03")


## 乱弦：魔音先完成自身癫狂结算，再向最近的两名周围敌人传染。
func on_pipa_sound_hit(target: Node2D) -> void:
	if skull_id != "z002" or not _own("z002_chorus_1") or int(target.get("hp")) <= 0:
		return
	# 乱弦·初：主目标必定癫狂，先保证单体也有收益，再向周围传染
	if target.has_method("apply_frenzy"):
		target.call("apply_frenzy", 6.0)
	var candidates: Array = []
	for e in _foes():
		var other := e as Node2D
		if other == null or other == target or int(e.get("hp")) <= 0 or not e.has_method("apply_frenzy"):
			continue
		if other.global_position.distance_to(target.global_position) <= 240.0:
			candidates.append(other)
	candidates.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return a.global_position.distance_squared_to(target.global_position) < b.global_position.distance_squared_to(target.global_position))
	for i in range(mini(2, candidates.size())):
		candidates[i].call("apply_frenzy", 6.0)


## 绯刃掷匕命中：落匕与分裂匕的牵引都依赖真实命中点。
func on_dagger_hit(p: Node2D, pos: Vector2, from_split := false) -> void:
	if skull_id != "c021":
		return
	if _own("c021_return_1"):
		_leave_dagger(pos)
	if from_split and _own("c021_feather_3") and int(p.get("hp")) > 0:
		p.call("root", 1.2)
		for e in _foes():
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
		var old: Dictionary = _daggers.pop_front()
		var stale = old.get("node")
		if is_instance_valid(stale):
			stale.queue_free()
	_daggers.append({"pos": pos, "time": 8.0, "node": _make_dagger_marker(pos)})
	FX.spawn(get_tree().current_scene, "ink_hit", pos, {"scale": 0.25})


## 归刃·初：留在地上的匕首必须有可见实体，否则玩家完全不知道有匕可归
func _make_dagger_marker(pos: Vector2) -> Node2D:
	var blade := Polygon2D.new()
	blade.polygon = PackedVector2Array([
		Vector2(-2, -16), Vector2(2, -16), Vector2(3, 4), Vector2(-3, 4),
	])
	blade.color = Color(0.66, 0.2, 0.16)
	blade.global_position = pos
	get_tree().current_scene.add_child(blade)
	var tw := blade.create_tween()
	tw.tween_property(blade, "modulate:a", 0.0, 0.8).set_delay(7.2)
	tw.tween_callback(blade.queue_free)
	return blade


## 清空留匕时同步销毁地面实体，避免召回后还留着一堆不可交互的匕首
func _clear_dagger_markers() -> void:
	for dagger in _daggers:
		var node = dagger.get("node")
		if is_instance_valid(node):
			node.queue_free()
	_daggers.clear()


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
			for e in _foes():
				var p := e as Node2D
				if p != null and int(e.get("hp")) > 0 and not targets.has(p) \
						and absf(p.global_position.x - pos.x) <= 150.0 + _radius_of(p):
					targets.append(p)
		if _daggers.size() >= 2 and targets.size() >= 2:
			# 多匕拉撞：两把以上匕首才把落点敌人拉到中点对撞
			var mid: float = (targets[0].global_position.x + targets[1].global_position.x) * 0.5
			_pull_enemy(targets[0], mid - 20.0)
			_pull_enemy(targets[1], mid + 20.0)
			targets[0].call("stun", 1.2)
			targets[1].call("stun", 1.2)
			for i in range(2, targets.size()):
				targets[i].call("root", 1.2)
		elif targets.size() >= 1:
			_pull_enemy(targets[0], nearest.x)
			targets[0].call("root", 2.5)
	global_position.x = nearest.x
	_clear_dagger_markers()
	FX.spawn(get_tree().current_scene, "pillar", global_position, {"scale": 0.35})


## 敌人死亡回报由 c016（Boss 继承）发出；永久效果只归属于当前化身。
func on_enemy_killed(_enemy: Node2D) -> void:
	if skull_id == "z003" and has_battle_passive("z003_blood_cut") and _enemy.has_method("export_passives"):
		var packet := Run.record_blood_cut(_enemy.call("export_passives"))
		if not packet.is_empty():
			var dn := DAMAGE_NUMBER.new()
			dn.setup("血色切割 · 夺取 %d 被动" % (packet["passives"] as Array).size(), Color(0.78, 0.3, 0.38))
			dn.global_position = global_position + Vector2(0, -175)
			_world_add(dn)
	if skull_id == "c021" and _form_node("c021_dance_3"):
		Run.c021_dance_kills = (Run.c021_dance_kills + 1) % 3
		if Run.c021_dance_kills == 0:
			_restore_hp(1)
	if skull_id != "z003":
		return
	if _form_node("z003_chase_3"):
		for n in _skill_cds:
			_skill_cds[n] = maxf(0.0, float(_skill_cds[n]) - 1.0)
	if _o_kill_window > 0.0 and _buff_timer > 0.0 and _form_node("z003_return_3"):
		_buff_timer += 4.0
		_o_kill_window = 0.0


## 毒梅·极：毒死时向附近最近的两名敌人传毒，避免连锁即死、只传播状态。
func on_poison_kill(victim: Node2D) -> void:
	if skull_id != "c023" or not _form_node("c023_venom_3"):
		return
	var candidates: Array = []
	for e in _foes():
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
	if _form_node("z003_time_3") and int(p.get("hp")) > 0:
		if pvp_mode and ("pvp_mode" in p) and bool(p.get("pvp_mode")):
			# PVP：尾伤同样由 pvp_rules 换算，避免走 _damage_enemy 的 PvE 通道
			_emit_pvp_strike({"damage": 1, "full_screen": true, "both": true, "height": 9999.0, "knockback": 0.0})
		else:
			_damage_enemy(p, 1)
		hit_scored()


## 技能命中的位移效果（与普攻 _deal_hit 同规则）：launch=击飞挑空，knockback=击退轰飞；打死的尸体不动
func _skill_kinetic(p: Node2D, h: Dictionary) -> void:
	if int(p.get("hp")) <= 0:
		return
	if _skill_name == "skill04" and _moon_slam(p):
		return
	var lc: Dictionary = h.get("launch", {})
	if not lc.is_empty():
		# ignore_armor（剑仙 U 飞脚）：规则级击飞，连 Boss 的霸体也能挑起来
		p.call("launch", facing, float(lc.get("vx", 150.0)), float(lc.get("vy", 520.0)), bool(lc.get("ignore_armor", false)))
	var kb: Dictionary = h.get("knockback", {})
	var seismic_impact := skull_id == "c013" and _skill_name == "skill03" and _form_node("c013_seismic_3")
	if not kb.is_empty():
		# ignore_armor（剑仙 O 横斩）：霸体也照样轰飞；镇岳 L 的永久撞人不无视霸体
		var impact := int(kb.get("impact", 1)) + int(seismic_impact)
		p.call("knock_back", facing, float(kb.get("force", 620.0)), impact, bool(kb.get("ignore_armor", false)))
	elif seismic_impact:
		p.call("knock_back", facing, 620.0, 2) # 原本只有晕眩的 L 获得撞人，碰撞伤害 1→2


## 技能命中附加控制（敌人侧接口）：
## root=定身秒数（镇岳 K：轰飞后钉在落点，只锁移动、照常出手）
## stun=晕眩秒数（镇岳 L：锁移动也锁出手，立即打断正在起的招）
func _apply_hit_control(p: Node2D, h: Dictionary) -> void:
	if int(p.get("hp")) <= 0:
		return
	var stun := float(h.get("stun", 0.0))
	if stun > 0.0 and p.has_method("stun"):
		p.call("stun", stun)
	var root := float(h.get("root", 0.0))
	if skull_id == "c013" and _skill_name == "skill01" and _form_node("c013_seismic_2"):
		root = maxf(root, 2.5)
	if root > 0.0 and p.has_method("root"):
		p.call("root", root)


## 金刚·极：护盾抵挡或自然消失时每房最多回一次；换头主动散盾不触发。
func _shield_heal_once() -> void:
	if skull_id != "c013" or not _form_node("c013_guard_3") or _shield_heal_used:
		return
	_shield_heal_used = true
	_restore_hp(1)


## 金钟罩（镇岳 K 第二段）：给自己挂一次免伤，免疫下一次攻击；time 秒内没挨打也自动散
func _apply_self_shield(spec: Dictionary) -> void:
	_shield_hits = maxi(_shield_hits, int(spec.get("hits", 1)))
	var duration := float(spec.get("time", 8.0))
	if _form_node("c013_guard_2"):
		duration += 2.0
	_shield_time = maxf(_shield_time, duration)
	fx.sync_persistent(state == State.DEAD)
	if skull_id == "c013" and _own("c013_bell_1"):
		var pulled := 0
		for e in _foes():
			var p := e as Node2D
			if p != null and int(e.get("hp")) > 0 and absf(p.global_position.x - global_position.x) <= 340.0 + _radius_of(p) \
					and absf(p.global_position.y - global_position.y) <= 160.0:
				_pull_enemy(p, global_position.x + facing * (105.0 + pulled * 34.0))
				pulled += 1
	var dn := DAMAGE_NUMBER.new()
	dn.setup("金钟罩", Color(0.9, 0.75, 0.3)) # 金：护体成功提示
	dn.global_position = global_position + Vector2(0, -150)
	_world_add(dn)
	_play_sfx("skill_boom")
	Feel.hitstop(0.05)


## 钟鸣·续：主动碎钟，剩余护罩越久，震缚越久；极阶留下一次性反震壳。
func _shatter_bell() -> void:
	var dur := clampf(_shield_time * 0.25, 0.6, 2.5)
	_shield_hits = 0
	_shield_time = 0.0
	fx.sync_persistent(state == State.DEAD)
	_bell_shell = _own("c013_bell_3")
	for e in _foes():
		var p := e as Node2D
		if p != null and int(e.get("hp")) > 0 and absf(p.global_position.x - global_position.x) <= 360.0 + _radius_of(p) \
				and absf(p.global_position.y - global_position.y) <= 170.0:
			p.call("root", dur)
	_shield_heal_once()
	FX.spawn(get_tree().current_scene, "ink_hit", global_position + Vector2(0, -70), {"scale": 1.0})
	_play_sfx("gold")
	Feel.shake(7.0, 0.2)


## 技能命中附加流血：绯刃 L「裂帛」用，每次命中叠一层（敌人侧 apply_bleed 结算，直扣血不进硬直）
func _apply_hit_bleed(p: Node2D, h: Dictionary) -> void:
	var layers := int(h.get("bleed", 0))
	if layers <= 0 or int(p.get("hp")) <= 0:
		return
	if p.has_method("apply_bleed"):
		p.call("apply_bleed", layers)


## 技能命中附加中毒（梅剑 K 尾端甩鞭）：毒 duration 秒，敌人侧每 0.5 秒直扣 1 点、不叠层只刷新
func _apply_hit_poison(p: Node2D, h: Dictionary) -> void:
	var dur := float(h.get("poison", 0.0))
	if dur > 0.0 and skull_id == "c023" and _form_node("c023_venom_1"):
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
		_awaken_buff_damage = maxi(_awaken_buff_damage, int(sb.get("damage", 0)))
		_buff_timer = maxf(_buff_timer, float(sb.get("time", 6.0)))
	var heal_amt := int(h.get("heal", 0))
	if h.has("heal_ratio") and _skill_damage_total > 0:
		heal_amt += int(round(float(_skill_damage_total) * float(h["heal_ratio"])))
	var used_precepts := 0
	if skull_id == "c013" and _skill_name == "skill02" and h.has("heal") and _own("c013_ascetic_1"):
		used_precepts = _precepts
		heal_amt += used_precepts
	if heal_amt > 0:
		# PVP：技能回血同样按对战系数折算
		if pvp_mode:
			heal_amt = maxi(1, int(roundf(float(heal_amt) * PvpTuning.HEAL_SCALE)))
			if _pvp_heal_cut:
				heal_amt = maxi(1, int(ceilf(float(heal_amt) * 0.5))) # 剑宗：治疗减半
		var total_heal := heal_amt + _heal_bonus
		var received := total_heal * (2 if skull_id == "z000" and has_battle_passive("z000_immortal") else 1)
		var missing := maxi(0, max_hp + extra_hp_cap() - hp)
		var heal := mini(received, missing)
		if heal > 0:
			if _z001_burnout:
				_z001_exit_burnout() # 燃尽期间获得回血：立即恢复正常扣血逻辑
			hp += heal
			hp_changed.emit(hp, max_hp)
			var dn := DAMAGE_NUMBER.new()
			dn.setup("回血 +%d" % heal, Color(0.45, 0.75, 0.5))
			dn.global_position = global_position + Vector2(0, -130)
			_world_add(dn)
			_play_sfx("heal")
		if used_precepts > 0:
			_precepts = 0
			var overflow := maxi(0, total_heal - missing)
			var shields := mini(used_precepts, overflow)
			if shields > 0 and _own("c013_ascetic_2"):
				_apply_self_shield({"hits": shields, "time": 6.0})


## 技能持续伤害段（梅剑·转鞭）：每 interval 秒对前后方范围内的所有敌人各打一次。
## 不顿帧、不震屏——0.5s 一跳的持续伤害如果每跳都卡一下，打起来会抖。
func _deal_skill_tick(tick: Dictionary) -> void:
	# PVP：持续伤害段不在 _deal_skill_hit 的命中帧里，需要单独补一次判定
	if pvp_mode:
		_emit_pvp_strike({
			"damage": _stolen_skill_damage(int(tick["damage"]) + _tick_damage_bonus + damage_bonus + _buff_now()),
			"range": float(tick["range"]) * range_scale * _tick_range_scale,
			"height": float(tick.get("height", 120.0)),
			"both": bool(tick.get("both", false)),
			"knockback": 0.0,
		})
	var did_hit := false
	for e in _foes():
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
		_damage_enemy(p, _stolen_skill_damage(int(tick["damage"]) + _tick_damage_bonus + damage_bonus + _buff_now()) + _target_damage_bonus(p))
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
		for e in get_tree().get_nodes_in_group(&"enemies"):
			var p := e as Node2D
			if p == null or int(e.get("hp")) <= 0:
				continue
			var d: float = (p.global_position.x - global_position.x) * dir
			if d >= 0.0 and d < best:
				best = d
				target = e
	if target != null:
		_damage_enemy(target, damage)
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
	var effects := spec.duplicate(true)
	if skull_id == "z002" and _form_node("z002_echo_1"):
		if effects.has("frenzy"):
			effects["frenzy"] = float(effects["frenzy"]) + 2.0
		if bool(effects.get("frenzy_double", false)):
			effects["frenzy_min"] = float(effects.get("frenzy_min", 12.0)) + 2.0
	if skull_id == "z002" and from_skill and _skill_name == "skill10_03":
		effects["fx_id"] = "E53008" if randi() % 2 == 0 else "E53009"
		effects["fx_anim"] = "action"
	if skull_id == "z002" and str(spec.get("style", "")) == "magic_sound":
		if from_skill and _skill_name == "skill03":
			effects["fx_id"] = "E100129"
			effects["fx_anim"] = "action"
			effects["fx_height"] = 110.0
			effects["fx_speed"] = (float(spec.get("speed", 650.0)) * _proj_speed_scale) / 650.0
		elif not from_skill and _attack_idx == 3:
			effects["fx_id"] = "E54055"
			effects["fx_anim"] = "action"
			effects["fx_scale"] = 0.25
			effects["hit_fx_id"] = "E54056"
			effects["hit_fx_anim"] = "action"
			effects["hit_fx_scale"] = 0.3
	# root=命中定身秒数；split=命中后分裂数量；source 用于状态加伤与流派命中回报。
	pr.setup(facing, float(spec.get("speed", 520.0)) * _proj_speed_scale, float(spec.get("range", 420.0)) * _proj_range_scale,
		damage, sfx, proj_pierce or bool(spec.get("pierce", false)), float(spec.get("root", 0.0)),
		int(spec.get("split", 0)), str(spec.get("style", "qi")),
		int(spec.get("bleed", 0)), float(spec.get("scale", 1.0)), 0,
		self, from_skill, _skill_cast_id, effects)
	pr.global_position = global_position + Vector2(facing * 36.0, -52.0 + y_off)
	if not _world_add(pr):
		return
	var flight_sfx := str(_skill_runtime.get("projectile_sfx", "")) if from_skill else str(spec.get("projectile_sfx", ""))
	if flight_sfx == "pipa_basic_wave":
		audio.play_wave(flight_sfx)
	elif flight_sfx != "":
		_play_sfx(flight_sfx)


## 当前该用的待机动画：残血形态（weak 之类）优先，其余回普通 stand
func _idle_anim() -> String:
	if _low_idle_anim != "" and _low_hp_ratio > 0.0 \
			and float(hp) / float(maxi(1, max_hp)) <= _low_hp_ratio:
		return _low_idle_anim
	return str(anim_map["idle"])


func _hurt_tick(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, accel * delta)
	# 倒地链（镇岳）：逐段按动画真实时长接续，段与段之间无缝，起身段整段无敌
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
	_knock_cd = KNOCK_COOLDOWN
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
	var total := float(_skill_cd_totals.get(n, 0.0))
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
	# 优先读 InputMap（设置里改键后 HUD 跟着变），读不到再退回写死表。
	# 联机客机虽然占 1 号槽，但用的是自己设备上的 P1/触屏输入，不能显示本机双人的 P2 键位。
	if input_slot != 0 and Run.net_role == "":
		return LocalCoop.key_label(action)
	var s := Settings.action_label(action)
	return s if s != "-" else str(KEY_LABELS.get(action, "-"))


# ---------- 动作入口 ----------

## 输入槽相关：P1 读原动作，P2 读 local_coop 注册的 p2_ 动作，互不干扰
func _act(action: String) -> String:
	return LocalCoop.action(input_slot, action)


func _just(action: String) -> bool:
	if LanNet.is_remote_slot(input_slot):
		return LanNet.take_remote_just(input_slot, action)
	return Input.is_action_just_pressed(_act(action))


func _move_axis() -> float:
	if LanNet.is_remote_slot(input_slot):
		return float(LanNet.remote_axis(input_slot))
	return Input.get_axis(_act("move_left"), _act("move_right"))


## 联机镜像：主机快照直接写入位置/血量/状态/动画；物理与技能全部由主机结算
func net_apply_state(x: float, y: float, hp_value: int, max_hp_value: int, st: int, face: int, anim: String, loop: bool) -> void:
	global_position = Vector2(x, y)
	if max_hp_value != max_hp:
		max_hp = max_hp_value
	if hp_value != hp:
		hp = hp_value
		hp_changed.emit(hp, max_hp)
	state = st
	if face != facing:
		facing = face
		if sprite != null:
			sprite.scale = Vector2(base_scale * facing, base_scale)
	if anim != "" and (anim != _current_anim or loop != net_anim_loop):
		_play(anim, loop)


func _try_jump() -> void:
	if _jump_seal <= 0.0 and _cripple_time <= 0.0 and _jump_buf > 0.0 and _coyote > 0.0:
		_jump_buf = 0.0
		_coyote = 0.0
		velocity.y = jump_velocity * _qg_jump_mul # 轻功：明显更高的起跳
		_hover_left = _qg_hover # 本次跳跃带一段顶点悬停
		_set_state(State.JUMP)


func _try_dash() -> void:
	var flash_gap := skull_id == "c021" and has_battle_passive("c021_flash")
	if not _just("dash") or _dash_cd > 0.0 or (_dash_gap > 0.0 and not flash_gap) or _dash_seal > 0.0 or _cripple_time > 0.0:
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
		# 没有 still 项的形态（烬生）：站定与移动都从 move 池随机抽，保证 28/47 两段都出现
		if _move_axis() != 0.0 or not _dash_pool.has("still"):
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
	_begin_attack_recovery_if_needed()
	state = State.DASH
	_set_blink(true) # 所有化身的闪避都没有敌人碰撞体积，可穿到目标身后
	if skull_id == "c021" and _form_node("c021_shadow_1"):
		_dash_attack_window = 2.0
	_dash_speed_now = speed
	_dash_cd_set = cd
	_dash_timer = dur * _dash_time_scale # 闪避时长 = 闪避动画长度（整段都是完美闪避）
	fx.world("E53026", global_position + Vector2(-facing * 48.0, -58.0), "action", false,
		{"scale": 0.3, "flip": facing < 0, "fx_role": "dash"})
	_play(anim, false, _dash_anim_speed)
	_play_sfx("dash_step") # 冲刺踏地声，补上原本只有画面没有声音的空档


## 去来：归痕中闪避沿原路返回，只留状态不重复结算 O 的伤害。
func _return_dash() -> void:
	var start := global_position
	var left := minf(start.x, _return_mark.x) - 30.0
	var right := maxf(start.x, _return_mark.x) + 30.0
	var did_hit := false
	for e in _foes():
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
	global_position.x = _clamp_battle_x(global_position.x)
	_return_time = 0.0
	_outbound_hits.clear()
	_clear_return_mark()
	_hurt_invincible = maxf(_hurt_invincible, 0.35)
	_dash_gap = 0.5
	_dash_cd = 0.0 if did_hit and _own("z003_returning_3") else dash_cooldown * _dash_cd_scale
	FX.spawn(get_tree().current_scene, "speedline", (start + global_position) * 0.5, {"scale": 0.8})
	FX.spawn(get_tree().current_scene, "ink_hit", global_position + Vector2(0, -60), {"scale": 0.45})
	_play_sfx("dash_step")


func _start_attack(idx: int) -> void:
	if state != State.ATTACK and _attack_recovery_active():
		return
	if skull_id == "z000" and _wind_final and _form_node("z000_wind_1"):
		idx = attacks.size() - 1
		_wind_final = false
	if idx < 0 or idx >= attacks.size():
		return
	var atk: Dictionary = attacks[idx]
	state = State.ATTACK
	_attack_idx = idx
	_attack_queued = false
	_final_wave_done = false
	_attack_dodge_bonus = skull_id == "c021" and _form_node("c021_shadow_1") and _dash_attack_window > 0.0
	if _attack_dodge_bonus:
		_dash_attack_window = 0.0 # 只强化闪避后的下一段普攻
	# 随机池段（银夜三段普攻）：每段从 pool 抽一种动画，锁定时长 = 抽中动画的真实时长，
	# 命中时刻/判定范围也按抽中的动画查表（pool 段用 hit_at/range 字典逐动画标定）
	var anim := str(atk.get("anim", ""))
	if atk.has("pool") and not (atk["pool"] as Array).is_empty():
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
	_sync_stolen_sword_clone()
	_play_sfx(str(atk.get("cast_sfx", "weapon_sword"))) # 起手嗖一声
	_queue(anim_map["idle"], true) # 打完自动回 idle，防止卡在收招帧
	_idle_queued = true # 与 _start_skill 一致：idle 已在队列里，收招超时别再 _play 重开淡化


func _try_skill() -> void:
	if skull_id == "c013" and _own("c013_bell_2") and _shield_hits > 0 and _just("skill"):
		_shatter_bell()
		return
	for n in skill_config:
		var cfg: Dictionary = skill_config[n]
		if not _just(str(cfg["action"])) or _skill_cds.get(n, 0.0) > 0.0:
			continue
		# 觉醒限定技（O/P）只认真正觉醒窗口；完美闪避等普通加伤不能解锁。
		if bool(cfg.get("require_buff", false)) and _awaken_time <= 0.0:
			continue
		if skull_id == "z002" and bool(cfg.get("once_per_awaken", false)) and _pipa_o_used:
			continue
		if _cripple_time > 0.0 and _skill_has_displacement(n, cfg):
			continue
		_start_skill(n)
		return


## 致残只封带位移的技能；纯伤害、回血、觉醒与时停不受影响。
func _skill_has_displacement(n: String, cfg: Dictionary) -> bool:
	return cfg.has("blink_from") or cfg.has("blink_to") or bool(cfg.get("root_motion", false)) \
		or not cfg.get("teleport_anims", []).is_empty() or float(cfg.get("lunge", 0.0)) != 0.0 \
		or (skull_id == "z003" and n == "skill11")


func _start_skill(n: String) -> void:
	_begin_attack_recovery_if_needed()
	Achievements.event("skills_used")
	if skull_id == "c021" and n == "skill01" and _own("c021_return_2"):
		_recall_daggers()
	state = State.SKILL
	_skill_name = n
	_skill_cast_id += 1
	if _stolen("c008_bell"):
		_stolen_bell += 2 # 佛曰：每个非普通招式获得一层，每层抵挡两次伤害
		_spawn_passive_text("佛曰 · 金钟 %d 层" % int(_stolen_bell / 2.0), Color(0.9, 0.75, 0.3))
	if skull_id == "z003" and n == "skill10" and not _stolen_divine and _stolen("c032_divine_favor"):
		_stolen_divine = true # 神眷只随首次 I 觉醒启用；P 仍是影殇原本的天倾与魅唤
		_spawn_passive_text("神眷 · 神圣庇佑", Color(0.95, 0.82, 0.38))
	_skill_cancel_ready = false
	if skull_id == "z000" and n == "atk04":
		_edge_k_hits.clear()
	var cfg: Dictionary = skill_config[n]
	# 绛弦 U 觉醒前后共用技能键与冷却，只替换本次运行配置。
	if cfg.has("awaken") and _awaken_time > 0.0:
		var base_cfg := cfg
		cfg = (base_cfg["awaken"] as Dictionary).duplicate(true)
		cfg["action"] = base_cfg["action"]
		cfg["cooldown"] = base_cfg["cooldown"]
		if not cfg.has("cast_sfx"):
			cfg["cast_sfx"] = str(base_cfg.get("cast_sfx", ""))
		if cfg.has("anim"):
			cfg["pool"] = [str(cfg["anim"])]
	_skill_runtime = cfg.duplicate(true)
	_skill_audio_events = (cfg.get("sfx_events", []) as Array).duplicate(true)
	if skull_id == "z002" and bool(cfg.get("once_per_awaken", false)):
		_pipa_o_used = true
		_pipa_wave_hits.clear()
	_parry_ready = skull_id == "c023" and n == "skill02" and (_own("c023_counter_1") or _form_node("c023_counter_1"))
	if _parry_ready:
		# 回环·初：格挡是隐藏状态，起手必须给一个看得见的架势提示
		FX.spawn(get_tree().current_scene, "telegraph", global_position + Vector2(0, -60), {"scale": 0.7, "mod": Color(0.9, 0.75, 0.3, 0.8)})
		var guard_dn := DAMAGE_NUMBER.new()
		guard_dn.setup("格挡", Color(0.9, 0.75, 0.3))
		guard_dn.global_position = global_position + Vector2(0, -150)
		_world_add(guard_dn)
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
		_spawn_return_mark()
	# 随机池技能（银夜 I/O）：每次从池里抽一种动画，时长按抽中的走；冷却/命中段全技能统一
	_skill_anim = str(cfg.get("anim", n))
	if cfg.has("pool") and not (cfg["pool"] as Array).is_empty():
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
	# 连播类技能（烬生 K）：同一段动画循环 repeat 次，总时长按次数累加
	var repeat := maxi(1, int(cfg.get("repeat", 1)))
	if repeat > 1:
		_skill_dur = base_dur * float(repeat) / _skill_speed
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
		for extra in ["projectile", "bleed", "poison", "vulnerable", "stun", "root", "knockback", "launch",
				"heal", "heal_ratio", "self_buff", "self_shield", "full_screen", "room_buff", "sfx_on_release"]:
			if cfg.has(extra):
				h[extra] = cfg[extra]
		_skill_hits = [h]
	else:
		_skill_hits = cfg.get("hits", []).duplicate(true)
	# 连播类技能：把每轮命中按动画周期展开到整段循环上
	if repeat > 1:
		var expanded: Array = []
		var cycle_hits: Array = cfg.get("repeat_hits", [])
		for c in repeat:
			for rh in cycle_hits:
				var hh: Dictionary = (rh as Dictionary).duplicate(true)
				hh["at"] = float(hh.get("at", 0.2)) + base_dur * float(c)
				hh["range"] = float(cfg.get("range", hh.get("range", 120.0)))
				hh["height"] = float(cfg.get("height", hh.get("height", 110.0)))
				hh["both"] = bool(cfg.get("both", hh.get("both", false)))
				hh["sfx"] = str(cfg.get("sfx", hh.get("sfx", "")))
				expanded.append(hh)
		_skill_hits = expanded
	if skull_id == "z000" and n == "skill04":
		_skill_hits = [{"at": 0.48, "damage": 5, "sfx": "hit_heavy", "projectile": {
			"speed": 900.0, "range": 620.0, "pierce": true, "style": "qi",
			"fx_id": "E54083", "fx_anim": "action1", "fx_scale": 0.35,
			"first_fx_anim": "action3", "first_fx_scale": 0.3, "first_damage": 5, "hit_sfx": "z000_u_hit",
			"hit_fx_id": "E54083", "hit_fx_anim": "action2", "hit_fx_scale": 0.35, "later_damage": 2,
		}}]
	_skill_start_x = global_position.x
	# root_motion：节点跟着动画根骨走（绯刃 U：动画自己后跃约 170px，节点必须跟到那儿，收招才不会滑回原点）
	_skill_root_follow = bool(cfg.get("root_motion", false))
	_skill_root_x = global_position.x
	if sprite:
		sprite.position = Vector2.ZERO # 清掉上一招残留的根骨补偿
	_skill_poise = bool(cfg.get("poise", false)) or (skull_id == "c023" and n == "skill02" and _form_node("c023_patience_1"))
	_skill_reflect = bool(cfg.get("reflect", false))
	_skill_ranged_guard = bool(cfg.get("ranged_guard", false))
	_skill_tick_acc = 0.0
	_stop_done = false
	var room_penalty := float(_room_cd_uses.get(n, 0)) if _room_cd_cursed else 0.0
	_skill_cd_set = float(cfg["cooldown"]) * cooldown_scale * _mastery_cd * _form_cd_scale * float(_skill_cd_mod.get(n, 1.0)) + room_penalty
	if skull_id == "z000" and _z000_confidence_time > 0.0 and has_battle_passive("z000_lady"):
		_skill_cd_set *= 0.5 # 淑女：只减半自信期间实际释放的技能
	if skull_id == "z002" and n == "skill03" and _form_node("z002_echo_2"):
		_skill_cd_set = maxf(0.1, _skill_cd_set - 1.0)
	_skill_cd_totals[n] = _skill_cd_set
	_skill_cds[n] = _skill_cd_set
	if _room_cd_cursed:
		_room_cd_uses[n] = int(_room_cd_uses.get(n, 0)) + 1
	if skull_id == "c013" and n == "skill02" and _precepts >= 3 and _own("c013_ascetic_3"):
		_skill_cds[n] = 0.0
		_apply_self_shield({"hits": 1, "time": 6.0})
		# 苦行·极：三戒 U 同时展开钟鸣，把周围敌人拉到身前
		var pulled := 0
		for e in _foes():
			var p := e as Node2D
			if p != null and int(e.get("hp")) > 0 and absf(p.global_position.x - global_position.x) <= 340.0 + _radius_of(p) \
					and absf(p.global_position.y - global_position.y) <= 160.0:
				_pull_enemy(p, global_position.x + facing * (105.0 + pulled * 34.0))
				pulled += 1
	_skill_damage_total = 0 # O 第三段按本次技能总伤害比例回血
	_awaken_pending = float(cfg.get("awaken_time", 0.0)) # I 觉醒：动画播完才开始计时
	if _awaken_pending > 0.0:
		_awaken_stacks = 0
	_invincible = false
	# 无敌型技能（红蝶 L「罗刹旋舞」等）起手即无敌：不等 _skill_tick 下一帧，避免起手同帧被命中打断
	if bool(cfg.get("invincible", false)):
		_invincible = true
	# 自带位移动画（银夜 O 抽到 #87 skill11-cankao）：原地播放，收招瞬间瞬移整段冲刺距离（闪现窗口×速度）
	_skill_teleport = 0.0
	if _skill_anim in cfg.get("teleport_anims", []):
		_skill_teleport = float(cfg.get("blink_speed", 800.0)) * (float(cfg.get("blink_to", 0.9)) - float(cfg.get("blink_from", 0.15))) * _blink_dist_scale + _blink_bonus_dist
	# 觉醒（银夜 I）：起手即回血 + 限时加伤；绛弦 L 改在曲终魔音出手时统一回血。
	if cfg.has("heal") and not (skull_id == "z002" and n == "skill03"):
		_apply_skill_heal({"heal": cfg["heal"]})
	# 烬生 I：立刻把生命恢复至满值（燃尽中则先退出燃尽）
	if bool(cfg.get("heal_full", false)):
		_restore_hp(maxi(0, max_hp - hp))
	if cfg.has("buff_damage"):
		_buff_damage = int(cfg["buff_damage"])
		_awaken_buff_damage = int(cfg["buff_damage"])
		_buff_timer = float(cfg.get("buff_time", 8.0))
		if skull_id == "z003" and n == "skill10" and _form_node("z003_return_2"):
			_buff_timer += 2.0
		if skull_id == "z003" and n == "skill10":
			_awaken_time = _buff_timer # 影殇 I 与加伤同时建立等长的真正觉醒窗口
	velocity.x = facing * float(attacks[0]["lunge"]) * 0.6 # 起手小前冲
	_play(_skill_anim, repeat > 1, _skill_speed)
	_sync_stolen_sword_clone()
	var loop_sfx := str(cfg.get("loop_sfx", ""))
	if loop_sfx != "":
		_start_skill_loop(loop_sfx)
	else:
		_stop_skill_loop()
		var full_cast_sfx := str(cfg.get("full_cast_sfx", ""))
		if not full_cast_sfx.is_empty():
			_play_full_sfx(full_cast_sfx, float(cfg.get("full_cast_volume_db", 0.0)))
		else:
			_play_sfx(str(cfg.get("cast_sfx", "voice_skill_cast"))) # 技能起手嗡一声
	# 其他技能排队 stand 防止收招空窗；银夜 I 必须保留原轨道供 _skill_tick 监听完成，收招时再切 stand。
	if skull_id != "z003" or _skill_name != "skill10":
		_queue(anim_map["idle"], true)
		_idle_queued = true
	else:
		_idle_queued = false
	if str(cfg.get("action", "")) == "skill_p":
		_charm_call()
	_start_skill_spine(n)


func _stolen(id: String) -> bool:
	return skull_id == "z003" and has_battle_passive("z003_blood_cut") and Run.has_stolen_passive(id)


func _stolen_skill_damage(amount: int) -> int:
	return maxi(1, amount - 1) if _stolen_bloodthirst and _stolen("c018_bloodthirst") else amount


func _stolen_control_immune() -> bool:
	return _stolen("c017_brute") or _stolen("c009_construct")


func _stolen_dot_immune() -> bool:
	return _stolen("c001_faith") or _stolen("c009_construct")


## 炽热之心只响应怒焰真实扣血；普通命中只负责叠怒焰，不会直接回血或刷新技能。
func on_fen_ding_burn_hit(dealt: int, _target: Node) -> void:
	if dealt <= 0 or not _stolen("c015a1_burning_heart"):
		return
	_restore_hp(10)
	for n in _skill_cds:
		_skill_cds[n] = 0.0


func _try_stolen_era(attacker: Node, move: Dictionary) -> void:
	if not _stolen("c001_era") or not bool(move.get("wu_che_charge", false)):
		return
	var key := _enemy_cast_key(attacker, move)
	if key.is_empty() and attacker != null and is_instance_valid(attacker):
		key = str(attacker.get_instance_id())
	if key.is_empty() or _stolen_era_contacts.has(key):
		return
	_stolen_era_contacts[key] = true
	var past := global_position
	if not _stolen_history.is_empty():
		past = _stolen_history[0]["position"]
	global_position = past
	global_position.x = _clamp_battle_x(global_position.x)
	FX.spawn(get_tree().current_scene, "speedline", past, {"scale": 0.8, "mod": Color(0.55, 0.78, 0.82, 0.7)})
	_spawn_passive_text("璀璨时代 · 回溯", Color(0.55, 0.78, 0.82))


## 墨徒信仰把生命作为冲撞耐久：首次撞墙免费，之后每次撞墙失去一点。
func _stolen_wall_tick() -> void:
	if not _stolen("c001_faith"):
		_stolen_wall_latch = false
		return
	if state != State.DASH or not is_on_wall():
		_stolen_wall_latch = false
		return
	if _stolen_wall_latch:
		return
	_stolen_wall_latch = true
	if _stolen_wall_free:
		_stolen_wall_free = false
		_spawn_passive_text("墨徒信仰 · 初撞免耗", Color(0.9, 0.75, 0.3))
		return
	hp = maxi(0, hp - 1)
	hp_changed.emit(hp, max_hp)
	_spawn_passive_text("耐久 -1", Color(0.9, 0.48, 0.3))
	if hp <= 0 and not _try_revive(Vector2.ZERO):
		die()


func _try_stolen_madness_damage(amount: int, attacker: Node, move: Dictionary) -> bool:
	if not _stolen("c009_madness"):
		return false
	var actual := mini(amount, max_hp)
	max_hp = maxi(0, max_hp - amount)
	hp = max_hp # 失心疯始终生命等于上限，受伤只失去等量上限
	if Run.active:
		Run.z003_madness_hp -= actual
		Run.max_hp = max_hp
		Run.set_slot_hp(input_slot, hp)
	_record_last_hit(attacker, move, actual)
	if attacker != null and is_instance_valid(attacker) and attacker.has_method("on_player_hit"):
		attacker.call("on_player_hit", actual, move, self)
	hp_changed.emit(hp, max_hp)
	_spawn_number(actual, DMG_COLOR, 130.0)
	FX.spawn(get_tree().current_scene, "ink_hit", global_position + Vector2(0, -70), {"scale": 0.45})
	if hp <= 0 and not _try_revive(Vector2.ZERO):
		die()
	return true


func _stolen_death_burst() -> void:
	if not _stolen("c037_burst"):
		return
	for e in _foes():
		var p := e as Node2D
		if p == null or int(e.get("hp")) <= 0:
			continue
		var dx := p.global_position.x - global_position.x
		var in_front := dx == 0.0 or (dx > 0.0) == (facing > 0)
		if not in_front or absf(dx) > 480.0 + _radius_of(p) or absf(p.global_position.y - global_position.y) > 240.0:
			continue
		if _damage_enemy(p, 3) > 0 and int(e.get("hp")) > 0 and e.has_method("apply_room_cd_curse"):
			e.call("apply_room_cd_curse")
	FX.spawn(get_tree().current_scene, "ink_claw", global_position + Vector2(facing * 210.0, -100.0), {"scale": 2.2, "flip": facing < 0, "z": 6})


## 魅唤附加在原 P 之后：原觉醒、伤害与冷却完全保留；友方不进入 enemies 或武车 _summons。
func _charm_call() -> void:
	if not has_battle_passive("z003_charm_call"):
		return
	if is_instance_valid(_charm_summon) and int(_charm_summon.get("hp")) > 0:
		return
	var packet := Run.random_stolen_packet()
	if packet.is_empty():
		return
	var type_id := str(packet.get("type_id", ""))
	var scene_path := str(packet.get("scene", ""))
	if scene_path.is_empty():
		scene_path = str(BossTypes.SCENES.get(type_id, ""))
	if scene_path.is_empty():
		return
	var scene := load(scene_path) as PackedScene
	if scene == null:
		return
	var ally := scene.instantiate() as Node2D
	if ally == null:
		return
	var script_path := str(packet.get("script", ""))
	if script_path.is_empty():
		script_path = str(BossTypes.SCRIPT_OVERRIDES.get(type_id, ""))
	if not script_path.is_empty() and ally.get_script().resource_path != script_path:
		ally.set_script(load(script_path))
	ally.set("type_id", type_id)
	ally.set("player_ally", true)
	get_parent().add_child(ally)
	ally.global_position = global_position + Vector2(-facing * 100.0, 0.0)
	_charm_summon = ally
	fx.world("E54054", ally.global_position + Vector2(0.0, -60.0), "action", false,
		{"scale": 0.5, "fx_role": "summon"})


## 立刻换成指定形态：拆旧骨架 → 重装形态数据 → 重建骨架
func swap_skull(id: String) -> void:
	if not Skulls.SKULLS.has(id) or id == skull_id:
		return
	_stop_skill_loop()
	fx.clear_all()
	_dismiss_stolen_sword_clone()
	_set_blink(false) # 换头瞬间收掉闪现的碰撞例外
	_invincible = false
	_idle_queued = false
	_attack_idx = -1
	_attack_recovery = 0.0
	_attack_queued = false
	_attack_hits.clear()
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
	_awaken_buff_damage = 0
	_awaken_time = 0.0 # 剑仙觉醒与剑意层数同理，换头即散
	_awaken_pending = 0.0
	_awaken_stacks = 0
	_skill_damage_total = 0
	_stop_buff_timer = 0.0 # 时停加伤同理
	_hover_left = 0.0
	_feathers = 0
	_clear_dagger_markers()
	if is_instance_valid(_bait):
		_bait.queue_free()
	_bait = null
	_bait_time = 0.0
	_branch_zones.clear()
	_clear_plum_zones()
	_clear_return_mark()
	_clear_scar()
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
	# 局外养成的击杀/通关记账按 P1 当前形态归属；联机客机的镜像换形不得覆盖主机下发的身份。
	if int(input_slot) == 0:
		Run.skull_id = id
	# 换形态后按新角色的定位生命重算上限；局内还要同步 Run 的真实上限（只有 0 号槽写全局值）。
	set_upgrades(_upgrades)
	if pvp_mode:
		# 对战生命上限统一由 pvp_tuning 决定：中途换人不该按 PvE 定位血量（8/12/60）缩水
		max_hp = PvpTuning.MAX_HP
	elif Run.active:
		var cap := Run.calculated_max_hp(id, int(input_slot))
		if int(input_slot) == 0:
			Run.max_hp = cap
		max_hp = effective_max_hp(cap)
	hp = mini(hp, max_hp)
	hp_changed.emit(hp, max_hp)
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
		global_position.x = _clamp_battle_x(global_position.x)
		p.global_position = old_pos
		if p is CharacterBody2D:
			p.global_position.x = _clamp_battle_x(p.global_position.x)
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
	if _room_cd_cursed or _saint_immune():
		return
	_room_cd_cursed = true
	var dn := DAMAGE_NUMBER.new()
	dn.setup("魔诅 · 冷却滋长", Color(0.62, 0.38, 0.72))
	dn.global_position = global_position + Vector2(0, -180)
	_world_add(dn)


## 无敌不是"攻击落空"：攻击者仍收到命中回报，玩家也有视听反馈，只是生命与动作不受影响。
func _invincible_hit_feedback(attacker: Node, move: Dictionary) -> void:
	if attacker != null and is_instance_valid(attacker) and attacker.has_method("on_player_hit"):
		attacker.call("on_player_hit", 0, move, self)
	FX.spawn(get_tree().current_scene, "ink_hit", global_position + Vector2(0, -70), {"scale": 0.3})
	var dn := DAMAGE_NUMBER.new()
	dn.setup("无敌", Color(0.9, 0.75, 0.3))
	dn.global_position = global_position + Vector2(0, -150)
	_world_add(dn)
	_play_sfx("gold")
	Feel.hitstop(0.025)


func _passive_block_feedback(attacker: Node, move: Dictionary, label: String, sfx_name := "gold") -> void:
	if attacker != null and is_instance_valid(attacker) and attacker.has_method("on_player_hit"):
		attacker.call("on_player_hit", 0, move, self)
	FX.spawn(get_tree().current_scene, "ink_hit", global_position + Vector2(0, -70), {"scale": 0.35})
	var dn := DAMAGE_NUMBER.new()
	dn.setup(label, Color(0.9, 0.75, 0.3))
	dn.global_position = global_position + Vector2(0, -150)
	_world_add(dn)
	_play_sfx(sfx_name)


func hurt(amount: int = 1, knockback: Vector2 = Vector2.ZERO, attacker: Node = null, move: Dictionary = {}) -> void:
	if state == State.DEAD:
		return
	_try_stolen_era(attacker, move)
	if state == State.DASH and bool(move.get("wu_che_charge", false)):
		wu_che_wanted = false
	if _invincible:
		_invincible_hit_feedback(attacker, move)
		return
	# 完美闪避：冲刺途中碰到"本应命中"的伤害——全部闪掉并发收益
	# （小怪/Boss/投射物的伤害都走 hurt 这一个入口，挂这里全覆盖）
	if state == State.DASH:
		_perfect_dodge(attacker, amount)
		return
	# 刀客「亡命三刀」前两刀：只演受击、不扣血，也不进入受伤无敌/消耗护盾，
	# 这样三刀能各自重播受击动画，最后的实伤不会被前两刀的无敌窗口吞掉。
	if bool(move.get("feedback_only", false)):
		_begin_attack_recovery_if_needed()
		_set_blink(false)
		_reset_root_follow()
		state = State.HURT
		_hurt_phase = ""
		_hurt_getup_dur = 0.0
		var feedback_anim := str(anim_map["hurt"])
		_hurt_timer = maxf(hurt_time, float(_anim_durations.get(feedback_anim, hurt_time)))
		_stop_skill_loop()
		fx.clear_skill()
		velocity = knockback
		_idle_queued = false
		_play_sfx("hit_fist")
		FX.spawn(get_tree().current_scene, "ink_hit", global_position + Vector2(0, -70), {"scale": 0.35, "flip": knockback.x > 0.0})
		Feel.hitstop(0.025)
		Feel.shake(2.0, 0.08)
		_play(feedback_anim, false)
		return
	if _parry_ready and attacker != null and is_instance_valid(attacker) and _counter_attack(attacker):
		Achievements.event("parries")
		return
	if _bell_shell:
		_bell_shell = false
		Achievements.event("blocks")
		_hurt_invincible = maxf(_hurt_invincible, 0.35)
		if attacker != null and is_instance_valid(attacker) and int(attacker.get("hp")) > 0:
			# 钟鸣·极：钟壳挡下攻击时反震真实伤害，而不只是定身
			var reflected := 1 + _reflect_bonus
			_damage_enemy(attacker, reflected)
			attacker.call("stun", 1.2)
			var ap := attacker as Node2D
			if ap != null:
				FX.spawn(get_tree().current_scene, "ink_hit", ap.global_position + Vector2(0, -70), {"scale": 0.55})
				var dn := DAMAGE_NUMBER.new()
				dn.setup(str(reflected), Color(0.72, 0.45, 0.3), reflected)
				dn.global_position = ap.global_position + Vector2(0, -140)
				_world_add(dn)
		_play_sfx("gold")
		Feel.hitstop(0.06)
		Feel.shake(5.0, 0.16)
		return
	# 定山·反伤：技能期间自身无敌，挨多少就原样弹回攻击者多少
	# 放在 _hurt_invincible 之前——刚受过伤的 0.8s 无敌期内照样反弹
	if _skill_reflect and attacker != null and is_instance_valid(attacker) \
			and attacker.has_method("take_damage"):
		var reflected := amount + _reflect_bonus # 金刚·初/极：反弹额外加伤
		_damage_enemy(attacker, reflected)
		var ap := attacker as Node2D
		if ap != null:
			FX.spawn(get_tree().current_scene, "ink_hit", ap.global_position + Vector2(0, -60), {"scale": 0.4})
			var dn := DAMAGE_NUMBER.new()
			dn.setup(str(reflected), Color(0.72, 0.45, 0.3), reflected) # 赭石：反伤数字挂在攻击者头上
			dn.global_position = ap.global_position + Vector2(0, -140)
			_world_add(dn)
		_play_sfx("voice_fan_hit")
		Feel.shake(3.0, 0.1)
		return
	var cast_key := _enemy_cast_key(attacker, move)
	if _hurt_invincible > 0.0:
		# 只放行同一名攻击者、同一次起手且明确配置的后续段；其他防御仍在各自分支结算。
		if not bool(move.get("pierce_hurt_invincible", false)) or cast_key.is_empty() or cast_key != _hurt_cast_key:
			_invincible_hit_feedback(attacker, move)
			return
	# 金钟罩（镇岳 K 第二段）：免疫这一下，挡完即散（8 秒没挨打也会自动消失）
	if _shield_hits > 0:
		_shield_hits -= 1 # 苦行可把多枚戒印转成多层护盾，一次攻击只挡一层
		if _shield_hits <= 0:
			_shield_time = 0.0
		fx.sync_persistent(state == State.DEAD)
		var shield_dn := DAMAGE_NUMBER.new()
		shield_dn.setup("金钟罩", Color(0.9, 0.75, 0.3)) # 金：与完美闪避同色系
		shield_dn.global_position = global_position + Vector2(0, -150)
		_world_add(shield_dn)
		FX.spawn(get_tree().current_scene, "ink_hit", global_position + Vector2(0, -70), {"scale": 0.5})
		_play_sfx("golden_bell_block")
		Feel.hitstop(0.06)
		Feel.shake(3.0, 0.1)
		_shield_heal_once()
		return
	# 镰意绽花与墨颤削上限都是无直伤的特殊命中：先经过全部防御，再结算各自机制。
	if bool(move.get("bloom", false)):
		if _saint_immune():
			_passive_block_feedback(attacker, move, "圣僧")
		else:
			_apply_bloom(attacker, move)
		return
	if bool(move.get("mo_ting_sunder", false)):
		if _saint_immune():
			_passive_block_feedback(attacker, move, "圣僧")
		else:
			_apply_mo_ting_sunder(attacker, move)
		return
	# 鸣钟觉醒后的攻击仍先经过闪避、招架、护盾与受伤无敌，再转为零伤圣光命中。
	if bool(move.get("ming_zhong_zero", false)):
		if attacker != null and is_instance_valid(attacker) and attacker.has_method("on_ming_zhong_zero_hit"):
			attacker.call("on_ming_zhong_zero_hit", move, self)
		return
	if amount > 0 and _stolen("c001_faith"):
		_passive_block_feedback(attacker, move, "墨徒信仰")
		return
	if skull_id == "z003" and amount > 0 and has_battle_passive("z003_night") and randf() < 0.2:
		_passive_block_feedback(attacker, move, "暗夜", "z003_night")
		return
	if amount > 0 and _stolen_bell > 0 and _stolen("c008_bell"):
		_stolen_bell -= 1
		_passive_block_feedback(attacker, move, "佛曰 · 抵挡")
		return
	# 通缉只强化武车亲自召唤的敌人；闪避、护盾、受伤无敌等未实伤路径不会加伤。
	var summon_tag = attacker.get("wu_che_summon") if attacker != null and is_instance_valid(attacker) else false
	if amount > 0 and wu_che_wanted and summon_tag != null and bool(summon_tag):
		amount += 1
	var temporary_reduce := int(skull_id == "c013" and _form_node("c013_meditation_2") and _hurt_guard_timer > 0.0)
	if Run.guard_available and not _passives_disabled():
		temporary_reduce += 1
		Run.guard_available = false # 护砚只在实际扣血时消耗，闪避/护盾不会浪费
	amount = maxi(1, amount - (0 if _passives_disabled() else _damage_reduce) - temporary_reduce) # 所有减伤都遵守最低 1 伤
	amount = _ming_zhong_amplify(amount) # 鸣钟易伤固定 +1，并把唯一一层重新续到 12 秒
	if _stolen_flame_awakened and _stolen("c015a1_flame_bone"):
		amount = int(ceil(float(amount) * 0.5))
	if amount > 0 and _stolen_block > 0 and _stolen("c032_war_god"):
		var absorbed := mini(_stolen_block, amount)
		_stolen_block -= absorbed
		amount -= absorbed
		_spawn_passive_text("武神 · 格挡 %d" % _stolen_block, Color(0.9, 0.78, 0.36))
		if amount <= 0:
			_passive_block_feedback(attacker, move, "武神 · 格挡")
			return
	if _saint_immune():
		amount = mini(amount, 3)
	var buddha_guard := _consume_buddha_guard(amount, move)
	_on_pipa_damaged(attacker)
	amount = _try_pipa_scapegoat(amount, attacker)
	if _try_stolen_madness_damage(amount, attacker, move):
		return
	# 正式对局保护：敌方单次伤害不超过当前生命上限的 50%（至少两击才可能击倒），
	# 避免联机人数缩放后小兵一次普攻直接秒杀 8~10 血角色；红蝶每秒流失不走这里。
	if attacker != null and is_instance_valid(attacker):
		amount = Run.cap_enemy_hit(amount, max_hp)
	# 只记录真正扣血的一击：闪避、护盾、受伤无敌与反伤都不会污染终局对演。
	_record_last_hit(attacker, move, amount)
	# 燃尽：生命已归零，后续伤害改为扣除生命上限
	if _z001_burnout and amount > 0:
		_z001_burnout_take_damage(amount)
		return
	if skull_id == "c013" and _form_node("c013_meditation_2"):
		_hurt_guard_timer = 2.0
	if skull_id == "c023" and _form_node("c023_patience_3") and _hurt_cd_refund_cd <= 0.0:
		_hurt_cd_refund_cd = 5.0
		_skill_cds["skill02"] = maxf(0.0, float(_skill_cds.get("skill02", 0.0)) - 2.0)
	# 烬生：≤4 伤既不进硬直也不打断技能，连收招/闪现/根骨结算都不动
	var z001_soft := skull_id == "z001" and amount <= 4
	_hurt_invincible = 0.8
	_hurt_cast_key = cast_key
	if not z001_soft:
		_begin_attack_recovery_if_needed()
		_set_blink(false) # 受击打断技能：闪现的碰撞例外一并清掉，别带着穿怪状态进硬直
		_reset_root_follow() # 技能被受击打断：把根骨位移结算进节点，别把骨架留在偏移位置
	var dealt := mini(amount, hp) # 过量伤害不计入镰碎回血；反伤/护盾/闪避在上方已直接返回
	hp -= amount
	if dealt > 0:
		_z001_on_hit_taken() # 战狂：每次实际受击累计，满 5 次叠 1 层战意
	Achievements.hurt_event(dealt)
	if attacker != null and is_instance_valid(attacker) and attacker.has_method("on_player_hit"):
		attacker.call("on_player_hit", dealt, move, self)
	if not _stolen("c009_construct"):
		if hp > 0 and bool(move.get("room_cd_curse", false)):
			_apply_room_cd_curse()
		if hp > 0 and bool(move.get("cut", false)):
			_apply_cut(attacker, move, cast_key)
		if hp > 0 and int(move.get("bleed", 0)) > 0:
			_apply_bleed(int(move.get("bleed", 0)), attacker, move)
		if hp > 0 and bool(move.get("mo_ting_burn", false)):
			_apply_mo_ting_burn()
		if hp > 0 and bool(move.get("fen_ding_burn", false)):
			_apply_fen_ding_burn(attacker)
		if hp > 0 and bool(move.get("ming_zhong_vulnerability", false)):
			apply_ming_zhong_vulnerability()
	if skull_id == "c013" and _own("c013_ascetic_1"):
		_precepts = mini(3, _precepts + 1)
		var precept_dn := DAMAGE_NUMBER.new()
		precept_dn.setup("戒印 %d/3" % _precepts, Color(0.9, 0.75, 0.3))
		precept_dn.global_position = global_position + Vector2(0, -165)
		_world_add(precept_dn)
	hp_changed.emit(hp, max_hp)
	_spawn_number(amount, DMG_COLOR, 130.0)
	var hurt_sfx := "hit_fist"
	if attacker != null and is_instance_valid(attacker):
		var attacker_id = attacker.get("type_id")
		if attacker_id == null:
			attacker_id = attacker.get("skull_id")
		if attacker_id != null:
			hurt_sfx = "player_hurt_blunt" if str(attacker_id) in ["c013", "z002", "c001", "c015a1"] else "player_hurt_sharp"
	_play_sfx(hurt_sfx)
	# 水墨受击花在胸口炸开，flip 跟击退方向（击退朝右 = 攻击来自左侧）
	FX.spawn(get_tree().current_scene, "ink_hit", global_position + Vector2(0, -70), {"scale": 0.45, "flip": knockback.x > 0.0})
	Feel.hitstop(0.05) # 挨打也要"一僵"：受击反馈和打人一样重要
	Feel.shake(8.0, 0.24)
	# 烬生：4 点及以下伤害不进入硬直、不打断技能，也不吃受击无敌帧（伤害照常结算）
	if skull_id == "z001" and amount <= 4 and hp > 0:
		_hurt_invincible = 0.0
		return
	if hp <= 0:
		if _z001_enter_burnout():
			# 致命伤不判死，但 ≥5 的受击仍按阈值走 27 → 26 → 50 的倒地链
			if amount >= _knock_at and _knock_cd <= 0.0 and not _knock_chain.is_empty():
				_start_hurt_chain(knockback)
			return
		if _try_revive(knockback):
			return
		die()
		return
	if _stolen_control_immune():
		return # 蛮力与机关造物保留伤害结算，但免疫普通控制、受击硬直和击退
	# 升龙刀等实伤击飞：在普通受击与倒地链分支前覆盖竖直初速；防御与霸体规则不变。
	var launch_y := float(move.get("launch_velocity_y", 0.0))
	if launch_y < 0.0:
		knockback.y = launch_y
	var jump_seal := float(move.get("jump_seal", 0.0))
	if jump_seal > 0.0 and not _saint_immune():
		_jump_seal = maxf(_jump_seal, jump_seal)
		var seal_dn := DAMAGE_NUMBER.new()
		seal_dn.setup("封跳", Color(0.85, 0.72, 0.42))
		seal_dn.global_position = global_position + Vector2(0, -150)
		_world_add(seal_dn)
	var dash_seal := float(move.get("dash_seal", 0.0))
	if dash_seal > 0.0 and not _saint_immune():
		_dash_seal = maxf(_dash_seal, dash_seal)
		var seal_dn := DAMAGE_NUMBER.new()
		seal_dn.setup("封闪", Color(0.85, 0.72, 0.42))
		seal_dn.global_position = global_position + Vector2(0, -150)
		_world_add(seal_dn)
	var cripple := float(move.get("cripple", 0.0))
	if cripple > 0.0 and not _saint_immune():
		_cripple_time = maxf(_cripple_time, cripple)
		_jump_buf = 0.0
		var cripple_dn := DAMAGE_NUMBER.new()
		cripple_dn.setup("致残", Color(0.85, 0.42, 0.32))
		cripple_dn.global_position = global_position + Vector2(0, -170)
		_world_add(cripple_dn)
	var passive_seal := float(move.get("passive_seal", 0.0))
	if passive_seal > 0.0 and not _saint_immune():
		apply_sui_yue_seal(passive_seal)
		var seal_dn := DAMAGE_NUMBER.new()
		seal_dn.setup("剥离 · 被动封印", Color(0.68, 0.48, 0.78))
		seal_dn.global_position = global_position + Vector2(0, -190)
		_world_add(seal_dn)
	var stun := float(move.get("stun", 0.0))
	if stun > 0.0 and not _saint_immune() and not _stolen_control_immune():
		_stun_time = maxf(_stun_time, stun)
		var stun_dn := DAMAGE_NUMBER.new()
		stun_dn.setup("眩晕", Color(0.9, 0.75, 0.3))
		stun_dn.global_position = global_position + Vector2(0, -150)
		_world_add(stun_dn)
	# 鸣钟四连击期间保留正前方站位，由 Boss 在整套动作结束后统一释放。
	if is_instance_valid(_ming_zhong_holder):
		state = State.HURT
		_hurt_phase = "ming_zhong_hold"
		velocity = Vector2.ZERO
		return
	# 墨颤定点期间保留站位，由 Boss 在整套滑斩结束后统一释放。
	if _mo_ting_grabbed:
		state = State.HURT
		_hurt_phase = "mo_ting_grab"
		velocity = Vector2.ZERO
		return
	# 霸体（镇岳形态专属 + 定山技能自带）：技能期间挨打开着招式硬吃，掉血但不进硬直、不打断技能
	if (poise or _skill_poise) and state == State.SKILL:
		return
	_stop_skill_loop()
	fx.clear_skill()
	# 墨冲明确携带倒地标记；只有当前角色确有倒地链或倒地动画时才强制触发。
	# 击倒保护期内只结算伤害与普通受击，不再倒地（全形态默认）。
	if not buddha_guard and _knock_cd <= 0.0 and bool(move.get("force_knockdown", false)):
		if not _knock_chain.is_empty():
			_start_hurt_chain(knockback)
			return
		if _fall_anim != "":
			_start_knockdown(knockback)
			return
	# 伤害过阈值直接倒地：播 fall → getup（起身段无敌），重型攻击的惩罚更直观；
	# 形态表配了 knock_chain（镇岳：重受击→浮空重受击→倒地→起身）就走整条链
	if not buddha_guard and _knock_cd <= 0.0 and _knock_at < 999 and amount >= _knock_at:
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
	_skill_hits.clear() # 普通受击打断技能后，不留可在后续状态误结算的命中段
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
	_begin_attack_recovery_if_needed()
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
		_world_add(loss_dn)
	if attacker.has_method("on_player_hit"):
		attacker.call("on_player_hit", 0, move, self)


## 墨颤命中后把玩家定点在操控者正前方；主动释放前不吃重力、不接受移动输入。
## 返回 false 表示这次锁头没有抓住（防守状态），操控者不应把玩家当成已抓获。
func mo_ting_hold(pos: Vector2) -> bool:
	if state == State.DEAD or _saint_immune():
		return false
	# 无敌 / 完美闪避 / 受击无敌 / 金钟罩期间，锁头不把人带走：
	# 抓取是位置判定、不经过 hurt，必须在这里单独挡。
	if _invincible or state == State.DASH or _hurt_invincible > 0.0 or _shield_hits > 0:
		return false
	_begin_attack_recovery_if_needed()
	_set_blink(false)
	_reset_root_follow()
	_skill_teleport = 0.0
	_skill_poise = false
	_skill_reflect = false
	_skill_ranged_guard = false
	_invincible = false
	_hurt_invincible = 0.0
	_mo_ting_grabbed = true
	global_position = pos
	velocity = Vector2.ZERO
	state = State.HURT
	_hurt_phase = "mo_ting_grab"
	_hurt_timer = 0.0
	_idle_queued = false
	_play(anim_map["idle"], true)
	return true


func mo_ting_release() -> void:
	if not _mo_ting_grabbed:
		return
	_mo_ting_grabbed = false
	_hurt_phase = ""
	_invincible = false
	_hurt_invincible = maxf(_hurt_invincible, 0.35)
	velocity = Vector2.ZERO
	_set_state(State.FALL)


## 鸣钟首段实伤后锁定正前方站位；后续段仍可结算伤害，但输入与重力不再推开玩家。
func ming_zhong_hold(boss: Node2D) -> void:
	if state == State.DEAD or boss == null or _saint_immune():
		return
	# 无敌型技能全程不可被打断：锁头也不能清掉无敌、强转 HURT
	if _invincible:
		return
	_begin_attack_recovery_if_needed()
	_set_blink(false)
	_reset_root_follow()
	_skill_teleport = 0.0
	_skill_poise = false
	_skill_reflect = false
	_skill_ranged_guard = false
	_invincible = false
	_hurt_invincible = 0.0
	_ming_zhong_holder = boss
	velocity = Vector2.ZERO
	state = State.HURT
	_hurt_phase = "ming_zhong_hold"
	_hurt_timer = 0.0
	_idle_queued = false
	_play(anim_map["idle"], true)


func release_ming_zhong_hold(boss: Node2D) -> void:
	if boss != _ming_zhong_holder:
		return
	_ming_zhong_holder = null
	if _hurt_phase == "ming_zhong_hold":
		_hurt_phase = ""
	_invincible = false
	_hurt_invincible = maxf(_hurt_invincible, 0.35)
	velocity = Vector2.ZERO
	if state != State.DEAD:
		_set_state(State.FALL)


func apply_ming_zhong_vulnerability() -> void:
	if state == State.DEAD or _saint_immune():
		return
	_ming_zhong_vulnerable_time = 12.0
	var dn := DAMAGE_NUMBER.new()
	dn.setup("易伤 · 12秒", Color(0.9, 0.48, 0.3))
	dn.global_position = global_position + Vector2(0, -165)
	_world_add(dn)


func apply_ming_zhong_holy(stacks: int) -> void:
	if stacks <= 0 or state == State.DEAD or _saint_immune():
		return
	_ming_zhong_holy += stacks
	var dn := DAMAGE_NUMBER.new()
	dn.setup("圣光 · %d/36" % _ming_zhong_holy, Color(0.95, 0.82, 0.38))
	dn.global_position = global_position + Vector2(0, -165)
	_world_add(dn)
	if _ming_zhong_holy < 36:
		return
	hp = 0
	hp_changed.emit(hp, max_hp)
	Feel.hitstop(0.08)
	Feel.shake(10.0, 0.3)
	die() # 圣光审判是直接秒杀，不进入普通伤害与复活结算。


func clear_ming_zhong_effects() -> void:
	if is_instance_valid(_ming_zhong_holder):
		release_ming_zhong_hold(_ming_zhong_holder)
	_ming_zhong_holder = null
	_ming_zhong_vulnerable_time = 0.0
	_ming_zhong_holy = 0


func _ming_zhong_amplify(amount: int) -> int:
	if amount > 0 and _ming_zhong_vulnerable_time > 0.0:
		_ming_zhong_vulnerable_time = 12.0
		return amount + 1
	return amount


## 墨颤后续滑斩不再扣当前生命，而是把生命上限削到当前生命；跨房间仍保留。
func _apply_mo_ting_sunder(attacker: Node, move: Dictionary) -> void:
	var target_max := maxi(1, hp)
	var loss := maxi(0, max_hp - target_max)
	var actual := 0
	if loss > 0:
		if Run.active and Run.max_hp == max_hp:
			actual = Run.lose_max_hp(loss, self)
		else:
			actual = mini(loss, max_hp - 1)
			max_hp -= actual
			hp = mini(hp, max_hp)
			hp_changed.emit(hp, max_hp)
	FX.spawn(get_tree().current_scene, "ink_hit", global_position + Vector2(0, -70), {"scale": 0.45})
	Feel.hitstop(0.04)
	Feel.shake(5.0, 0.16)
	if actual > 0:
		var loss_dn := DAMAGE_NUMBER.new()
		loss_dn.setup("命限削至当前 · -%d" % actual, Color(0.85, 0.42, 0.32))
		loss_dn.global_position = global_position + Vector2(0, -165)
		_world_add(loss_dn)
	if attacker != null and is_instance_valid(attacker) and attacker.has_method("on_player_hit"):
		attacker.call("on_player_hit", 0, move, self)


## 每累计 3 层灼烧，墨霆后续激光基础伤害 +1，最多 +3；6 秒未再命中则清除。
func mo_ting_laser_damage() -> int:
	return 1 + mini(3, int(_mo_ting_burn_stacks / 3))


func _apply_mo_ting_burn() -> void:
	if _saint_immune():
		return
	var old_bonus := mini(3, int(_mo_ting_burn_stacks / 3))
	_mo_ting_burn_stacks = mini(9, _mo_ting_burn_stacks + 1)
	_mo_ting_burn_time = 6.0
	var new_bonus := mini(3, int(_mo_ting_burn_stacks / 3))
	if new_bonus > old_bonus:
		var burn_dn := DAMAGE_NUMBER.new()
		burn_dn.setup("灼烧 · 激光 +%d" % new_bonus, Color(0.9, 0.38, 0.2))
		burn_dn.global_position = global_position + Vector2(0, -175)
		_world_add(burn_dn)


func _mo_ting_burn_tick(delta: float) -> void:
	if _mo_ting_burn_time <= 0.0:
		return
	_mo_ting_burn_time = maxf(0.0, _mo_ting_burn_time - delta)
	if _mo_ting_burn_time <= 0.0:
		_mo_ting_burn_stacks = 0


## 怒焰只在招式真实扣血后叠层；新层按新间隔重启唯一的共享计时器。
func _apply_fen_ding_burn(attacker: Node) -> void:
	if _saint_immune():
		return
	if attacker == null or not is_instance_valid(attacker):
		return
	_fen_ding_burn_stacks += 1
	_fen_ding_burn_source = attacker
	_fen_ding_burn_left = fen_ding_burn_interval()


func fen_ding_burn_interval() -> float:
	if _fen_ding_burn_stacks <= 0:
		return 0.0
	return float(FEN_DING_BURN_INTERVALS[mini(_fen_ding_burn_stacks, FEN_DING_BURN_INTERVALS.size()) - 1])


func clear_fen_ding_burn(boss: Node = null) -> void:
	if boss != null and _fen_ding_burn_source != boss:
		return
	_fen_ding_burn_stacks = 0
	_fen_ding_burn_left = 0.0
	_fen_ding_burn_source = null


## 固定 1 点真实扣血：不写受伤无敌、不进受击状态，也不被普通减伤吞掉。
func _fen_ding_burn_tick(delta: float) -> void:
	if _fen_ding_burn_stacks <= 0 or state == State.DEAD:
		return
	if not is_instance_valid(_fen_ding_burn_source) or int(_fen_ding_burn_source.get("hp")) <= 0:
		clear_fen_ding_burn()
		return
	_fen_ding_burn_left -= delta
	if _fen_ding_burn_left > 0.0:
		return
	if _stolen_dot_immune():
		_fen_ding_burn_left = fen_ding_burn_interval()
		return
	var amount := _ming_zhong_amplify(1)
	var source := _fen_ding_burn_source
	_on_pipa_damaged(source)
	amount = _try_pipa_scapegoat(amount, source)
	var dealt := mini(amount, hp)
	hp -= amount
	hp_changed.emit(hp, max_hp)
	_spawn_number(dealt, DMG_COLOR, 130.0)
	FX.spawn(get_tree().current_scene, "fire_hit", global_position + Vector2(0, -70), {"scale": 0.35})
	if is_instance_valid(source) and source.has_method("on_fen_ding_burn_hit"):
		source.call("on_fen_ding_burn_hit", dealt, self)
	_fen_ding_burn_left = fen_ding_burn_interval()
	if hp <= 0:
		_record_last_hit(source, {"anim": "fen_ding_burn", "hit_at": 0.0}, dealt)
		if _try_revive(Vector2.ZERO):
			return
		die()


## 普通流血：每层每秒 1 伤、持续 3 秒、最多 5 层，新层刷新持续时间；双镰与青笠共用。
func _apply_bleed(layers: int, attacker: Node, move: Dictionary) -> void:
	if layers <= 0 or state == State.DEAD or _saint_immune():
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
	if state == State.DEAD or _stolen_dot_immune():
		return
	var amount := _ming_zhong_amplify(_bleed_stacks)
	var attacker = _bleed_source.get("attacker") as Node
	_on_pipa_damaged(attacker)
	amount = _try_pipa_scapegoat(amount, attacker)
	if _z001_burnout:
		_z001_burnout_take_damage(amount) # 燃尽期间流血同样只扣生命上限
		return
	var dealt := mini(amount, hp)
	hp -= amount
	hp_changed.emit(hp, max_hp)
	_spawn_number(dealt, DMG_COLOR, 130.0)
	FX.spawn(get_tree().current_scene, "ink_hit", global_position + Vector2(0, -70), {"scale": 0.22})
	if hp > 0:
		return
	_record_last_hit(attacker, _bleed_source.get("move", {}), dealt)
	if _z001_enter_burnout():
		return
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
	if _saint_immune():
		return
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
	if state == State.DEAD or _stolen_dot_immune():
		return
	var amount := _ming_zhong_amplify(1)
	var attacker = cut.get("attacker")
	if not is_instance_valid(attacker):
		attacker = null
	_on_pipa_damaged(attacker)
	amount = _try_pipa_scapegoat(amount, attacker)
	var dealt := mini(amount, hp)
	hp -= amount
	hp_changed.emit(hp, max_hp)
	_spawn_number(dealt, DMG_COLOR, 130.0)
	FX.spawn(get_tree().current_scene, "ink_hit", global_position + Vector2(0, -70), {"scale": 0.22})
	if hp > 0:
		return
	_record_last_hit(attacker, cut.get("move", {}), dealt)
	if _try_revive(Vector2.ZERO):
		_cuts.clear()
		_cut_casts.clear()
		return
	die()


## 复活优先级：续命赐福 → 复活墨符（4 血起身）→ 红蝶。
## 红蝶是绯刃固有被动、每局一次，优先级最低，留到没有其他复活资源时再消耗。
## 赐福与复活墨符相互独立，两者齐备时一局可以起身两次。
func _try_revive(knockback: Vector2) -> bool:
	var can_revive := false
	var red_butterfly := false
	var slot := int(input_slot)
	if Run.blessing_of(slot) == "revive" and not Run.blessing_used_of(slot):
		Run.set_blessing_used(slot, true)
		can_revive = true
	elif Run.supply_revive and not Run.supply_revive_used:
		Run.supply_revive_used = true
		can_revive = true
	elif skull_id == "c021" and not Run.c021_red_butterfly_used and has_battle_passive("c021_red_butterfly"):
		red_butterfly = true
		Run.c021_red_butterfly_used = true
		# 上限按「自己槽位的化身」算：本机双人时 Run.max_hp 是 P1 的全局值，
		# 直接拿它给 P2 复活会把红蝶的 100 点压成 P1 的 8 点，起身七八秒就烧没了。
		var butterfly_max := Run.calculated_max_hp(skull_id, slot)
		if slot == 0:
			Run.max_hp = butterfly_max
		max_hp = butterfly_max
		_red_butterfly_left = 1.0
		can_revive = true
	if not can_revive:
		return false
	Achievements.event("revives")
	if max_hp <= 0 and _stolen("c009_madness"):
		var stolen_cap := maxi(1, Run.calculated_max_hp(skull_id, slot))
		if slot == 0:
			Run.max_hp = stolen_cap
		max_hp = stolen_cap
	_clear_bleed()
	_stop_skill_loop()
	fx.clear_all()
	_begin_attack_recovery_if_needed()
	_set_blink(false)
	_reset_root_follow()
	_skill_hits.clear()
	_skill_audio_events.clear()
	_delayed.clear()
	_skill_runtime.clear()
	_skill_name = ""
	_skill_timer = 0.0
	_skill_teleport = 0.0
	_skill_tick_acc = 0.0
	_awaken_pending = 0.0
	_invincible = false
	_skill_poise = false
	_skill_reflect = false
	_skill_ranged_guard = false
	_skill_cancel_ready = false
	_parry_ready = false
	_bell_shell = false
	_shield_hits = 0
	_shield_time = 0.0
	hp = max_hp if red_butterfly else mini(4, max_hp)
	if Run.active:
		Run.set_slot_hp(input_slot, hp)
	_hurt_invincible = 1.5 # 起身喘口气，别立刻又被围殴
	hp_changed.emit(hp, max_hp)
	state = State.HURT
	_hurt_phase = ""
	_hurt_getup_dur = 0.0
	_hurt_timer = float(_anim_durations.get(str(anim_map["getup"]), hurt_time))
	velocity = knockback
	_play(anim_map["getup"], false)
	_queue(anim_map["idle"], true)
	_idle_queued = true
	if red_butterfly:
		fx.attach("E54015", Vector2(0.0, -64.0), "action", false,
			{"scale": 0.5 * _body_fx_scale(), "fx_role": "revive"})
		# 红蝶专属复活音：走完整播放通道，收招/受击短音不会把它截断。
		# 只在本分支触发，赐福复活与复活墨符不会误响。
		_play_full_sfx("assassin_revive", 0.0)
	return true


## 倒地：播倒地动画 → 接起身动画（起身段无敌）。hp 已扣完且未死亡时才走这里
func _start_knockdown(knockback: Vector2) -> void:
	var getup_anim := str(anim_map.get("getup", anim_map["hurt"]))
	var fall_dur := float(_anim_durations.get(_fall_anim, 0.5))
	_hurt_getup_dur = float(_anim_durations.get(getup_anim, 0.5))
	state = State.HURT
	_hurt_phase = "fall"
	_knock_cd = KNOCK_COOLDOWN
	_hurt_timer = fall_dur + _hurt_getup_dur
	velocity = knockback * 0.6
	_idle_queued = false
	_invincible = false
	_play(_fall_anim, false)
	_queue(getup_anim, false)
	_queue(anim_map["idle"], true)
	_idle_queued = true # 起身后 stand 已在队列里，_set_state 只同步不重开


func _spawn_number(amount: int, color: Color, height: float, gated := true) -> void:
	var dn := DAMAGE_NUMBER.new()
	dn.setup(str(amount), color, amount if gated else -1)
	dn.global_position = global_position + Vector2(randf_range(-12.0, 12.0), -height)
	_world_add(dn)


## 完美闪避：冲刺中"本应命中"的伤害全部闪掉，并给收益——
## 冲刺普通冷却立刻回零（仍受闪避后 0.5 秒最小间隔限制）、4s 全伤害 +2（与觉醒共用 buff 槽，取高者）、
## 0.5s 短无敌防同一轮攻击的后段在冲刺结束后立刻命中。
func _perfect_dodge(attacker: Node = null, incoming_damage: int = 0) -> void:
	_dash_cd = 0.0 # 收益一：冷却回零
	_hurt_invincible = maxf(_hurt_invincible, 0.5 + _dodge_time_bonus) # 冲刺窗口只有 0.16s，垫一层防后续段
	_buff_damage = maxi(_buff_damage, 2 + _dodge_bonus) # 收益二：限时加伤（掠影加档）
	_buff_timer = maxf(_buff_timer, 4.0 + _dodge_time_bonus)
	var cd_refund := _dodge_cd_refund
	if skull_id == "c021" and _form_node("c021_shadow_2"):
		cd_refund += 1.0
	if cd_refund > 0.0:
		for n in _skill_cds:
			_skill_cds[n] = maxf(0.0, float(_skill_cds[n]) - cd_refund)
	if skull_id == "c021" and _own("c021_bait_1"):
		_spawn_bait()
	if skull_id == "z000" and _form_node("z000_wind_1"):
		_wind_final = true
	if skull_id == "z000" and _own("z000_listen_1") and attacker != null and is_instance_valid(attacker):
		var p := attacker as Node2D
		if p != null and int(attacker.get("hp")) > 0:
			_openings[p.get_instance_id()] = {"target": p, "time": 5.0}
			# 听锋·初：破绽当场可见、可换血，否则完美闪避后玩家不知道有这张卡
			if p.has_method("take_damage_from"):
				p.call("take_damage_from", 1, self)
			FX.spawn(get_tree().current_scene, "telegraph", p.global_position + Vector2(0, -60), {"scale": 0.5, "mod": Color(0.85, 0.72, 0.42, 0.85)})
			var mark_dn := DAMAGE_NUMBER.new()
			mark_dn.setup("破绽", Color(0.85, 0.72, 0.42))
			mark_dn.global_position = p.global_position + Vector2(0, -140)
			_world_add(mark_dn)
	if skull_id == "c021" and has_battle_passive("c021_flash") and incoming_damage > 0 \
			and attacker != null and is_instance_valid(attacker) and int(attacker.get("hp")) > 0:
		# 闪身只回敬这一段原始伤害，不再叠加玩家加伤；PvP 走专用受击避免被 _damage_enemy 去重
		if pvp_mode and ("pvp_mode" in attacker) and bool(attacker.get("pvp_mode")):
			attacker.call("pvp_apply_damage", incoming_damage, Vector2.ZERO, null)
		else:
			_damage_enemy(attacker, incoming_damage)
	_play_sfx("weapon_sword") # 侧身擦过的嗖声当闪避音
	Achievements.event("perfect_dodges")
	var dn := DAMAGE_NUMBER.new()
	dn.setup("完美闪避", Color(0.9, 0.75, 0.3)) # 金：奖励时刻
	dn.global_position = global_position + Vector2(0, -150)
	_world_add(dn)
	Feel.hitstop(0.04) # 顿一瞬强调"擦过去了"
	Feel.shake(2.0, 0.1)


func die() -> void:
	_z001_burnout = false
	_stop_skill_loop()
	fx.clear_all()
	_mo_ting_grabbed = false
	_passive_seal_time = 0.0
	_stun_time = 0.0
	return_all_sui_yue_passives()
	clear_fen_ding_burn()
	state = State.DEAD
	_dismiss_stolen_sword_clone()
	_clear_scar()
	_clear_plum_zones()
	_clear_return_mark()
	_stolen_death_burst()
	clear_ming_zhong_effects()
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


# ---------- 玩家对战（PVP） ----------

## 普攻/技能到达命中帧时只广播判定参数，由 pvp_rules.gd 结算；
## PvE 路径不读这个信号，pvp_mode 为 false 时完全静默。
func _emit_pvp_strike(spec: Dictionary) -> void:
	if pvp_mode:
		pvp_strike.emit(spec)


## PvP 实际伤害回调（pvp_rules 扣血后调用）：接回“造成实际伤害后”的被动与技能总伤。
## 护盾、反伤、复活保护挡下的攻击不会扣血，因此也不会误触发。
func on_pvp_damage_dealt(amount: int, target: Node) -> void:
	if not pvp_mode or amount <= 0:
		return
	_skill_damage_total += amount
	_on_innate_damage(target, amount)


## PVP 专用受击：按 PvE 的防御顺序接入技能无敌、完美闪避、招架、金刚反伤、受击无敌、
## 金钟罩、圣僧与暗夜；红蝶按回合提供一次复活。只有持续伤害/控制走独立的 PvP 适配层。
func pvp_apply_damage(amount: int, knockback: Vector2 = Vector2.ZERO, attacker: Node = null) -> void:
	if not pvp_mode or state == State.DEAD or amount <= 0:
		return
	if _pvp_revive_guard > 0.0:
		return
	# 技能无敌帧
	if _invincible:
		_invincible_hit_feedback(attacker, {})
		return
	# 完美闪避：冲刺窗口内免伤，并结算闪身等收益
	if state == State.DASH:
		_perfect_dodge(attacker, amount)
		return
	# 回环招架：挡下首次近战并反击控制
	if _parry_ready and attacker != null and is_instance_valid(attacker) and _counter_attack(attacker):
		Achievements.event("parries")
		return
	# 金刚反伤
	if _skill_reflect and attacker != null and is_instance_valid(attacker) and attacker.has_method("pvp_apply_damage"):
		_pvp_reflect_to(attacker, amount)
		return
	# 受击无敌：与 PvE 同序，但用更短的 PvP 窗口避免吞掉连段
	if _hurt_invincible > 0.0:
		_invincible_hit_feedback(attacker, {})
		return
	# 金钟罩
	if _shield_hits > 0:
		_pvp_block_with_shield()
		return
	# 圣僧：单次伤害封顶
	if _saint_immune():
		amount = mini(amount, PvpTuning.SAINT_HIT_CAP)
	# 暗夜：20% 概率免伤
	if skull_id == "z003" and has_battle_passive("z003_night") and randf() < 0.2:
		_passive_block_feedback(attacker, {}, "暗夜", "z003_night")
		return
	if hp - amount <= 0 and _pvp_try_revive():
		_pvp_after_revive()
		return
	hp = maxi(0, hp - amount)
	hp_changed.emit(hp, max_hp)
	_on_pipa_damaged(attacker) # 红尘：实际受伤后给攻击方叠怨
	_z001_on_hit_taken() # 战狂：PvP 受击同样累计
	_hurt_invincible = maxf(_hurt_invincible, PvpTuning.HURT_INVINCIBLE)
	_spawn_number(amount, DMG_COLOR, 130.0, false)
	if hp <= 0:
		velocity = Vector2.ZERO
		die()
		return
	_begin_attack_recovery_if_needed()
	_reset_root_follow()
	state = State.HURT
	_hurt_phase = ""
	_hurt_getup_dur = 0.0
	var pvp_hurt_anim := str(anim_map.get("hurt", ""))
	_hurt_timer = maxf(hurt_time, float(_anim_durations.get(pvp_hurt_anim, hurt_time)))
	_stop_skill_loop()
	fx.clear_skill()
	velocity = knockback
	_idle_queued = false
	_invincible = false
	if pvp_hurt_anim != "":
		_play(pvp_hurt_anim, false)
	_play_sfx("hit_fist")
	FX.spawn(get_tree().current_scene, "ink_hit", global_position + Vector2(0, -70), {"scale": 0.45, "flip": knockback.x > 0.0})
	Feel.hitstop(0.03)
	Feel.shake(2.5, 0.1)


## 金刚反伤：PvP 中挨打不扣血，按原始伤害弹回攻击方；反伤本身不再触发对方反伤。
func _pvp_reflect_to(attacker: Node, amount: int) -> void:
	var reflected := amount + _reflect_bonus
	attacker.call("pvp_apply_damage", reflected, Vector2.ZERO, null)
	var ap := attacker as Node2D
	if ap != null:
		FX.spawn(get_tree().current_scene, "ink_hit", ap.global_position + Vector2(0, -60), {"scale": 0.4})
		var dn := DAMAGE_NUMBER.new()
		dn.setup(str(reflected), Color(0.72, 0.45, 0.3), reflected)
		dn.global_position = ap.global_position + Vector2(0, -140)
		_world_add(dn)
	var guard_dn := DAMAGE_NUMBER.new()
	guard_dn.setup("金刚 · 反伤", Color(0.9, 0.75, 0.3))
	guard_dn.global_position = global_position + Vector2(0, -150)
	_world_add(guard_dn)
	_play_sfx("voice_fan_hit")
	Feel.hitstop(0.05)
	Feel.shake(3.0, 0.1)


## 金钟罩挡下 PvP 一击：与 PvE 同一套反馈，但不进入受击硬直、不打断正在出手。
func _pvp_block_with_shield() -> void:
	_shield_hits -= 1
	if _shield_hits <= 0:
		_shield_time = 0.0
	fx.sync_persistent(state == State.DEAD)
	var shield_dn := DAMAGE_NUMBER.new()
	shield_dn.setup("金钟罩", Color(0.9, 0.75, 0.3))
	shield_dn.global_position = global_position + Vector2(0, -150)
	_world_add(shield_dn)
	FX.spawn(get_tree().current_scene, "ink_hit", global_position + Vector2(0, -70), {"scale": 0.5})
	_play_sfx("golden_bell_block")
	Feel.hitstop(0.06)
	Feel.shake(3.0, 0.1)
	_shield_heal_once()


## 红蝶 PvP 复活：每个回合一次，回半血并清空持续伤害与控制，避免复活即被 DOT 烧死。
func _pvp_try_revive() -> bool:
	if skull_id != "c021" or _pvp_butterfly_used or not has_battle_passive("c021_red_butterfly"):
		return false
	_pvp_butterfly_used = true
	hp = maxi(1, int(roundf(float(max_hp) * PvpTuning.REVIVE_HP_RATIO)))
	_pvp_revive_guard = PvpTuning.REVIVE_GUARD
	_pvp_butterfly_drain = true
	_pvp_butterfly_tick = 0.0
	_pvp_bleed_time = 0.0
	_pvp_bleed_stacks = 0
	_pvp_bleed_acc = 0.0
	_pvp_poison_time = 0.0
	_pvp_poison_acc = 0.0
	_pvp_vuln_time = 0.0
	_pvp_frenzy_time = 0.0
	_pvp_stun_time = 0.0
	_pvp_root_time = 0.0
	_pvp_slow_time = 0.0
	_pvp_slow_scale = 1.0
	_shield_hits = 0
	_shield_time = 0.0
	return true


## 红蝶复活演出：起身 + 红蝶特效 + 专属音效，血量在此之前已经写好。
func _pvp_after_revive() -> void:
	hp_changed.emit(hp, max_hp)
	_stop_skill_loop()
	fx.clear_all()
	_begin_attack_recovery_if_needed()
	_reset_root_follow()
	_skill_name = ""
	_skill_timer = 0.0
	_skill_teleport = 0.0
	_skill_tick_acc = 0.0
	_parry_ready = false
	_bell_shell = false
	state = State.HURT
	_hurt_phase = ""
	_hurt_getup_dur = 0.0
	var getup_anim := str(anim_map.get("getup", anim_map.get("hurt", "")))
	_hurt_timer = float(_anim_durations.get(getup_anim, hurt_time))
	velocity = Vector2.ZERO
	_idle_queued = true
	if getup_anim != "":
		_play(getup_anim, false)
	_queue(anim_map["idle"], true)
	fx.attach("E54015", Vector2(0.0, -64.0), "action", false,
		{"scale": 0.5 * _body_fx_scale(), "fx_role": "revive"})
	_play_full_sfx("assassin_revive", 0.0)
	var dn := DAMAGE_NUMBER.new()
	dn.setup("红蝶", Color(0.78, 0.3, 0.38))
	dn.global_position = global_position + Vector2(0, -165)
	_world_add(dn)
	Feel.hitstop(0.05)


## 回合重置：回满本轮血量，清掉受击/技能/增益残留，再放回出生点。
func pvp_reset(spawn: Vector2) -> void:
	hp = max_hp
	global_position = spawn
	velocity = Vector2.ZERO
	state = State.IDLE
	facing = 1
	_apply_facing()
	# 上一回合可能停在倒地/躺尸动画上，先把 Spine 轨道和待播队列清干净再回待机
	if _anim_state != null and _anim_state.has_method("clear_tracks"):
		_anim_state.call("clear_tracks")
	_pending_anim = ""
	_pending_queue.clear()
	_current_anim = ""
	_hurt_timer = 0.0
	_hurt_phase = ""
	_hurt_getup_dur = 0.0
	_hurt_chain.clear()
	_hurt_seg_left = 0.0
	_hurt_invincible = 0.0
	_hurt_cast_key = ""
	_stun_time = 0.0
	_invincible = false
	_mo_ting_grabbed = false
	_passive_seal_time = 0.0
	_jump_buf = 0.0
	_jump_seal = 0.0
	_dash_seal = 0.0
	_cripple_time = 0.0
	_attack_idx = -1
	_attack_hits.clear()
	_attack_recovery = 0.0
	_attack_queued = false
	_skill_name = ""
	_skill_timer = 0.0
	_shield_hits = 0
	_shield_time = 0.0
	_pvp_butterfly_used = false # 红蝶按回合恢复：每回合都能触发一次
	_pvp_revive_guard = 0.0
	_pvp_butterfly_drain = false
	_pvp_butterfly_tick = 0.0
	_pvp_grudge = 0
	_pvp_heal_cut = false
	_buff_timer = 0.0
	_awaken_time = 0.0
	_idle_queued = false
	return_all_sui_yue_passives()
	clear_fen_ding_burn()
	_dismiss_stolen_sword_clone()
	_clear_scar()
	_clear_plum_zones()
	_clear_return_mark()
	clear_ming_zhong_effects()
	_clear_bleed()
	_stop_skill_loop()
	fx.clear_all()
	_set_blink(false)
	if str(anim_map.get("idle", "")) != "":
		_play(str(anim_map["idle"]), true)
	hp_changed.emit(hp, max_hp)
	_clear_pvp_status()


# ---------- PVP 状态适配：与被 _foes() 遍历到的敌人接口同名 ----------

## 时停分档：玩家在 PVP 中按 BOSS 档位处理，取 stop["boss"] 的时长
func stop_tier() -> String:
	return "boss" if pvp_mode else "mob"


## 时间暂停（将去未还）：无视霸体/前摇直接打断，冻结全部状态计时，到点回报施法者
func time_stop(dur: float, caster: Node = null) -> void:
	if not pvp_mode or state == State.DEAD or dur <= 0.0:
		return
	_pvp_stop_time = maxf(_pvp_stop_time, minf(dur, PvpTuning.TIME_STOP_MAX))
	if caster != null:
		_pvp_stop_caster = caster
	if state != State.HURT:
		_stop_skill_loop()
		_attack_idx = -1
		_attack_hits.clear()
		state = State.IDLE
		_idle_queued = false
		if str(anim_map.get("idle", "")) != "":
			_play(str(anim_map["idle"]), true)
	velocity = Vector2.ZERO


## 定身：可以照常出手，但不能移动
func root(dur: float, _ignore_armor := false) -> void:
	if not pvp_mode or state == State.DEAD or _saint_immune():
		return
	_pvp_root_time = maxf(_pvp_root_time, maxf(0.0, dur * PvpTuning.CONTROL_SCALE))


## 枝界持续约束：每帧延续定身，不重复播控制反馈
func contain(dur: float, ignore_armor := false) -> void:
	root(dur, ignore_armor)


## 硬控：锁定移动与全部操作，并打断正在释放的技能
func stun(dur: float, _ignore_armor := false) -> void:
	if not pvp_mode or state == State.DEAD or _saint_immune():
		return
	_pvp_stun_time = maxf(_pvp_stun_time, maxf(0.0, dur * PvpTuning.CONTROL_SCALE))
	if state != State.HURT:
		_stop_skill_loop()
		state = State.IDLE
		_idle_queued = false
	velocity.x = 0.0


func slow(dur: float, scale := 0.6) -> void:
	if not pvp_mode or state == State.DEAD or _saint_immune():
		return
	_pvp_slow_time = maxf(_pvp_slow_time, dur)
	_pvp_slow_scale = clampf(scale, 0.2, 1.0)


func launch(dir: int, vx: float, vy: float, _ignore_armor := false) -> void:
	if not pvp_mode or state == State.DEAD or _pvp_stop_time > 0.0:
		return
	velocity = Vector2(float(dir) * vx, -vy)
	if is_on_floor():
		_set_state(State.JUMP)


func knock_back(dir: int, force: float, _impact := 1, _ignore_armor := false) -> void:
	if not pvp_mode or state == State.DEAD or _pvp_stop_time > 0.0:
		return
	velocity.x = float(dir) * clampf(force * 0.5, 0.0, 420.0)


## 流血：每层每秒 1 伤，上限 5 层；层数越高 DOT 越疼
func apply_bleed(layers := 1) -> void:
	if not pvp_mode or state == State.DEAD or _saint_immune():
		return
	_pvp_bleed_stacks = mini(BLEED_MAX, _pvp_bleed_stacks + maxi(1, layers))
	_pvp_bleed_time = maxf(_pvp_bleed_time, BLEED_DUR * PvpTuning.BLEED_SCALE)


## 中毒：每秒 1 伤，持续 dur 秒
func apply_poison(dur: float) -> void:
	if not pvp_mode or state == State.DEAD or _saint_immune():
		return
	_pvp_poison_time = maxf(_pvp_poison_time, dur)


## 易伤：期间受到的所有伤害按 ratio 放大（与对战基础系数叠乘）
func apply_vulnerable(dur: float, _ratio := 0.25) -> void:
	if not pvp_mode or state == State.DEAD or _saint_immune():
		return
	_pvp_vuln_time = maxf(_pvp_vuln_time, dur)


## 躁动：期间受到的伤害小幅放大（给 frenzy 类技能一个 PVP 收益）
func apply_frenzy(dur: float, _empower := false) -> void:
	if not pvp_mode or state == State.DEAD or _saint_immune():
		return
	_pvp_frenzy_time = maxf(_pvp_frenzy_time, dur)


## 摄心：1v1 中转为短硬控（不回血、不叛变），时长受对战控制系数与 2 秒上限约束
func apply_charm(dur: float) -> void:
	if not pvp_mode or state == State.DEAD or _saint_immune():
		return
	_pvp_stun_time = maxf(_pvp_stun_time, minf(dur * PvpTuning.CONTROL_SCALE, 2.0))
	if state != State.HURT:
		_stop_skill_loop()
		state = State.IDLE
		_idle_queued = false
	velocity.x = 0.0


## 心魔引爆：把六感引爆折算为一次固定伤害（PvE 的六感层数机制不搬进 1v1）
func detonate_mind(base_damage: int, _from_x := 0.0, _boosted := false) -> void:
	if not pvp_mode or state == State.DEAD:
		return
	_pvp_tick_damage(maxi(1, base_damage))


## 转移负面：1v1 中按类别落成流血/硬控/定身/易伤，保证 z002 的引爆链不空转
func apply_transferred_debuff(info: Dictionary) -> void:
	if not pvp_mode or state == State.DEAD or _saint_immune():
		return
	match str(info.get("id", "")):
		"bleed", "cut", "fen_ding_burn":
			apply_bleed(maxi(1, int(info.get("stacks", 1))))
		"stun":
			stun(maxf(float(info.get("time", 0.0)), 1.0), true)
		"jump_seal", "dash_seal", "cripple":
			root(maxf(float(info.get("time", 0.0)), 1.0), true)
		_:
			_pvp_vuln_time = maxf(_pvp_vuln_time, maxf(1.0, float(info.get("time", 1.0))))


## 邪佛神伤：延长现有负面状态，并追加一段易伤
func amplify_debuffs() -> void:
	if not pvp_mode or _saint_immune():
		return
	_pvp_bleed_time *= 1.5
	_pvp_poison_time *= 1.5
	_pvp_frenzy_time *= 1.5
	_pvp_vuln_time = maxf(_pvp_vuln_time, 4.0)


## 邪佛压场：自身造成的伤害折算降低
func set_evil_buddha_pressure(on: bool) -> void:
	if pvp_mode:
		_pvp_pressure = on


## 换房诅咒：一次性给现有技能冷却加 1.5 秒
func apply_room_cd_curse() -> void:
	if not pvp_mode or _pvp_cd_cursed or _saint_immune():
		return
	_pvp_cd_cursed = true
	for n in _skill_cds:
		_skill_cds[n] = float(_skill_cds[n]) + 1.5


## 受击方伤害倍率（易伤/躁动），由 pvp_rules 与自身 DOT 结算读取
func pvp_damage_taken_scale() -> float:
	var s := 1.0
	if _pvp_vuln_time > 0.0:
		s *= PvpTuning.VULN_SCALE
	if _pvp_frenzy_time > 0.0:
		s *= PvpTuning.FRENZY_SCALE
	return s


## 攻击方伤害倍率（邪佛压场），由 pvp_rules 读取
func pvp_damage_scale() -> float:
	return PvpTuning.PRESSURE_SCALE if _pvp_pressure else 1.0


## 攻击方固定加伤（局外称号 + 目标特化），由 pvp_rules 在倍率结算后追加。
func pvp_flat_damage_bonus(target: Node) -> int:
	var bonus := Achievements.bonus_int("damage")
	if skull_id == "z001":
		bonus += _z001_fury # 战意：全部伤害追加等量焚烧
	if target == null or not is_instance_valid(target):
		return bonus
	if skull_id == "c023" and _form_node("c023_venom_2") and float(target.get("_pvp_poison_time")) > 0.0:
		bonus += 1 # 淬毒·续：目标身上有毒时每段 +1
	if skull_id == "z003" and _form_node("z003_chase_2") \
			and target.has_method("is_on_floor") and not bool(target.call("is_on_floor")):
		bonus += 1 # 追风·续：目标浮空时每段 +1
	return bonus


## 红尘：每 3 层怨使自身每段伤害 -1（由 pvp_rules 在倍率阶段扣除）
func pvp_grudge_penalty() -> int:
	return int(_pvp_grudge / 3) if pvp_mode else 0


## 红尘叠怨：绛弦受到实际伤害后调用
func add_grudge(layers: int) -> void:
	if not pvp_mode or layers <= 0:
		return
	_pvp_grudge += layers
	_spawn_passive_text("怨 %d" % _pvp_grudge, Color(0.72, 0.42, 0.78))


## 剑宗：被剑仙实际伤害后治疗减半，持续到本回合结束
func apply_sword_sect() -> void:
	if not pvp_mode or _pvp_heal_cut:
		return
	_pvp_heal_cut = true
	_spawn_passive_text("剑宗 · 减疗", Color(0.55, 0.78, 0.82))


func _pvp_status_tick(delta: float) -> void:
	if not pvp_mode:
		return
	_pvp_revive_guard = maxf(0.0, _pvp_revive_guard - delta)
	# 时停：彻底冻结（含 DOT 与其他控制计时），到点回报施法者
	if _pvp_stop_time > 0.0:
		_pvp_stop_time = maxf(0.0, _pvp_stop_time - delta)
		if _pvp_stop_time <= 0.0:
			var caster := _pvp_stop_caster
			_pvp_stop_caster = null
			if is_instance_valid(caster) and caster.has_method("on_time_stop_end"):
				caster.call("on_time_stop_end", self)
		return
	# 红蝶：复活后的每秒生命流失（时停期间冻结，与 PvE 一致）
	if _pvp_butterfly_drain and state != State.DEAD:
		_pvp_butterfly_tick += delta
		while _pvp_butterfly_tick >= 1.0 and state != State.DEAD:
			_pvp_butterfly_tick -= 1.0
			hp = maxi(0, hp - 1)
			hp_changed.emit(hp, max_hp)
			_spawn_number(1, DMG_COLOR, 130.0, false)
			if hp <= 0:
				velocity = Vector2.ZERO
				die()
	if state == State.DEAD:
		return
	_pvp_root_time = maxf(0.0, _pvp_root_time - delta)
	_pvp_stun_time = maxf(0.0, _pvp_stun_time - delta)
	_pvp_slow_time = maxf(0.0, _pvp_slow_time - delta)
	if _pvp_slow_time <= 0.0:
		_pvp_slow_scale = 1.0
	_pvp_vuln_time = maxf(0.0, _pvp_vuln_time - delta)
	_pvp_frenzy_time = maxf(0.0, _pvp_frenzy_time - delta)
	if _pvp_bleed_time > 0.0 and _pvp_bleed_stacks > 0:
		_pvp_bleed_time = maxf(0.0, _pvp_bleed_time - delta)
		_pvp_bleed_acc += delta
		while _pvp_bleed_acc >= 1.0 and _pvp_bleed_stacks > 0:
			_pvp_bleed_acc -= 1.0
			_pvp_tick_damage(_pvp_bleed_stacks)
			if state == State.DEAD:
				return
		if _pvp_bleed_time <= 0.0:
			_pvp_bleed_stacks = 0
			_pvp_bleed_acc = 0.0
	if _pvp_poison_time > 0.0:
		_pvp_poison_time = maxf(0.0, _pvp_poison_time - delta)
		_pvp_poison_acc += delta
		while _pvp_poison_acc >= 1.0:
			_pvp_poison_acc -= 1.0
			_pvp_tick_damage(1)
			if state == State.DEAD:
				return


## PVP 持续伤害：直扣血、不进受击硬直；致命时同样先走红蝶复活，复活失败才统一死亡
func _pvp_tick_damage(amount: int) -> void:
	if not pvp_mode or state == State.DEAD or amount <= 0:
		return
	if _pvp_revive_guard > 0.0:
		return
	amount = maxi(1, int(roundf(float(amount) * pvp_damage_taken_scale())))
	if _saint_immune():
		amount = mini(amount, PvpTuning.SAINT_HIT_CAP)
	if hp - amount <= 0 and _pvp_try_revive():
		_pvp_after_revive()
		return
	var dealt := mini(amount, hp)
	hp = maxi(0, hp - amount)
	hp_changed.emit(hp, max_hp)
	_spawn_number(dealt, DMG_COLOR, 130.0, false)
	if hp <= 0:
		velocity = Vector2.ZERO
		die()


func _clear_pvp_status() -> void:
	_pvp_stop_time = 0.0
	_pvp_stop_caster = null
	_pvp_root_time = 0.0
	_pvp_stun_time = 0.0
	_pvp_slow_time = 0.0
	_pvp_slow_scale = 1.0
	_pvp_bleed_time = 0.0
	_pvp_bleed_stacks = 0
	_pvp_bleed_acc = 0.0
	_pvp_poison_time = 0.0
	_pvp_poison_acc = 0.0
	_pvp_vuln_time = 0.0
	_pvp_frenzy_time = 0.0
	_pvp_pressure = false
	_pvp_cd_cursed = false
	_pvp_grudge = 0
	_pvp_heal_cut = false
	_pvp_butterfly_drain = false
	_pvp_butterfly_tick = 0.0


# ---------- 内部工具 ----------

## 普攻无论是打完整段、移动/闪避取消，还是被技能与受击打断，都进入同一恢复窗口。
func _attack_recovery_active() -> bool:
	return _attack_recovery > 0.0 and not (skull_id == "c023" and has_battle_passive("c023_frost_plum"))


func _begin_attack_recovery_if_needed() -> void:
	if state != State.ATTACK:
		return
	if not (skull_id == "c023" and has_battle_passive("c023_frost_plum")):
		# 收招硬直 0.7s：只锁“再次起手普攻”，不锁技能/移动/闪避，
		# 比原来的 1.0s 更贴合连续作战节奏，又不会快到能无限连。
		_attack_recovery = maxf(_attack_recovery, 0.7)
	_attack_queued = false
	_attack_hits.clear()


func _post_move() -> void:
	_stolen_wall_tick()
	if state == State.DEAD:
		return
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
				# 分段跳跃：落地瞬间补一帧落地动画（烬生要求落地必播 57；其他形态跑动着地直接接 run 更顺）
				var land := str(anim_map.get("jump_land", ""))
				if _jump_seg and land != "" and (absf(velocity.x) <= 10.0 or skull_id == "z001"):
					_play(land, false)
					_queue(anim_map["idle"], true)
					_idle_queued = true
					_set_state(State.IDLE)
					return
				_set_state(State.RUN if absf(velocity.x) > 10.0 else State.IDLE)


func _set_state(new_state: int) -> void:
	if state == new_state:
		return
	if state == State.SKILL:
		_stop_skill_loop()
		fx.clear_skill()
	_begin_attack_recovery_if_needed()
	state = new_state
	match state:
		State.IDLE:
			if _idle_queued:
				# 自动接续不会经过 _play，也要在轨道换代前保存完整旧姿势。
				if _pose_mixer != null:
					_pose_mixer.capture()
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
				# 分段跳跃：起跳跳一帧起跳动画，空中换上升/下降姿态，落地另有落地帧
				if state == State.JUMP:
					if anim_map.has("jump_start"):
						_play(anim_map["jump_start"], false)
						_queue(anim_map.get("jump_mid", anim_map["air"]), true)
					else:
						_play(anim_map.get("jump_mid", anim_map["air"]), true) # 无起跳过渡：直接上升姿态
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
	net_anim_loop = loop
	if loop and anim == _current_anim:
		return # 循环动画同名重放 = 从头再来一遍，跳跃顶点会抽搐
	if _pose_mixer != null:
		if _pending_anim.is_empty():
			_pose_mixer.capture()
		_current_anim = anim
		_pending_anim = anim
		_pending_loop = loop
		_pending_speed = spd
		_pending_queue.clear()
		return
	_current_anim = anim
	var entry = _anim_state.call("set_animation", anim, loop, 0)
	if spd != 1.0 and entry != null and entry.has_method("set_time_scale"):
		entry.call("set_time_scale", spd)


func _queue(anim: String, loop: bool) -> void:
	if _anim_state == null:
		return
	if _pose_mixer != null and not _pending_anim.is_empty():
		_pending_queue.append({"anim": anim, "loop": loop})
		return
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
