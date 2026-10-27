# 墨构 InkConstruct · 项目进度与路线图

> Godot 4.6.2 mono + spine-godot 4.2 水墨国风 Roguelite 横版动作
> 更新日期：2026-10-27

---

## 一、已实现 ✅

### 核心玩法

| 模块 | 文件 | 核心能力 |
|---|---|---|
| 玩家控制器 | `scripts/player/player.gd` + `scripts/player/skulls.gd` | 多化身（4 形态：刀客 / 弓手 / 法师 / 弓弩手）各自独立骨架、普攻段、技能表、HUD 技能栏；普攻连段、多段技能命中（双刺闪扫路径判定）、dash、jump、coyote、受伤无敌 |
| 手感系统 | `scripts/systems/combat_feel.gd` | hitstop 顿帧、屏幕震、受击白闪；player 三档加速度（`accel` 启动 / `brake` 制动 / `turn_accel` 反向转向，均 `@export` 可调）、lunge 惯性（`brake*0.5` 代替 `accel` 秒刹）、hit_at × 0.9 提前判定、预警泛红闪 0.2s（原 0.35s） |
| 小怪 AI | `scripts/enemies/c016.gd` + `scripts/enemies/enemy_types.gd` | 形态表驱动的巡逻 / 追击 / 挑招式 / 出手令牌 / 攻击锁定 / 受击硬直分层（普通 vs 精英霸体）；range_probe 标定 ranges + hit_at |
| Boss 系统 | `scripts/enemies/boss.gd` + `scripts/enemies/boss_types.gd` | 五真身（墨霆巨兽骑手 C009 / 焚鼎紫焰巨汉 C015a1 / 武车双马战车 C001 / 碎岳墨甲巨汉 C008 / 鸣钟双斧武者 C032）；多阶段切换（血量阈值）+ 变身无敌 + 僵直窗口（奖励输出）+ 冲锋技（蓄力→碾压→撞墙大硬直）；C032 自带 transform/transform1/transform2 三套变身动画，P2/P3 各演一套；HUD 大血条；`ROSTER` 随机登场 |
| 特效系统 | `scripts/systems/fx.gd` | GIF 精灵条逐帧播放器，12 条特效（ink_hit / ink_claw / slash / pillar / tiger / thunder / fire_pillar / speedline / crack / gather / vanish / fire_hit）；Boss fx 配置表驱动（登场 / 变身 / 冲锋拖尾 / 撞墙 / 受击）+ 焚鼎 P3 封锁火区（聚气预警 → 火柱喷发 → 范围灼烧） |
| 房间流程 | `scripts/world/room_01.gd` + `scripts/systems/run_state.gd` | 三层推进（普通房×2 → Boss 房）；`RoomIndex` + `is_boss_room` 路由；Boss 房换幽谷背景 + 暗色宫殿剪影 |

### UI / 数据

| 模块 | 文件 | 说明 |
|---|---|---|
| HUD | `scripts/ui/hud.gd` | 大血条 + 技能冷却遮罩 |
| 结算 | `scripts/ui/settlement_panel.gd` | 通关 / 阵亡结算 |
| 化身面板 | `scripts/ui/swap_panel.gd` | 暂停时换头 |
| 赐福 | `scripts/ui/blessing_panel.gd` | 开局三选一 |
| 强化 | `scripts/ui/upgrade_panel.gd` | 中途三选一 |
| 伤害数字 | `scripts/ui/damage_number.gd` | 飘字 |
| 局外养成 | `scripts/systems/meta.gd` | 击杀 / 通关计数；契合度 Lv1/Lv2/Lv3 加伤 + 冷却 + 免费 |

### 素材管线

| 文件 | 说明 |
|---|---|
| `tools/gif2strip.py` | GIF → 水平精灵条 PNG + JSON |
| `tools/key_alpha.py` | 按背景色距离重建 alpha（解决老 GIF 无透明通道坑） |
| `tools/contact_sheet.py` | 精灵条重排网格接触表供人工预览 |

### 测试场景

| 场景 | 用途 |
|---|---|
| `scenes/tests/room_test.tscn` | 主循环冒烟（刷怪 / 战斗 / 换头 / 化身 / 面板 / 结算） |
| `scenes/tests/boss_test.tscn` | Boss 真身全链路（`$env:BOSS_ID=c009\|c015a1\|c001\|c008\|c032\|_debug`） |
| `scenes/tests/settlement_clear_test.tscn` | 通关结算 |
| `scenes/tests/settlement_dead_test.tscn` | 阵亡结算 |
| `scenes/tests/fx_test.tscn` | 特效总览 |
| `scenes/tests/range_probe.tscn` | 骨架伸展峰值探针 |
| `scenes/tests/anim_list.tscn` | 骨架动画清单 |

---

## 二、遗留坑 ⚠️

| 坑 | 严重度 | 位置 | 说明 |
|---|---|---|---|
| Boss 火区只在 chase / idle 状态触发 | 低 | `boss.gd` `_fz_tick` | 冲锋 / 变身 / 僵直期间 `_fz_tick` 走不到——逻辑对，但意图要写清楚 |
| c001 武车 stun / charge 复用 stop 动画 | 低 | `boss_types.gd` `c001.charge` | 骨架 stun 是空帧，撞墙自晕姿势用 `stop`；视觉上就是急停 pose，缺一段更"撞懵了"的动画 |
| spine_probe 标定命中位置未对齐玩家 hitbox | 低 | 全局 | ranges 是"骨架伸展像素 × scale"，hit_at 是"峰值时刻"；但玩家 hitbox 只有 70px 高、120-130px 范围——boss 277-580px 的 range 实际只打半个房间，数值大但合理（Boss 要远程威慑） |
| re-import 后 Godot 偶发 "No loader found" | 低 | 全局 | 删除 png 后没清 .import，`--import` 能自动修；但删掉 birds.png / palace_dark.png 后如果用户本地已有 .import cache，F5 可能报 "Can't load texture"——下次改完素材记得先 `--import` |
| project.godot 注释只认 `;` 不认 `#` | 中 | `project.godot` | `#` 注释行会让整个 section 静默解析失败（设置项丢失、引擎零报错）。曾因 `[gui]` 段 `#` 注释导致全局字体主题丢失；排障用 `scripts/tests/font_probe.gd` 探针断言 |

---

## 三、待开发路线图 🔜

### P0 · 玩家手感收尾（1-2 天）

- [x] **小怪也上三档加速度**：c016 新增 `accel/brake/turn_accel`（1300/1700/2100），巡逻/追击从瞬时变速改为渐加速，反向转向走 turn_accel；攻击 lunge 改用 `brake*0.5` 半速制动带惯性（对齐玩家手感）
- [x] **玩家攻击后期可取消**：`_attack_tick` 在本段 hits 全结算后、lock 后 30%（`atk["cancel"]` 可调）允许提前接下一招 / 移动 / dash
- [ ] **hitstop 强度分档**：普攻 0.045s、技能 0.06s、Boss 命中 0.08s 已够；弹反场景（未来）要单独 0.12s
- [x] **清 room_01.gd / run_state.gd 的两个 Invalid access**：根因是当时 player.gd 语法错误 → 实例化成裸 CharacterBody2D；已补 `has_signal("died")` / `has_method("set_upgrades")` 守卫，再发生时报清晰错误而非刷屏

### P1 · Boss 房视觉完整（2-3 天）

- [ ] **五个 Boss 房独立背景**：现在只有一张 `bg_boss.png` 通吃，应该 c009（巨兽山巅） / c015a1（焚鼎熔炉） / c001（战车校场） / c008（碎岳山门） / c032（鸣钟古阁）各一张
- [x] **Boss 登场演出强化**：镜头拉远 → 缓推回（`Feel.intro_zoom`）、大血条延迟淡入、Boss 名书法大字中央定格弹出后淡去（`hud._splash_boss_name`）；boss_test 回归通过
- [ ] **焚鼎 P3 火区视觉优化**：fire_hit 打完玩家身上那一下现在只是一个橙色炸开——应该加持续 0.4s 灼烧 DOT 视觉（不做真实 DOT 伤害，只视觉）

### P2 · 新内容（看素材库）

- [ ] **额外化身**：素材库玩家骨架多的话，加第 5 / 6 个形态
- [ ] **精英怪独立 AI 行为**：现在精英只是参数放大；可以加"蓄力重击"预警 1.5s 然后冲过来砸地（需要新骨架动画）
- [ ] **关卡装饰系统**：随机生成 3-5 个可互动场景（卷轴回血、香炉加墨骨、石碑加临时 buff）

### P3 · 系统层

- [ ] **投射物特效**：现在 `projectile.gd` 用 `_draw` 直接画轨迹，硬编码圆形；改为从精灵条生成弹道（墨弹 / 火球 / 雷矢）
- [ ] **音效全覆盖**：现在只有 hit_qi / voice_sword_hit / voice_skill_cast / hit_fist 四个，Boss 技能命中 / 火区爆炸 / 玩家 dash 都还没音效
- [ ] **结算面板强化**：加本局化身战绩、Boss 击杀统计、"契合度经验 +XX" 视觉条

### P4 · 打磨

- [x] ~~存档文件持久化~~：meta.gd 已实现 `user://meta.json`（JSON 存累计击杀/通关/契合经验），此条为过时记录
- [ ] **正式启动场景**：现在 F5 直接进 room_01，缺 main_menu → blessing → room_01 的正式流程
- [ ] **移动端适配**：当前 1280×720 PC 分辨率，UI 按钮没考虑触摸

---

## 四、命令行速查

```powershell
# 回归 room_test
& "E:\Godot\Godot_v4.6.2-stable_mono_win64.exe" --path "e:\GodotProjects\ink-construct" "res://scenes/tests/room_test.tscn"

# Boss 真身冒烟（五选一）
$env:BOSS_ID = "c009"  # 或 c015a1 / c001 / c008 / c032 / _debug
& "E:\Godot\Godot_v4.6.2-stable_mono_win64.exe" --path "e:\GodotProjects\ink-construct" "res://scenes/tests/boss_test.tscn"

# 重导素材（删 png 后必跑）
& "E:\Godot\Godot_v4.6.2-stable_mono_win64.exe" --path "e:\GodotProjects\ink-construct" --import

# 骨架探针
& "E:\Godot\Godot_v4.6.2-stable_mono_win64.exe" --path "e:\GodotProjects\ink-construct" "res://scenes/tests/range_probe.tscn"
```

> 拷素材只认 `E:\素材\墨构素材库\暗黑武侠水墨风人物Spine...\Character\<ID>`（4.2.11，可直接导入）；
> `E:\素材\暗黑武侠水墨风人物Spine...`（不带"墨构素材库"前缀）是 **3.6.53 原版**，拷进来会导入失败、`.skel.import` 显示 `valid=false`。

## 五、目录速查

```
scripts/
├── player/          # 玩家控制器 + 化身形态表
├── enemies/         # 小怪 c016 + 小怪形态表 + Boss boss.gd + Boss 形态表
├── systems/         # fx 特效 + run_state + combat_feel + meta
├── ui/              # hud + settlement + swap + blessing + upgrade + damage_number
├── world/           # room_01
└── tests/           # 测试场景脚本

art/
├── characters/
│   ├── enemies/     # 小怪骨架 + atlas
│   └── bosses/      # c009 / c015a1 / c001 / c008 / c032 骨架 + atlas
├── fx/              # 12 条精灵条特效（.png + .json）
└── environment/     # decor + background（bg_boss.png / bg_green.png）

tools/               # gif2strip / key_alpha / contact_sheet 素材管线
scenes/tests/        # 测试场景（见上表）
tests/out/           # 回归截图 + 日志
```

---

## 六、项目约束（别忘）

- **投射物特效用户不自理**：空闲就修改 `projectile.gd` 的 `_draw` 视觉
- **中文注释**：全项目中文注释
- **WTE 规范**：preload 不用 `class_name`、函数内不能声明 `const`
- **GIF → 精灵条**：spine-godot 4.2 不兼容老 Spine 3.8 GIF，统一走 `tools/gif2strip.py` + `key_alpha.py`

## 最重要
用户有无限的素材资源，想要查看或者使用啥的直接跟用户说想要看看新素材，我把整个文件给你你自己决断，当然，里面的spine版本可能比较低，你选好你想要的然后告诉我，我帮你转换成spine4.2版本
