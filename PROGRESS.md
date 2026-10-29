# 墨构 InkConstruct · 项目进度与路线图

> Godot 4.6.2 mono + spine-godot 4.2 水墨国风 Roguelite 横版动作
> 更新日期：2026-10-29（本文档已与代码现状全面对齐）

---

## 一、已实现 ✅

### 核心玩法

| 模块 | 文件 | 核心能力 |
|---|---|---|
| 玩家控制器 | `scripts/player/player.gd` + `scripts/player/skulls.gd` | **5 形态换头**（双刺·冷红绫 c021 / 梅剑·白疏影 c023 / 力僧·定山 c013 / 剑仙·洛惊鸿 z000 / **银夜·将去未还 z003**，默认 c021；青笠 c012 已下架转精英怪）：各自独立骨架、普攻段、技能表、HUD 技能栏；普攻连段、多段技能命中、投射物（剑仙剑气）、blink 闪现、dash、jump、coyote、受伤无敌；Q 键呼出化身面板（暂停中选头，墨骨结算，契合 Lv3 免费）。技能支持可选字段：`poise`（自身霸体）/ `reflect`（技能期间无敌，伤害原样反弹给攻击者）/ `heal`（砸地回血，力僧 U 用）/ `ranged_guard`（远程免疫并反弹敌方投射物）/ `tick`（技能持续伤害段：窗口内每 interval 秒对前后方范围结算一次）/ `pool`（随机抽动画池，普攻段与技能均支持，锁定 = 抽中动画真实时长）/ `launch`（普攻段击飞）/ `knockback`（命中击退 + 碰撞组合伤害）/ `stop`（时间暂停分档 mob/elite/boss，无视霸体）/ `buff_damage`+`buff_time`（觉醒加伤 buff，全伤害路径生效）/ `sword_qi`（剑气远程接口预留，未实装）/ `qinggong`（轻功：jump_mul 跳高倍率 + hover 顶点悬停，银夜专属）；普攻 `hits` 支持字典段 `{at, damage, range, pull, sfx}`（旧格式纯秒数仍兼容），`pull` 命中后把敌人拽到身前。技能命中控制通用字段：`root`（定身：只锁移动）/ `stun`（晕眩：锁移动 + 锁出手 + 立即打断正在起的招）/ `self_shield`（自身金钟罩：免一次攻击或限时自动消失）/ 形态表 `knock_chain`（重受击倒地链，段间按动画真实时长无缝接续，最后一段起身整段无敌）。**力僧定位站桩重击**：普攻 = `skill02_01`（第 16 号，2 伤）+ `skill02_03`（第 18 号，3 伤）两段；K = `skill01` 两段（横扫 3 伤 + 击退 620/撞人 1 伤 + 落点定身 2s；第二段不造成伤害、改给自己金钟罩免一次/8s）；L = `skill03`（3 伤 + 晕眩 2s）；U = 定山（反伤 + 回血）；奔跑第 19 号、闪避第 15 号（0.583s 整段完美闪避）；受击 1→第 1 号 / 2→第 6 号 / ≥3→第 6→3→5→9 号整链起身；武僧无残血待机。**梅剑定位数值怪**：普攻 = `skill01` 两段（鞭击 2 点拉回 80px + 前刺 3 点），唯一技能 = `skill02` 放 K 位。**银夜定位机制怪**：三段普攻随机池（段2 击飞）、K 蓄力霸体、L 击退组合伤害、U 时停、I 觉醒回血加伤、O 位移斩杀 600px |
| 手感系统 | `scripts/systems/combat_feel.gd` | hitstop 顿帧、屏幕震、受击白闪；player 三档加速度（`accel`/`brake`/`turn_accel` 均 `@export`）、lunge 惯性（`brake*0.5`）、hit_at × 0.9 提前判定、预警泛红闪 0.2s；攻击后 30% 可取消窗口（`atk["cancel"]` 可调） |
| 小怪 AI | `scripts/enemies/c016.gd` + `scripts/enemies/enemy_types.gd` | 形态表驱动巡逻/追击/挑招式/出手令牌/攻击锁定/受击硬直分层（普通 vs 精英霸体）；三档加速度对齐玩家手感；range_probe 标定 ranges + hit_at；**多段命中**（`hit_at`/`ranges` 支持数组按段结算）、`damage` 每招伤害、`poise_atk` 出手霸体（挨打掉血不断招）、`lunge_mul` 前冲倍率、`hop` 起手跃起、`enrage` 半血狂暴（冷却×cd、追速×speed，触发一次）；**FLY 状态**（击飞/击退共用：重力抛物线，击退撞同伴手动距离判定双方各吃 impact、撞墙自己吃，落地回硬直）；**`time_stop` 时停**（sprite.process_mode=DISABLED 冻结动画 + 主循环早退，时长按 mob/elite 分档，时停中伤害照算、打死先解冻再 die）；**控制接口 `root(dur)` 定身**（只锁移动、照常出手）与 **`stun(dur)` 晕眩**（锁移动 + 锁出手 + 立即掐掉前摇并交还出手令牌；Boss 时长减半、自定义状态期间不生效） |
| 敌人池 | `scenes/enemies/`（全部复用 c016.gd） | 小怪 4 种：c016 刀客 / z002 黑袍剑客 / c017 蛮兵 / c035 刺客；精英 3 种：c037_elite 大剑骑士 / c018_elite 双镰 / **c012_elite 青笠剑客（前玩家形态转生）**。**除青笠外主角形态不设同名敌人版本**（原 c023_elite 落梅弓手已删，与梅剑共用美术） |
| 波次刷怪 | `scripts/systems/wave_spawner.gd` | 波次表由 `Run.room_config()` 提供：**冒险**每房 2 波（5~7 只，血量速度递增 + 精英混入）；**无尽**波数/血量/速度/精英数随层数抬升（`Run.endless_waves`）。同屏上限 6，死一只补一只，波间喘息 1.6s；清完发 `all_cleared`。精英血量走「形态表基础值 × `hp_mul`」`configure({"hp_mul": ...})`，普通怪用绝对 `hp` |
| Boss 系统 | `scripts/enemies/boss.gd` + `scripts/enemies/boss_types.gd` | 五真身（墨霆巨兽骑手 C009 / 焚鼎紫焰巨汉 C015a1 / 武车双马战车 C001 / 碎岳墨甲巨汉 C008 / 鸣钟双斧武者 C032）；多阶段切换 + 变身无敌 + 僵直窗口 + 冲锋技 + **绕后转身演出**（配 `turn` 动画的 Boss 被穿裆时播调头动画再翻转朝向，不瞬转，转身期不还手是奖励窗口，带冷却防锁死）；C032 三套变身动画分 P2/P3；HUD 大血条 + 登场书法落款 + 运镜推拉；`ROSTER` 随机登场；每形态独立主题背景整图铺底；**时停可打断冲锋/技能前摇**（boss 档 1s，变身演出冻结不取消）；**霸体免疫击退/击飞**（`launch`/`knock_back` 覆盖为空） |
| 特效系统 | `scripts/systems/fx.gd` | GIF 精灵条逐帧播放器，12 条特效；Boss fx 配置表驱动 + 焚鼎 P3 封锁火区（聚气预警 → 火柱喷发 → 范围灼烧）；预警用程序化墨环（`tools/gen_telegraph.py`） |
| 房间流程 | `scripts/world/room_01.gd` + `scripts/systems/run_state.gd` | **两种模式**：冒险 = 3 普通房（波次清怪）→ Boss 房 → 通关结算；**无尽 = 每层都是「3 小关 + 1 Boss」**，Boss 倒下补墨骨 + 一次强化，前进即 `depth+1` 重开三小关、换一只 Boss（血量每层 ×1.4、出手冷却每层 ×0.94，最低 0.6）。每清一房花墨骨强化三选一；首房出发前排赐福三选一（一局一次，无尽跨层不再弹）；Boss 房按形态换主题背景（`BOSS_BG` 表）；普通房固定 4 棵远景树点缀 |
| 墨骨掉落 | `scripts/systems/bone_pickup.gd` | 敌人死亡掉墨骨：上抛落地 → 玩家靠近 95px 自动吸附 → 收下；14s 无人拾取消失；纯 `_draw` 墨点不依赖素材 |
| 关卡互动装饰 | `scripts/world/decor_interactive.gd` | 普通房随机刷 2-3 个可互动物件：卷轴回血 +1 / 香炉 +5 墨骨 / 石碑本房临时 buff（伤害 +2 或移速 ×1.25，换房自动失效）；走近 90px 自动触发 → decor_burst 爆开特效 + 飘字 + 音效（decor_pickup / decor_stele）→ 消失；香炉待机挂 decor_idle_fire 白焰 loop。**本体是程序化 `_draw` 临时绘制（偏简陋），待用户找到好素材整件替换（见 P1 标记）** |

### 经济 / 养成

| 模块 | 文件 | 说明 |
|---|---|---|
| 局内计数 | `scripts/systems/score.gd`（autoload Score） | 连击（窗口清零）/ 最高连击 / 击杀 / 墨骨；墨骨跨房间保留，开新局才清空；花墨骨 = 局内强化 + 换头 |
| 局外养成 | `scripts/systems/meta.gd`（autoload Meta） | `user://meta.json` 持久化；**敌人 / Boss 击杀收录 `seen` 表**（`add_enemy_kill(id)` / `enemy_kills(id)`，`c016.die()` 统一记账，Boss 走 `super()` 继承）；**解锁按强度梯度（双刺 < 力僧 < 梅剑 < 剑仙 < 银夜）**：双刺初始开放 → 力僧累计击杀 20 → 梅剑累计击杀 60 → 剑仙通关冒险 1 次 → **银夜通关冒险 3 次 + 累计击杀 150**（压轴）。通关计数只记冒险模式（无尽不计通关，击杀照常累计）；契合度 Lv1(30) 冷却-10% / Lv2(80) 普攻+1 / Lv3(150) 化身免费 |
| 墨锭商栈 | `meta.gd` `INK_SHOP` + `forms_panel.gd` | 结算时本局剩余墨骨沉淀为局外货币**墨锭**；化身谱面板内消费：买断解锁（绕过条件）+ 永久开局加成（初始墨骨/生命上限，可升级） |

### UI / 流程

| 模块 | 文件 | 说明 |
|---|---|---|
| 主菜单 | `scripts/ui/main_menu.gd` | **启动场景**（`project.godot` run/main_scene）：水墨远山底 + 书法标题 + 开始/化身谱/图鉴/设置/退出（5 键，y 330/402/474/546/618，260×56）；启动时 `Settings.apply_all()`。「开始游戏」不再直接进房间，改为弹开始面板 |
| 开始面板 | `scripts/ui/start_panel.gd` + `scenes/ui/start_panel.tscn` | **两步开局**：① 选模式（冒险 / 无尽卡片）② 选角色（`Skulls.ids()` 强度顺序 5 张，未解锁整卡压暗 + 显示解锁条件与实时进度，已解锁显示契合等级）。选中即 `Run.start(模式, 形态)` → 切 `room_01.tscn`；Esc / 上一步可回退 |
| 化身谱 | `scripts/ui/forms_panel.gd` | 主菜单入口：5 形态解锁条件/契合进度/各级加成一览 + 墨锭商栈 |
| 图鉴 | `scripts/ui/codex_panel.gd` + `scenes/ui/codex_panel.tscn` | 主菜单入口：左栏收录卡（2 列 × 6 行）分**敌人 / 化身**两页——敌人只收击败过的（未打过压暗 ？？？，Boss 追加在杂兵精英之后）；右栏预览台 + 名称/分类/生命/击败次数 + **背景故事**（`LORE` 表，现为占位文案）+ 动作条（4 列网格）。**鼠标悬停任一条 → SpineSprite 循环播该动画**（普攻 / 招式 / 技能 K-L-U-I-O / 待机奔跑冲刺滞空受击倒地；Boss 含三阶段招式并集 + 变身），说明行同步显示机制标签与紧凑数值（`1.33s ｜ 144px ｜ 1伤`）；数值全部由形态表 / 敌人表自动生成 |
| 暂停菜单 | `scripts/ui/pause_menu.gd` | Esc 呼出：继续 / 设置 / 回主菜单 |
| 设置 | `scripts/ui/settings.gd` + `settings_panel.gd` | 音乐/音效音量（Music/SFX 总线）、全屏、分辨率（1280×720 / 1600×900 / 1920×1080）；`user://settings.cfg` 持久化，改动立即生效 |
| HUD | `scripts/ui/hud.gd` | 大血条 + 技能冷却遮罩 + 连击/墨骨 + **顶部中央模式标签**（`冒险 · 1/3` / `无尽 · 第 2 层 · 2/3` / Boss 房写 `Boss`） |
| 结算 | `scripts/ui/settlement_panel.gd` | 通关/阵亡结算 + 战绩行（最高连击/击杀/墨骨）+ 朱砂「讨伐 · Boss 名」+ 契合经验条动画 + 墨锭沉淀；**结算栏旁挂当前形态化身**（通关从 profile `victory` 池随机播一遍转待机 / 阵亡播 dead 接 dead_hold 循环躺尸，SpineSprite `process_mode=ALWAYS` 对抗暂停，无 victory 配置的形态 = 接口 fallback 只待机） |
| 换头面板 | `scripts/ui/swap_panel.gd` | Q 键呼出，暂停时间选形态 |
| 赐福 / 强化 | `scripts/ui/blessing_panel.gd` / `upgrade_panel.gd` | 开局三选一 / 每房清完墨骨三选一。**通用池 6 张机制卡**（锋锐/静心/铁骨/轻骨/疾影/掠影，cost = 8+4×等级）+ **形态流派 45 张**（5 形态 × 3 流派 × 初/续/极，T2/T3 需前置 req，价格 8/14/20，一局 3 次强化正好走完一条流派）；`roll_cards` 保证「续卡 + 新流派 + 通用」各一张；流派卡只对当前形态生效（换头休眠，`player._apply_form_mods` 按 forms 过滤）；卡面按流派配色（朱砂/墨青/赭金）+ 右上角层级；卡牌图标 `art/ui/icons/` |
| 伤害数字 | `scripts/ui/damage_number.gd` | 飘字 |
| 字体 | `art/ui/fonts/main_theme.tres` + `hud.gd` | 全局庞门正道粗书体；Boss 落款/大血条名 = 演示佛系体（ASCII 文件名：slidefu_regular / pangmen） |

### 音频

| 模块 | 文件 | 说明 |
|---|---|---|
| BGM | `scripts/audio/bgm.gd`（autoload BGM） | 双 AudioStreamPlayer 交叉淡化（0.9s）；menu = 御风引（home.wav）/ battle = 破阵（battle.wav）；Music 总线；同名曲目不重播，暂停不中断；WAV 循环靠导入参数 loop_mode=2 |
| 音效 | `audio/sfx/` ~28 条 wav | 玩家：普攻起手 weapon_sword、命中 voice_sword_hit、技能起手 voice_skill_cast、各技能命中按 skulls 表 `sfx` 字段（hit_heavy / skill_fist / voice_fan_hit / skill_blade 等）、受伤 hit_fist、**冲刺 dash_step**；敌人：telegraph 预警、hit_qi 受击；Boss：boss_entrance 登场、**冲锋碾压 boss_skill_hit、火区喷发 fire_burst**；UI：click 全覆盖、swap_draw、level_up、settle/win/lose；拾取 pickup/gold |

### 素材管线

| 文件 | 说明 |
|---|---|
| `tools/gif2strip.py` | GIF → 水平精灵条 PNG + JSON |
| `tools/key_alpha.py` | 按背景色距离重建 alpha |
| `tools/contact_sheet.py` | 精灵条重排网格接触表供人工预览 |
| `tools/gen_telegraph.py` | 程序化生成预警墨环（根治 gather 贴图脏底） |
| `tools/png2strip.py` | PNG 序列 → 水平精灵条通用管线（按文件名数字排序，`--align bottom/center`） |

### 测试场景（`scenes/tests/`）

| 类别 | 场景 |
|---|---|
| 主循环冒烟 | `room_test.tscn` |
| Boss | `boss_test.tscn`（`BOSS_ID=c009\|c015a1\|c001\|c008\|c032\|_debug`）、`boss_bg_tour.tscn`（五房背景巡游）、`boss_cand_probe.tscn` |
| 结算 | `settlement_clear_test.tscn` / `settlement_dead_test.tscn`（阵亡分支会先换成银夜再死，断言 `Run.skull_id` 保留 = 「再来一局」不会掉回双刺） |
| 特效/音效 | `fx_test.tscn`、`sfx_preview.tscn` |
| 骨架探针 | `range_probe.tscn`、`spine_probe.tscn`、`spine_test.tscn`、`hit_probe.tscn`、`hook_probe.tscn`、`anim_list.tscn`（自动扫描全部骨架 → `tests/anim_list.log`）、`anim_viewer.tscn`（可视化查看器：←→ 切骨架、↑↓ 切动画、空格重播、L 循环）、`anim_sheet.tscn`、`anim_event_probe.tscn`、`face_check.tscn` |
| 战斗/UI 交互 | `combat_test.tscn`、`player_test.tscn`、`enemy_test.tscn`、`enemy_hit_test.tscn`、`skill_test.tscn`、`skill_preview.tscn`、`twitch_test.tscn`、`ui_test.tscn`（主菜单 → 设置 → 化身谱截图 → 模拟购买重建后再用真鼠标点「返回」→ 图鉴两页：造 `Meta.add_enemy_kill` 记录后开面板、悬停断言 `_current_anim` 变化、Boss 详情、切化身页、真鼠标返回）、`settings_test.tscn`、`font_probe.tscn` |
| 开局流程（真鼠标） | `start_flow_test.tscn`：把主菜单挂进来，用 `push_input(ev, true)` 发真实鼠标/键盘事件点一遍「开始游戏 → 模式卡 → 上一步 → 返回 → 连点 → Esc」。**`pressed.emit()` 不走 BaseButton 输入路径，模拟不出真实点击的崩溃，UI 回归优先用这个** |
| **试炼场（调试单挑）** | **`sandbox.tscn`**：一块空地 + 任选敌人单挑，调技能机制/动画/判定专用。[/] 换玩家形态、,/. 轮换敌人（小怪+精英+Boss，直接读两张形态表，新增怪自动进表）、R 重刷敌人；双方无限血（999999）；启动 1s 自动存 `tests/out/sandbox_boot.png` 供回归验收，`-- --shot` 跑完整自动巡游 |

---

## 二、遗留坑 ⚠️

| 坑 | 严重度 | 位置 | 说明 |
|---|---|---|---|
| Boss 火区只在 chase / idle 状态触发 | 低 | `boss.gd` `_fz_tick` | 冲锋 / 变身 / 僵直期间 `_fz_tick` 走不到——逻辑对，但意图要写清楚 |
| c001 武车 stun / charge 复用 stop 动画 | 低 | `boss_types.gd` `c001.charge` | 骨架 stun 是空帧，撞墙自晕姿势用 `stop`；视觉上就是急停 pose，缺一段更"撞懵了"的动画 |
| spine_probe 标定命中位置未对齐玩家 hitbox | 低 | 全局 | ranges 是"骨架伸展像素 × scale"，hit_at 是"峰值时刻"；但玩家 hitbox 只有 70px 高、120-130px 范围——boss 277-580px 的 range 实际只打半个房间，数值大但合理（Boss 要远程威慑） |
| re-import 后 Godot 偶发 "No loader found" | 低 | 全局 | 删除 png 后没清 .import，`--import` 能自动修；改完素材记得先 `--import` 或删 `.godot/imported` 对应 ctex 再开编辑器重导 |
| project.godot 注释只认 `;` 不认 `#` | 中 | `project.godot` | `#` 注释行会让整个 section 静默解析失败（设置项丢失、引擎零报错）。曾因 `[gui]` 段 `#` 注释导致全局字体主题丢失；排障用 `scripts/tests/font_probe.gd` 探针断言 |
| 跑测试前必须先查 Godot 进程 | 高 | 全局 | **标准前置动作**：任何 `--path` 跑场景之前，先 `Get-Process | Where-Object { $_.ProcessName -like "*Godot*" }`。有进程且命令行是 `--editor` = 用户在本机测试，**立刻停手等用户关**，不要硬跑（硬跑必报 `sandbox backend failed`，且会白烧排查时间）。用户开着编辑器玩耍不受我们影响，避让责任在 agent |
| 编辑器开着玩时不要跑回归 | 中 | 全局 | 编辑器重扫/重导会让运行中实例骨架加载失败，玩家死亡 → 结算暂停 → 测试挂死。**重跑一次即恢复**；回归前最好让用户关编辑器。**新表现（2026-10-28 实测）：编辑器开着时命令行跑场景直接报 `sandbox backend failed`（IDE 沙箱中间层被项目文件锁搞崩），不是权限拒绝、也不是项目代码问题。判别三步：①`echo` 正常 ②`Godot --version` 正常 ③`Godot --path 项目 --quit` 必崩 → 查进程里有没有 `--editor` 的 Godot 在跑，有就是它占着项目，关掉即可，**别再怀疑沙箱基础设施或引擎版本** |
| 技能 `hits[].at` 不能超过动画时长 | 中 | `skulls.gd` | 命中按计时器 `t >= at` 触发，而 t 最大只到动画时长；at 填超了整段命中永远不结算、且零报错（力僧定山 at=3.12 > 时长 3.05 曾把 U 的伤害整个丢掉，只剩站桩）。`player.gd` `_skill_tick` 退出帧已加"剩余命中段补结算"兜底，但新填数值仍应保证 `at <= 时长` |
| 力僧 U「定山」定位 | 低 | `skulls.gd` c013 | 蓄力 3.05s 期间**自身无敌 + 按实际伤害反弹**（`reflect` 字段：挨多少原样弹回攻击者，自身 0 掉血；`hurt` 第三参 `attacker` 传入）；砸地**不造成伤害**，只回 2 血（`heal` 字段，与是否命中无关），9s 冷却——站着吃招、惩罚近战的坦克循环 |
| push 报连接重置的排查顺序 | 中 | 全局 | 症状 `Recv failure: Connection was reset` / `Connection timed out`。按序查：①`git config --get http.proxy` 看是否写死代理 ②`curl.exe -x <代理> -I https://github.com` 测代理能否到目标站 ③代理通但 git 不通 → 换代理协议（HTTP ↔ SOCKS5，**两个方向都翻过车**：曾实测 socks5h 可用 http 被重置，2026-10-28 夜又反过来了——用 `git -c http.proxy=<另一协议>://127.0.0.1:33210 push` 临时换，别急着改固化配置）④协议通了仍失败 → `http.version=HTTP/1.1`。本仓库已固化 `socks5h://127.0.0.1:33210` + `HTTP/1.1`；**梯子关掉时 GitHub 直连完全不通（443 超时），必须开着梯子** |
| 骨架动画数 ≠ 可做技能数 | 中 | `skulls.gd` | 梅剑 c023 共 17 个动画，去掉受击/倒地/起身/移动后，真正能挥的只有 `skill01`、`skill02`；`animation` 只有 0.383s 撑不起招式、`"2"`（1.683s）名字像攻击实测是**持剑站姿**（四帧几乎不动）。**最终定版（2026-10-28）**：不硬凑技能位，梅剑改"数值怪"——普攻借 `skill01` 做两段（鞭击拉回 + 前刺，lock 锁满 1.883s、cancel=0，普攻间隔就是动画时长），唯一技能 `skill02` 从 U 位改到 K 位。新增技能前先跑 `anim_viewer.tscn` 看动作本身，别只看名字和时长 |
| 技能只能在 IDLE/RUN 起手 | 中 | `player.gd` `_try_skill` | `_try_skill()` 只在 `_ground_move`（IDLE/RUN）里调用，判定期间按技能键会被静默吞掉。回归脚本硬编码等待（如按完普攻等 1.0s 再按技能）一旦落在上一招锁定里，整个技能就测不到，表现为"数据对但 state 不动"。`player_test.gd` 已加 `_wait_free()`：每次按键前等 `_player.state <= 1`，新测试照抄 |
| spine 加载打印 "Resource file not found: 目录" | 低 | 全局 | 每次 `_setup_spine` 都会打 3 条 ERROR（`res://art/characters/player` / `res:///art/characters/player/` / `Can't load texture`），全部形态与敌人都有——路径是**目录**不是 .tres，属 spine-godot 附件贴图的既有噪音。已核实 `*_data.tres`、`skeleton.atlas`、`.import`、`.godot/imported` 产物齐全且截图贴图正常。**别误判成资源损坏去修** |
| `bin/windows/~` 前缀 DLL 残留 | 低 | 全局 | `~xxx.dll` / `~RF*.TMP` 是 Windows 替换 GDExtension DLL 被占用中断留下的备份，编辑器正常关闭后可删；编辑器在跑时别删（正在用） |
| 特效锚点分两派 | 低 | `scripts/systems/fx.gd` LIB | `pivot` 字段：bottom（pillar/tiger/fire_pillar/crack/gather/vanish，pos=脚底）vs center（ink_hit/ink_claw/slash/thunder/speedline/fire_hit，pos=中心）。受击爪痕在**来袭侧**、冲锋拖尾 `off_y` 按体型抬到躯干、撞墙 crack 炸在墙根 |

---

## 三、待开发路线图 🔜

### P1 · 收尾

- [ ] **互动物件本体换素材**（用户标记）：卷轴/香炉/石碑现在是程序化 `_draw` 临时绘制，太简陋；用户找到好素材后整件替换（结构不动，只换 `decor_interactive.gd` 的 `_draw` 为贴图渲染）
- [ ] **焚鼎 P3 火区灼烧视觉**：fire_hit 打完玩家身上那一下现在只是一个橙色炸开——应该加持续 0.4s 灼烧 DOT 视觉（不做真实 DOT 伤害，只视觉）
- [ ] **投射物特效**：`projectile.gd` 用 `_draw` 硬编码圆形轨迹；改为从精灵条生成弹道（墨弹 / 火球 / 雷矢）——用户明确点名过，剑仙剑气已在用投射物
- [x] **音效补缺**：dash → `dash_step`（Voice_jiaobu）、Boss 冲锋碾压命中 → `boss_skill_hit`（Hit_zhong）、火区喷发 → `fire_burst`（Skill_baozha），均已接入并回归通过

### P2 · 新内容（看素材库）

- [ ] **补第 5 席化身**：青笠 c012 已下架（动画撑不起招式、强度垫底，用户判定），骨架已转生为精英怪；用户从素材库自选新角色填补（SKULLS 加一项 + spine 三件套即可，参考交接笔记 2026-10-28 夜）
- [ ] **精英怪独立 AI 行为**：精英已有参数放大 + 青笠的出手霸体/跃起/狂暴；可以再加"蓄力重击"预警 1.5s 然后冲过来砸地（需要新骨架动画）

### P3 · 系统层

- [ ] **hitstop 弹反档**：普攻 0.045s、技能 0.06s、Boss 命中 0.08s 已够；弹反场景（未来）要单独 0.12s

### P4 · 打磨

- [ ] **移动端适配**：当前 1280×720 PC 分辨率（设置里可选到 1080p），UI 按钮没考虑触摸

---

## 四、命令行速查

```powershell
# 回归 room_test
& "E:\Godot\Godot_v4.6.2-stable_mono_win64.exe" --path "e:\GodotProjects\ink-construct" "res://scenes/tests/room_test.tscn"

# Boss 真身冒烟（五选一）
$env:BOSS_ID = "c009"  # 或 c015a1 / c001 / c008 / c032 / _debug
& "E:\Godot\Godot_v4.6.2-stable_mono_win64.exe" --path "e:\GodotProjects\ink-construct" "res://scenes/tests/boss_test.tscn"
# 注意：经 MCP 启动时环境变量传不进去，需临时把 boss_test.gd L26 的 "_debug" 硬编码成目标 id，跑完还原

# 重导素材（删 png 后必跑）
& "E:\Godot\Godot_v4.6.2-stable_mono_win64.exe" --path "e:\GodotProjects\ink-construct" --import

# 骨架探针
& "E:\Godot\Godot_v4.6.2-stable_mono_win64.exe" --path "e:\GodotProjects\ink-construct" "res://scenes/tests/range_probe.tscn"
```

## 素材库地图（`E:\素材\墨构素材库\`，新增素材也放这里）

| 目录 | 内容 | 用途 |
|---|---|---|
| `暗黑武侠水墨风人物Spine…167套…\Character\<ID>` | 人物骨架三件套（**spine 4.2.11，可直接导入**） | 化身 / 小怪 / 精英 / Boss |
| `Y700手绘水墨风格UI界面设计素材\` | Icons / HUD / 按钮 / 窗口等手绘水墨 UI 切图 | UI、互动装饰小件图标 |
| `国风修仙技能特效…\国风修仙技能特效CG美术素材\` | UI特效 / 场景特效 / 战斗特效（spine） | 技能特效、场景光效、弹道素材候选 |
| `音效\` | ~110 条 wav：Skill_* / Hit_* / Voice_* / Battle_* / Common_* / BGM | 音效补缺全在这拿（见下） |
| `map\` | 横版场景图（7 张水墨风已用于背景；Battle*Map 为欧美风暂不适用） | 房间背景 |
| 两个字体目录 | 庞门正道粗书体 / 演示佛系体 | 已接入 |

> 音效补缺对应素材：dash → `Voice_jiaobu.wav`（脚步）；火区爆炸 → `Skill_baozha.wav`；Boss 技能命中 → `Hit_zhong.wav` 或按武器选 `Skill_wuqi_*`；互动装饰拾取 → `Common_huode.wav`；石碑/卷轴触发 → `Voice_tupo.wav` / `Common_jiesuo.wav`。

> 拷人物骨架只认 `E:\素材\墨构素材库\暗黑武侠水墨风人物Spine...\Character\<ID>`（4.2.11，可直接导入）；
> `E:\素材\暗黑武侠水墨风人物Spine...`（不带"墨构素材库"前缀）是 **3.6.53 原版**，拷进来会导入失败、`.skel.import` 显示 `valid=false`。

## 五、目录速查

```
scripts/
├── player/          # 玩家控制器 + 化身形态表（4 形态）
├── enemies/         # 通用小怪 AI c016.gd + 形态表 + Boss boss.gd + Boss 形态表
├── systems/         # fx 特效 + run_state + combat_feel + meta + score + wave_spawner + bone_pickup + projectile
├── audio/           # bgm.gd（autoload，双轨交叉淡化）
├── ui/              # main_menu / forms_panel / codex_panel / pause_menu / settings(+panel) / hud / settlement / swap / blessing / upgrade / damage_number / ink_tex
├── world/           # room_01
└── tests/           # 测试场景脚本

scenes/
├── ui/              # main_menu / forms_panel / codex_panel / pause_menu / settings_panel / hud / settlement / swap / blessing / upgrade
├── enemies/         # c016 / z002 / c017 / c035 + c037_elite / c018_elite / c012_elite + bosses/boss
├── player/          # player.tscn
├── world/           # room_01.tscn
└── tests/           # 测试场景（见上表）

audio/
├── music/           # home.wav（御风引·菜单）/ battle.wav（破阵·战斗）+ plot_01/02
├── bgm/             # bgm_menu.ogg / bgm_battle.ogg（备用）
└── sfx/             # ~28 条音效 wav

art/
├── characters/
│   ├── player/      # 5 形态骨架（skulls/<id>/ 三件套；c012 已搬到 enemies/）
│   ├── enemies/     # 小怪骨架 + atlas
│   └── bosses/      # c009 / c015a1 / c001 / c008 / c032 骨架 + atlas
├── fx/              # 12 条精灵条特效（.png + .json）+ telegraph 墨环
├── ui/              # fonts / menu 窗口贴图
└── environment/     # decor + background（bg_main / bg_boss + 五张 Boss 主题图）

tools/               # gif2strip / key_alpha / contact_sheet / gen_telegraph 素材管线
tests/out/           # 回归截图 + 日志
```

---

## 六、项目约束（别忘）

- **⚠️⚠️ 不确定就先问用户，问清再动手（用户强调，最重要）**：需求里任何含糊、有歧义、或需要自行设计/平衡的地方（动画选哪一条、数值给多少、机制怎么设计、文案怎么改），**先向用户确认，得到明确答复再改代码**；不许凭猜测直接实装，也不许"先做了再说"。确认过的结论要在交接笔记里写清楚。
- **⚠️ 术语统一：玩家位移动作一律叫「闪避」（用户强调）**：图鉴、强化卡描述、面板提示等**一切玩家能看到的文案**里只能写「闪避」，「冲刺」二字不许出现在界面文本中。代码内部字段 / 枚举 / 注释（`State.DASH`、`dash_time`、`dash_speed`、`_perfect_dodge` 等）保持原名不动。
- **⚠️ 新模型必须可浏览（用户强调）**：任何新人物骨架三件套必须放进 `art/characters/` 下并 `--import` 重导——`anim_viewer.tscn` 递归扫描该目录自动收录，**实装新角色/敌人/精英/Boss 时必须开查看器确认能浏览全部动画**；若素材放到其他目录，必须同步扩大 `anim_viewer.gd` 的 `ROOT` 扫描范围，不许出现"实装了但查看器里看不到"的情况
- **⚠️ 受击体积跟体型走（用户强调，一律这样处理）**：所有角色挨打判定 = **攻击方射程 + 目标 `body_radius`**（边缘到边缘），体型越大挨打面越大——主角/小怪/精英/Boss 全部适用。`body_radius` 是角色字段（c016.gd / player.gd 基座声明，形态表 enemy_types.gd / boss_types.gd / skulls.gd 按体型逐个配，缺省 30）：小怪 28~40，精英 36~40，Boss 55~300（武车 711px 宽配 300，瘦高鸣钟只给 75）。判定共 7 处全走这条规则：玩家普攻 `_deal_hit` / 技能 `_deal_skill_hit`（path 与普通两分支）/ 持续段 `_deal_skill_tick` / 投射物 `projectile.gd` / 小怪 `_deal_hit` / Boss 冲锋 `_charge_hit_check`。**新角色/敌人/Boss 实装时必须按体型配 `body_radius`，不许出现"模型巨大但受击判定只有一点"**；物理碰撞胶囊不动（绕后穿裆机制依赖小胶囊）
- **⚠️ 新建可操控角色必须预留这四组接口（用户强调，以后每个新角色都按这个留）**：`skulls.gd` 的形态项一律带上下面这些字段，哪怕动画还没定也要留位置——`player.gd` 已通用读取，**不配就自动退回旧行为**，不会崩：
  ```gdscript
  "anim": {
      # ... idle/run/dash/air/hurt/dead
      "hurt": "轻受击动画",        # 伤害 < heavy 阈值（第 6 号那类短受击）
      "hurt_heavy": "重受击动画",  # 伤害 ≥ heavy 阈值（第 11 号那类大受击）
      "fall": "倒地动画",          # 伤害 ≥ knockdown 阈值：倒地（第 10 号那类）
      "getup": "起身动画",         # 倒地后立刻接起身（第 17 号那类）
      "low_idle": "残血待机动画",  # 血量 ≤ low_hp_ratio 时替换普通待机（第 32 号那类）
  },
  "dash_time": 0.5,    # 闪避时长 = 闪避动画真实长度（整段都是完美闪避判定窗口）
  "dash_speed": 340.0, # 闪避位移速度，配合时长控制总距离
  "hurt_tiers": {"heavy": 2, "knockdown": 3}, # 伤害 ≥2 播重受击；≥3 直接倒地
  "low_hp_ratio": 0.2, # 血量比例 ≤20% 切残血待机
  ```
  细则：① `hurt_heavy` 缺省 = 用 `hurt`；`fall` 为空 = 没有倒地机制；`low_idle` 为空 = 始终普通待机。② 受击 / 倒地 / 起身的状态时长一律按**动画真实长度**（`_anim_durations` 缓存），不许手填秒数。③ 倒地流程 = fall 播完自动接 getup，**起身段整段无敌**，全程 `State.HURT`，结束回 IDLE/FALL。④ 闪避动画多长，完美闪避窗口就多长（`dash_time` 必须等于该动画时长）。⑤ 参考样板就是 c021（双刺，已全量实装）。
- **⚠️ 效果验收走用户肉眼（用户强调：别反复自测烧积分）**：需要确认"动画行不行 / 机制对不对 / 效果好不好"时，**直接告诉用户开哪个场景、按哪些键、看哪个点**（例："开 sandbox.tscn，,/. 切到武车，J 砍马屁股看能否命中"），用户看完直接给结果——不许自己一遍遍跑场景截图来回试。能自己一次跑完的（日志断言类回归：player/enemy/room/boss_test）照旧自测；**肉眼验收类才走用户**
- **投射物特效用户不自理**：空闲就修改 `projectile.gd` 的 `_draw` 视觉
- **随机池段锁定 = 抽中动画真实时长**：普攻段/技能配了 `pool` 时，出招先抽动画、再按动画名查各自的 `hit_at`/`range` 字典；攻击锁定走 `_attack_lock`（抽中动画的真实时长）——**pool 段没有 `lock` 键，直接读段配置会崩**
- **控制效果分两档（用户定调）**：时停 = 规则级控制，**无视霸体**（连 Boss 冲锋/技能前摇都打断回 IDLE，变身演出只冻结不取消）；击退/击飞 = 物理级，Boss 霸体免疫。新控制效果实装前先定档
- **击退/击飞的撞人判定走手动距离检测**：同伴 ghost 机制会关掉敌人之间的物理碰撞，"击退撞其他敌人触发组合伤害"必须手动算距离（撞墙仍用 `is_on_wall`）
- **hurt() 是玩家唯一受伤入口**：小怪/Boss/Boss 冲刺/投射物全部走 `_target.hurt(...)`——给玩家加"受击侧"机制（闪避/反弹/免伤）只改 player.gd 的 hurt() 一处即可全覆盖。冲刺期碰到伤害=**完美闪避**（全免 + 冲刺冷却清零 + 4s 全伤害 +2 与觉醒共用 buff 槽取高者 + 0.5s 垫底无敌防同轮后续段）
- **技能 hits 同样支持 launch/knockback**：位移效果统一走 `_skill_kinetic`（`_deal_skill_hit` path/普通两分支都调用），与普攻 `_deal_hit` 同规则（尸体不动）——新技能直接配键即可
- **技能通用配置键（player.gd 已支持）**：`speed`（轨道级变速，`_play` 的 time_scale 只作用本条动画；时刻表不用缩放，`_skill_tick` 用动画时间 `(_skill_dur-_skill_timer)*_skill_speed` 对齐）、`hit_at`/`range` 字典（池技能按抽中动画逐段标定）、`align_max`（池内短动画慢放撑满最长时长）、`teleport_anims`（自带位移动画原地播放、收招帧瞬移整段距离再补结算）、`invincible`（整技无敌）；dash 短动画用形态级 `dash_anim_speed` 慢放填满冲刺窗口
- **暂停里要动的 SpineSprite 必须 `process_mode=ALWAYS`**：`get_tree().paused` 期间默认全冻结，结算面板化身、换头面板预览这类"暂停中仍要播动画"的节点都得显式设 ALWAYS
- **中文注释**：全项目中文注释
- **WTE 规范**：preload 不用 `class_name`、函数内不能声明 `const`
- **GIF → 精灵条**：spine-godot 4.2 不兼容老 Spine 3.8 GIF，统一走 `tools/gif2strip.py` + `key_alpha.py`
- **⚠️ 新素材来了走「接入流水线」**：见下一节。它和「开 anim_viewer 看动画」「开 sandbox 无限血单挑」同级别——**每个新素材都要走完这几步才算实装**，不许只在表里登记就完事

### 新素材接入流水线（来素材照这个走）

**第 0 步 · 确认 Spine 版本**：只认 **4.2.11**（`E:\素材\墨构素材库\...` 下那份）；库里**不带「墨构素材库」前缀**的是 3.6.53 原版，直接拷会导入失败（`.skel.import` 的 `valid=false`）——先让用户转 4.2，别硬拷。

**第 1 步 · 落盘 + 重导**：骨架进 `art/characters/` 对应子目录、特效进 `art/fx/`、UI 进 `art/ui/`、背景进 `art/environment/background/`、音效进 `audio/sfx/`；凡是新增/替换图片，一律跑一次 `--import`（命令见「四、命令行速查」）。

**第 2 步 · 登记表**（数据驱动，别把数值写进逻辑）：

| 素材 | 放哪 | 登记位置（一处都不能漏） |
|---|---|---|
| 玩家化身骨架 | `art/characters/player/skulls/<id>/` | `skulls.gd`：`SKULLS` 一项（label/name/data/scale/anim/attacks/skills/hud_skills）+ `ORDER`；`meta.gd`：`UNLOCKS` 条件 + `INK_SHOP` 买断；**第 6 个形态还要改排板**——`start_panel.gd` `x=80+i*228`、`forms_panel.gd` `70+i*232` 现在只够 5 张 |
| 小怪 / 精英 | `art/characters/enemies/<id>/` | `enemy_types.gd` `TYPES` 一项 + `scenes/enemies/<id>.tscn`（只改 `type_id`，碰撞胶囊跟体型）+ `wave_spawner.gd` 的 `NORMAL_SCENES`/`ELITE_SCENES` + `codex_panel.gd` 的 `ENEMY_ORDER`（漏了图鉴左栏就没有它） |
| Boss | `art/characters/enemies/bosses/<id>/` | `boss_types.gd` `BOSSES` 一项 + `ROSTER`（开局随机池，图鉴自动收录）；`room_01.gd` `BOSS_BG` 一项（背景图 + `ground` 地面线）；Boss 招式按阶段写在 `phases` 里 |
| 技能 / 场景特效 | `art/fx/`（先 `gif2strip.py` / `png2strip.py` 转水平精灵条） | `fx.gd` `FX` 表一项（tex / frames / fps / pivot），再按名引用到 `skulls.gd` / `boss_types.gd` 的 `fx` 字段 |
| UI 切图 | `art/ui/...` | 统一 `InkTex.load()`（不要 `Image.load_from_file`，导出后读不到）；面板沿用 `window_large.png` + `btn_normal/btn_clicked.png` |
| 音效 / BGM | `audio/sfx/`、`audio/music/` | 音效在形态/敌人/Boss 表里配 `sfx` 字段；UI 面板用常驻 `_sfx`（重建时不能一起 free）；BGM 走 `bgm.gd` 双轨交叉淡化 |
| 背景图 | `art/environment/background/` | Boss 房写 `room_01.gd` `BOSS_BG`（`ground` 要与画中地面线对齐）；普通房间沿用房间背景表；欧美风 `Battle*Map` 不适用 |

**第 3 步 · 标定**（数值必须实测，不许估）：
- **scale**：像素探针量骨架 `scale=1` 时的墨迹高度；化身形统一按 128px 算（`scale = 128 / 原始高度`），敌人 / 精英 / Boss 按造型大小定，别让换头时体型突变。
- **`body_radius` 跟体型走**（项目约束已有）：小怪 28~40、精英 36~40、Boss 55~300。
- **`hit_at` / `ranges`**：开 `range_probe.tscn` 逐帧看武器完全伸到最远端的时刻与真实像素，写进表里（随机池段写 `hit_at`/`range` 字典）。

**第 4 步 · 三级验收**（缺一不可）：
1. **`anim_viewer.tscn` 能浏览全部动画**——新骨架必须在 `art/characters/` 下被递归扫到；放别处就同步扩大 `anim_viewer.gd` 的 `ROOT`。实装完打不开查看器 = 不算实装（用户明确强调过）。
2. **`sandbox.tscn` 无限血单挑**——`[` / `]` 换玩家形态（直接读形态表）、`,` / `.` 轮换敌人（小怪 + 精英 + Boss 全自动进表）、`R` 重刷；在这个场里把新角色的普攻、每段技能、受击、倒地都打一遍（无限血随便试）。
3. **图鉴里能点开并悬停播动画**——新增敌人 / 化身 / Boss 都要在 `codex_panel` 里出现且每个动作悬停播得出来；背景故事先在 `LORE` 表占位，正式文案等用户给。

**第 5 步 · 回归 + 落档**：
- 能自己跑完的日志类回归一次跑完：`player_test` / `room_test` / `boss_test`（新 Boss 用 `BOSS_ID` 或临时硬编码 `_debug`，跑完还原）、`ui_test`；**肉眼类效果（手感、演出、光效）交给用户看**，按「效果验收走用户肉眼」那条来。
- 最后同步本文档（形态表 / 素材库地图 / 测试表 / 交接笔记），commit 后 `git push`。


## 最重要
**任何不确定的地方，先向用户确认、问清楚了再动手**（用户原文强调：有疑问一定要找我确认完再行动）。包括但不限于：用哪条动画、数值给多少、机制怎么设计、文案怎么删改、要不要动其他角色的手感。宁可多问一句，也不许猜着做。
用户有无限的素材资源，想要查看或者使用啥的直接跟用户说想要看看新素材，我把整个文件给你你自己决断，当然，里面的spine版本可能比较低，你选好你想要的然后告诉我，我帮你转换成spine4.2版本

---

## 七、交接笔记

### 2026-10-29 · 力僧（c013）全动画重置 + 金钟罩 / 晕眩 / 倒地链

#### 需求
第一段普攻与动画完全不符，整套动画重排：普攻只留两段（第 16、18 号），数值提高一档；K 动画不变、两段攻击，第一段横扫范围内击退 + 击退落点定身，第二段不造成伤害、改为给自己上金钟罩（免一次攻击或 8 秒后消失）；L 动画不变、数值加强、命中晕眩（与定身的区别是：既不能移动也不能出手）；U 不变；奔跑换第 19 号、闪避换第 15 号（完美闪避基础时长由闪避动画时长决定）；受击按伤害分档 1→第 1 号、2→第 6 号、>2→第 6 号→第 3 号→第 5 号→第 9 号（起身）；武僧没有残血待机。

#### 已确认数值（用户拍板）
普攻 2 / 3；K 第一段 3；L 3；K 击退 620 + 撞人 1 伤 + 定身 2s；L 晕眩 2s 且立即打断敌人正在起的招；金钟罩反馈 = 金字「金钟罩」+ 顿帧 + 音效。

#### 做法
- **`skulls.gd` c013 整块重写**：`anim.run "speed_run"`（19 号）、`anim.dash "skill04"`（15 号，0.583s）；`dash_time 0.583` / `dash_speed 300`（位移约 175px，整段 0.583s 都是完美闪避窗口）；`hurt_tiers {heavy 2, knockdown 3}`；`knock_chain ["atked_heavy","atked_air_heavy","atked_fall_end","getup"]`；普攻 = `skill02_01`（lock 0.44 / hit 0.13 / range 156 / 2 伤）+ `skill02_03`（lock 0.47 / hit 0.26 / range 185 / 3 伤），两段 `both` + lunge 120/130；K `skill01` 两段 hits——0.60s 横扫 range 198 / 3 伤 / `knockback {force 620, impact 1}` / `root 2.0`，1.66s `self_shield {hits 1, time 8}`；L `skill03`（`skill_sweep`）0.87s range 191 / 3 伤 / `stun 2.0`；U `skill02` 原样（reflect + heal 2，3.12s 砸地）。
- **`player.gd` 通用化**：形态表 `knock_chain` → `_start_hurt_chain/_start_chain_seg/_end_hurt_chain`，段间按 `_anim_durations` 真实时长无缝接续，最后一段与 `anim_map.getup` 同名时整段无敌；技能 hit 字典新增 `self_shield` → `_apply_self_shield()`（`_shield_hits/_shield_time`，`_physics_process` 倒计时；`hurt()` 在 `_hurt_invincible` 检查**之后**优先挡刀：不掉血、不进硬直、金字 + 顿帧 + `gold` 音效）；新增 `_apply_hit_control()` 统一派发 `stun` / `root`，普通命中与投射物命中都调用。
- **`c016.gd`**：新增 `_stun_timer` + `stun(dur)`（`_root_timer` 归零、交还出手令牌、清 `_attack_hits_left`、ATTACK 立刻回 IDLE）+ `_stun_tick()`（锁移动锁出手；FLY/HURT 照常推进）；`_physics_process` 里晕眩分支放在定身分支之前。**`boss.gd`** 覆盖 `stun()` 为时长减半（与 root 同规则）。
- ⚠️ **新坑**：`knock_chain` 最后一段必须与 `anim_map.getup` **同名**才挂起身无敌（按名字比对）；链里的动画名必须真实存在，`_setup_spine` 会 `push_error("Player: 倒地链动画不存在 …")` 报出来。

#### 回归
- `player_test`：c013 换头 / 普攻 / K / L / U（反伤 + 回血 5→7）全绿，无 SCRIPT ERROR。
- 临时探针（跑完已删）：`hurt(1)`→`atked`；`hurt(2)`→`atked_heavy`；`hurt(3)`→ `atked_heavy`(0.467s) → `atked_air_heavy`(0.5) → `atked_fall_end`(0.6) → `getup`(0.95，无敌) → 2.75s 回 IDLE；金钟罩挡 3 伤 hp 不掉、不进硬直、超时自动散；`c016.stun(2)` 立即打断 ATTACK，2s 内零位移，到点恢复。
- 沙盒启动无脚本报错。

#### 待用户肉眼验收
普攻两段手感与范围；K 横扫击退 + 落点定身的节奏；K 第二段金钟罩反馈；L 晕眩 2s 与被晕目标的手感；闪避 0.583s（完美闪避窗口变大）是否过飘；倒地链 6→3→5→9 是否顺畅无跳帧。

#### 已确认 / 待验收
- Boss 晕眩策略（用户已拍板）：与定身同规则——时长减半；变身/冲锋/僵直等自定义状态期间不生效。
- 改动暂未提交，等用户肉眼验收后再 commit + push。

### 2026-10-29 · 双刺（c021）技能重做 + 通用动作接口（受击分档 / 倒地 / 残血待机 / 闪避）

#### 需求
逐角色细调动画与技能，双刺先做：K 要像银夜位移技一样整段无敌、提速去掉顿感、伤害时刻对齐动画；L 太鸡肋（起手长、没霸体、挨打就断）→ 换第 28 号动画、原地无敌高伤、时长按动画；U → 改成远程投掷手中双刺（第 25 号），不要闪现残影，命中定身；受击按伤害分档（轻/重/倒地+起身）；残血（<20%）换待机；图鉴「冲刺」全改「闪避」，闪避时长 = 闪避动画长度、整段算完美闪避；开始模式页删掉多余文案。**通用接口要给所有角色留好并写进细则**。

#### 做法（双刺）
- **K `skill01`**：`speed 1.4` + `invincible: true`；`blink_speed 520→730`（提速后真实位移时间变短，同步提速保持原位移距离）；命中仍 `at 1.30`（动画秒，`_skill_tick` 用 `(_skill_dur-_skill_timer)*_skill_speed` 对齐）；实际时长 1.567/1.4 ≈ 1.12s。
- **L 换键 `skill03` → `skill5-`（第 28 号，2.583s）**：`invincible` 整段、四段命中 0.79/1.33/1.80/2.25（range_probe 峰值，双向旋斩 `both`），每段 2 伤 + `bleed: 1` 叠流血（裂帛）。
- **U 换键 `skill04` → `skill02-cankao`（第 25 号，2.05s）**：1.43s 出手 `projectile {speed 900, range 460, root 3.0, split 1, style "dagger"}`——一把短匕飞出，命中定身 3 秒并分裂第二把继续飞；无 blink/teleport，只有起手小前冲，不出现闪现/残影。
- `hud_skills` 同步为 `["skill01", "skill5-", "skill02-cankao"]`（技能键名 = 动画名，换动画必须换键）。

#### 做法（通用接口，`player.gd` 已通用）
- **受击分档**：`hurt_tiers {"heavy": 2, "knockdown": 3}`——1 伤播 `atked`（6 号）、≥2 播 `atked_heavy`（11 号）、≥3 直接倒地播 `atked_fall_end`（10 号）→ 自动接 `getup`（17 号）；`_hurt_phase`（fall/getup）+ `_anim_durations` 真实时长驱动，起身段整段无敌。状态时长一律按动画真实长度，不手填。
- **残血待机**：`low_hp_ratio 0.2` + `anim.low_idle "weak"`（32 号）；IDLE 每帧比对 `_idle_anim()`，技能/受击/倒地结束后自动接管。
- **闪避**：`anim.dash "dash_front"`（14 号）、`dash_time 0.5`（= 动画长度，整段是完美闪避窗口）、`dash_speed 340`。其他形态暂用默认（0.16s），要给它们改就按同一组字段填。
- **敌人侧**：`c016.gd` 新增 `root(dur)`（只锁移动、可出手，ATTACK/FLY/HURT 照常推进）、`apply_bleed(layers)` / `_bleed_tick`（每秒按层数直扣，最多 5 层 5 秒）、`_direct_damage`（不进硬直）；`_enter_fly` 时解除定身（物理级控制优先）。`boss.gd` 定身时长减半、流血直扣要同步阶段判定与大血条（变身无敌期不吃跳血）。
- **投射物**：`projectile.gd` 新增 `root / split / style` 参数与 `_draw_dagger()` 短匕视觉；分裂第二把继承 `_hit_list`，不重复结算首目标。

#### 文案
- 图鉴 `ACT_LABEL` 「冲刺」→「闪避」；`_skill_num` 自动标「远程」，`_skill_desc` 标「命中叠流血 / 命中定身」。
- `run_state.gd` 疾影 / 双刺疾刃卡描述「冲刺」→「闪避」。
- `start_panel.gd`：`MODES` 只留 label，删除选模式页副标题「冒险通关可攒解锁，无尽比谁走得深」与模式卡描述行。

#### 回归
- `player_test`：5 形态换头、普攻、技能、时停、强化卡、开始面板全过，无 SCRIPT ERROR。
- 临时脚本回归（跑完已删）：K 中段 `invincible=true`、命中后敌 58→正确；L 首段 -2 且流血 1 层，2.5s 后 4 层持续掉血；U 命中后 `root=2.75` 且分裂第二把补伤害（敌 44→38）；完美闪避不掉血 + buff 4s + 冷却清零；3 伤倒地 `phase=fall` → 1.1s 后 `getup` 且无敌 → 结束回 IDLE；残血待机切 `weak`。
- `tests/player_test.log`、`tests/range_probe.log` 已同步。

#### 待用户肉眼验收
K 提速手感、L 流血强度、U 投掷定身/分裂视觉、倒地起身节奏、残血待机切换、闪避 0.5s 是否过飘。

### 2026-10-29 · 图鉴（敌人收录 + 化身档案 + 悬停演示动画）

#### 需求
主菜单加「图鉴」：能查**自己击败过的敌人**和**已解锁的主角化身**——背景故事、技能机制介绍、数值；招式 / 任何动作都要有演示动画，**鼠标悬停即播**。背景故事先占位，之后用户逐条给正式文案再替换。

#### 做法
- **收录数据**：`meta.gd` 新增 `seen` 表（id → 击败次数）+ `add_enemy_kill()` / `enemy_kills()`，写进 `user://meta.json`；`c016.gd` 的 `die()` 在 `Meta.add_kill(...)` 之后记账，Boss 靠 `super()` 自动继承，不用逐个改。
- **`codex_panel.gd`（新建）**：1200×640 窗口，Tab 两页（敌人 / 化身）。左栏 2 列 × 6 行收录卡（`TextureButton` + 选中朱砂细条，未收录整卡压暗显示 ？？？）；右栏预览台（390×268 半透明墨底）+ 标题/分类/生命/击败次数 + 背景故事 + 动作条 4 列网格。
- **演示动画**：`ClassDB.instantiate("SpineSprite")` + `skeleton_data_res` + `get_animation_state().set_animation(anim, true, 0)` 循环；每个条目 `mouse_entered` → `_play(anim)`、`mouse_exited` → 回待机，说明行同步写成「名字 ｜ 数值 ｜ 机制标签」。数值全部从形态表 / 敌人表读，不手写。
- **条目来源**：化身页读 `Skulls.ids()`（未解锁显示解锁条件）；敌人页 = `ENEMY_ORDER` 7 个杂兵/精英 + `BossTypes.ROSTER` 追加在末尾；Boss 招式取三阶段并集 + 变身条目。
- **两处坑**：① Label 装中文长句会被最小宽度顶开、不换行 → 背景故事改 `RichTextLabel` + `AUTOWRAP_ARBITRARY` + `StyleBoxEmpty` 去默认内边距；② 招式刀光会甩出预览台盖住文字 → `_build()` 先搭详情（先画 SpineSprite）再铺条目卡，卡片后画自然遮住溢出部分。
- **主菜单**：按钮 4 → 5（加「图  鉴」），高度 64→56、步距 72 排开；原化身谱入口改名 `_open_forms()`，新增 `_open_codex()`。

#### 回归
- `ui_test`：设置 → 化身谱（重建 + 真鼠标返回）→ `Meta.persist = false` 后造 3 条击杀 → 开图鉴；日志 `图鉴打开=true`、`悬停招式 -> 预览动画 skill01（悬停前 stand）`、`切到化身页 -> 选中=c021`、`化身页悬停 -> 预览动画=atk01`、`图鉴点返回 -> 面板=false`，无 SCRIPT ERROR。
- 截图：`tests/out/ui_05_codex_enemy.png`（刀客详情）、`ui_06_codex_hover.png`（悬停高亮）、`ui_07_codex_boss.png`（鸣钟三阶段）、`ui_08_codex_form.png`（双刺 3 普攻 + K/L/U + 6 动作）。

#### 待办（用户后续给文案）
`codex_panel.gd` 顶部 `LORE` 表是**占位文案**（键 = 形态 / 敌人 id），用户给正式背景故事后逐条替换即可；机制标签在 `_skill_desc()`，动作排序在 `ACT_ORDER` / `ENEMY_ACT_ORDER`。

### 2026-10-29 · 「再来一局」沿用角色 / 化身谱商栈重排 / 回血飘字去「定山」

#### 三个用户报的问题
1. **阵亡后来一局变回双刺**：`settlement_panel._restart()` 只 `reload_current_scene()`，房间 `_ready` 见 `Run.active == false` 就走无参 `Run.start()` = 冒险 + c021。
2. **墨锭商栈排版挤**：商栈 6 个条目原来和 5 张形态卡同一套单行布局（210 宽、步距 228），第 6 个 x=1210 直接溢出窗口右沿，且和底部「返回」按钮纵向打架。
3. **回血飘字写死「定山」**：`player._apply_skill_heal()` 里 `dn.setup("定山 +%d")`——凡带 `heal` 字段的技能（银夜 I 觉醒等）都会飘出定山的名字。

#### 修法
- **`settlement_panel.gd`**：`_restart()` 改成 `Run.start(Run.mode, Run.skull_id)` 后再 `reload_current_scene()`；`room_01._on_player_died()` 先 `Run.snapshot(_player)` 把当前形态写进 Run（原来只有清完房间/Boss 才 snapshot，阵亡时会话里换过的头就丢了）。
- **`forms_panel.gd`**：形态卡整行改常量（`CARD_Y/CARD_W/CARD_STEP`）；商栈改 **3 列 × 2 行**网格（条目 330×88、列距 355、行距 96、整块水平居中，6 个条目全在 x 120..1160 内）；「返 回」缩成 130×44 挪到窗口左上角（右上角有墨点装饰会压花纹）；两行条目把说明句下移居中。顺手把点击音改成常驻 `_sfx`（`_ready` 建一次、`_click_sfx()` 播）、`_refresh()` 改 `remove_child + queue_free` 并跳过 `_sfx`——和 start_panel 那两处崩溃同源，提前堵住。
- **`player.gd`**：回血飘字改通用文案「回血 +N」，和具体形态/招式解耦。

#### 回归
- `ui_test`：新增化身谱段落——打开截图 → 调一次 `_refresh()` 模拟购买重建 → 真鼠标点「返回」，日志 `重建后点返回 -> 面板=false`，无 SCRIPT ERROR；截图 `tests/out/ui_03_codex.png`（排版）、`ui_04_codex_refresh.png`
- `settlement_dead_test`：阵亡前换成银夜，日志 `阵亡后 Run.skull_id=z003`、`再来一局 -> skull=z003 mode=adventure depth=1 active=true`
- `player_test`：力僧 U 回血断言（5 → 7）照旧全绿


### 2026-10-29 · 修开始面板两处「访问已释放对象」崩溃

#### 症状
① 点「开始游戏」选模式后卡死报错；② 修完 ① 后点「上一步」又卡死报错。两条都是编辑器调试器 `Debugger Break`，游戏当场停在 `debug> `，看起来像闪退。

#### 根因（都已复现 + 修好）
1. **`free()` 销毁正在发信号的按钮**：`_refresh()` 在 `pressed` 回调里对全部子节点 `c.free()`，把刚发出 `pressed` 的卡片当场销毁 → 引擎直接报错。
2. **`_sfx` 被一起清掉**：点击音播放器是面板子节点，`_refresh()` 重建时把它也 `queue_free` 了；下一次点按钮 `_click_sfx()` 调 `play()` 命中 `Cannot call method 'play' on a previously freed instance.` → 调试器中断。
   - 复现记录：去掉两处保护后跑 `start_flow_test`，日志停在点「上一步」后第一次点击，控制台出现该 SCRIPT ERROR + `debug> `。

#### 修法
- `_refresh()`：`remove_child` + `queue_free`（延后销毁），并**跳过 `_sfx`**；`_click_sfx()` 加 `is_instance_valid(_sfx)` 兜底。点击音改成 `_ready` 建一次、之后只 `play()`，不再每次点都新建节点。
- 主菜单加 `_start_panel` 单例引用，连点「开始游戏」不会叠出两块面板。

#### 教训（写测试时注意）
- **`pressed.emit()` 不等于真点击**：它绕过 BaseButton 的输入/状态机，真实鼠标路径才暴露了上面第 1 类崩溃。以后新 UI 按钮先用 `start_flow_test` 的手法（`get_viewport().push_input(ev, true)`，坐标用 1280x720 设计坐标）真点一遍。
- 编辑器里跑会停在 `Debugger Break`（不是进程退出），别当成闪退去猜；直接看 `%APPDATA%\Godot\app_userdata\InkConstruct\logs\godot.log` 末尾的 SCRIPT ERROR 和 backtrace。

#### 回归
- `start_flow_test`：开始→无尽→上一步→冒险→上一步→返回→再开始→无尽→Esc(两次)→连点，全绿无 SCRIPT ERROR
- `player_test` / `room_test` 全绿；`start_flow_test` 已入库，作为真鼠标回归


### 2026-10-29 · 开局流程（模式 → 选角）+ 无尽模式

#### 为什么
用户要求：① 进游戏先选角色（只列已解锁），解锁条件按强度顺序 双刺 < 力僧 < 梅剑 < 剑仙 < 银夜 重排，银夜压轴最难；② 新增无尽模式，怪物随层数在数值/机制上变强，结构仍是「三小关 + 一关 Boss」。流程改成：开始游戏 → 选模式 → 选角色 → 进房间。

#### 数据层
- **`skulls.gd`**：新增 `ORDER = ["c021","c013","c023","z000","z003"]`（强度由弱到强）+ `ids()` 按 ORDER 输出（漏写的新形态自动补末尾），选角面板与化身谱共用同一顺序
- **`meta.gd` 解锁梯度**：c013 击杀 20 / c023 击杀 60 / z000 通关冒险 1 / **z003 通关冒险 3 + 击杀 150**；`unlock_progress()` 支持双条件拼成「击杀 20/150 · 通关 1/3」；`INK_SHOP` 补 `buyout_c023`（80 墨锭）。**通关计数只记冒险**（无尽不计通关，击杀照常累计，解锁进度靠多打）
- **`run_state.gd`**：`MODE_ADVENTURE/MODE_ENDLESS`、`mode`、`depth`；`start(mode, skull)`；`room_config()` 无尽分支走 `endless_waves(i)`；`boss_hp_scale()` = 1+0.4×(depth-1)，`boss_cd_scale()` = max(0.6, 1-0.06×(depth-1))；`room_label()/mode_label()`；`advance()` 在无尽下 `room_index > 3` 时 `depth+1`、`room_index=0`、换一只 Boss
- **`boss.gd`**：新增外部缩放字段 `hp_scale` / `cd_scale`（默认 1 = 冒险原数值），`_apply_type` 里乘进 `max_hp` / `attack_cooldown`
- **`c016.gd`**：`configure()` 支持 `hp_mul`（按形态表基础血量乘倍率）；`wave_spawner` 给精英传 `hp_mul`，普通怪仍用绝对 `hp`

#### 无尽数值（`endless_waves`，第 d 层第 i 间）
- 普通怪血 `2+(d-1)+i`；速度 `min(1.55, 1+0.05(d-1))`；总数量 `min(12, 5+i+min(d-1,5))`；精英数 `floor((d-1)/2) + (i>=2 ? 1 : 0)`；精英血量倍率 `1+0.3(d-1)`（数量与血厚双管，速度有上限避免手感崩）
- Boss 血 ×(1+0.4(d-1))、出手冷却 ×max(0.6, 1-0.06(d-1))；层间补给 `8+4d` 墨骨 + 一次强化
- 赐福一局只发一次（`Run.blessing` 已存则不再弹），无尽跨层不重复

#### UI
- **`start_panel.gd/.tscn`（新）**：两步面板。① 冒险/无尽两张卡（写法差异，不写数值）② 5 张角色卡（`Skulls.ids()` 顺序，未解锁压暗 + 解锁条件 + 实时进度，已解锁显示契合）；Esc/上一步回退；选中即 `Run.start(mode, id)` → 切房间
- **`main_menu.gd`**：开始键改为 `_open_start()` 弹面板（不再自己 `Run.start` + 切场景）
- **`hud.gd`**：顶部中央模式标签 `冒险 · 1/3` / `无尽 · 第 2 层 · 2/3` / Boss 房 `Boss`（y=46，避开大血条与墨骨）
- **`room_01.gd`**：`_spawn_boss()` 在 add_child 前写 `hp_scale/cd_scale`；`_on_boss_died()` 无尽分支 = 补墨骨 + 弹强化（前进即下一层）；`_on_player_died()` 无尽结算标题写「无尽 · 第 N 层」

#### 回归结果（`player_test` 新增开局段）
- 新档解锁顺序 `[c021开, 其余锁]`；击杀 20/通关 1 → 力僧开、梅剑锁、剑仙开、银夜锁；击杀 150/通关 3 → 银夜开
- 开始面板两步截图 `17_start_mode` / `18_start_char_locked` / `19_start_char_all`
- 无尽第 1 层 vs 第 6 层：怪血、精英倍率、Boss 血倍率、冷却倍率全部单调变狠
- **肉眼验收点（交用户）**：主菜单开始游戏 → 选模式 → 选角色（新档只有双刺亮）→ 进房间看顶部模式标签；打通一层无尽确认自动进下一层、数值更硬


### 2026-10-29 · 升级系统 Build 化：通用卡机制化 + 每形态 3 流派 × 3 级

#### 为什么
用户验收后指出两处硬伤：① 通用池里「加移速」这类纯数值没搭配、没手感，应该换成「冲刺更远 / 完美闪避窗口更长」这种能改变玩法的词条；② 每形态专属强化只有 1-2 张，玩起来可玩性提升不大——要求**每个形态分化几条流派**。

#### 设计定版（`run_state.gd`）
- **通用池 6 张**（删掉 `speed` 疾行）：锋锐（全伤 +1，5 级）/ 静心（技能冷却 -15%，3 级）/ 铁骨（生命上限 +1 并回满，3 级）/ 轻骨（换头 -3 墨骨，2 级）/ **疾影**（冲刺时长 +20% ⇒ 冲得更远、完美闪避窗口同步变长；冷却 -10%，3 级）/ **掠影**（完美闪避赏伤 +1、无敌 +0.2s，2 级）
- **形态流派 45 张 = 5 形态 × 3 流派 × 3 级**，字段 `path`（流派名）/ `tier`（1 初 / 2 续 / 3 极）/ `theme`（配色）/ `req`（前置卡）。一局 3 次强化正好把一条流派从初推到极：
  - 双刺 c021：血饮（技能命中回血 → 回 2/4s → 回血时挂 4s 加伤）/ 锋扫（范围 +30/25/20% + 普攻加伤）/ 疾刃（冲刺终点斩 1→3 伤，命中回满冲刺 + 回墨骨）
  - 梅剑 c023：鞭术（范围+普攻增伤）/ 内劲（转鞭每跳 +1 → 出鞭 0.5→0.35s → 范围 +40% 且冷却 -25%）/ 铁骨（减伤，续段 -20% 冷却）
  - 力僧 c013：金刚（定山反伤 +2/+2、砸地回血 +2、冷却 -30%）/ 震地（范围 +35/25/25% + 普攻增伤）/ 禅定（减伤，挨打回 1 墨骨）
  - 剑仙 z000：剑气（伤害 +1/+2、飞行 +30%、穿透）/ 双发（齐发 +1/+2/+3 道）/ 御剑（冷却 -25%、射程 +30%、再 -15% 且 +1 伤）
  - 银夜 z003：轻功（跳更高悬停更久 + 完美闪避减全技能 CD 2s/4s）/ 时停（时长 +1s、时停期全伤 +2、冷却 -30%）/ 杀阵（O 位移距离 +1/3、伤害 +2、命中返还 3s 冷却）
- **价格改层级价**：流派卡 8 / 14 / 20（初/续/极），通用卡仍 8 + 4×等级
- **卡池轮转**：`roll_cards` 分 `cont`（已开张流派的下一层）/ `fresh`（新流派 T1）/ `gen`（通用）三池各取一张，再补足随机——保证「有延续、有新品、有通用」
- **卡面**：流派卡标题只写流派名并按主题配色（0 朱砂 / 1 墨青 / 2 赭金），右上角层级 `1/3`；通用卡标题带本次购买后的 `LvN`、右上角 `已拥有/上限`

#### 引擎侧（`player.gd`）
- 新增派生字段层：`_attack_damage_bonus` / `_proj_damage_bonus` / `_proj_speed_scale` / `_proj_range_scale` / `_damage_reduce` / `_hurt_bones` / `_reflect_bonus` / `_heal_bonus` / `_form_cd_scale` / `_skill_cd_mod` / `_skill_damage_mod` / `_skill_hit_refund` / `_tick_damage_bonus` / `_tick_interval_scale` / `_tick_range_scale` / `_stop_bonus` / `_stop_buff_damage` / `_blink_dist_scale` / `_qg_jump_bonus` / `_qg_hover_bonus` / `_dash_attack_*` / `_dodge_*` / `_dash_time_scale` / `_dash_cd_scale`
- **`_apply_form_mods()`**：整组归零后遍历 `_upgrades`，用 `Run.card_info(k)["forms"]` 过滤当前形态（**换头后旧形态卡休眠、换回来再生效**——旧实现无条件应用 `form_*` 是缺陷）；轻功在原形态表倍率上叠加
- 新机制：`_dash_attack()` 冲刺终点斩（身前 130 + 半径、dy≤80，命中回满冲刺/回墨骨）；时停加伤独立槽 `_stop_buff_timer`（与觉醒/血饮共用 `_buff_now()` 取最高）；`_skill_hit_refund` 命中返还冷却；`hurt()` 减伤下限 1、挨打回墨骨；`_perfect_dodge()` 收益加档 + 减全部技能 CD

#### 回归结果（`player_test` 新增 Build 段）
- 三选一含流派卡；`z003_stop_1/2/3` 连买价格 8/14/20，买完初后下一轮必出「时停·续」
- 生效值：`_stop_bonus=1.0 / _stop_buff_damage=2 / skill06_cd=0.70 / dash_time=1.20 / dash_cd=0.90`
- 跨形态泄漏 `[]`；切到 c021 时 `_stop_bonus=0.0`（休眠），切回 z003 恢复 1.0
- `upgrade_panel` 冒烟 `cards=3`，截图 `16_upgrade_panel.png` 排版正常（描述不再压价格）
- **肉眼验收点（交用户）**：清一房看三选一卡面（流派配色/层级/价格）；各形态连走一条流派体验手感；换头确认旧流派卡失效

### 2026-10-29 · 完美闪避 + O 的 #87 回退瞬移版

- **完美闪避**：冲刺（Shift）途中碰到任何"本应命中"的伤害 → 全免并给收益：冲刺冷却清零、4s 全伤害 +2（`_buff_damage`/`_buff_timer`，与觉醒共用槽、取高者）、0.5s 垫底无敌（防同轮攻击后段在冲刺结束后命中）。金色"完美闪避"飘字 + weapon_sword 嗖声 + 微顿帧微震屏。实现：player.gd `hurt()` 的 DASH 分支调 `_perfect_dodge()`——hurt 是玩家唯一受伤入口，一处挂钩全覆盖
- **O 的 #87 回退**：残影方案（196da12，本体不动放残影）用户实测"更难看"，`git checkout 4978714 -- player.gd skulls.gd` 回退到瞬移版（teleport_anims + 尾声零混合收 + 收招帧瞬移补结算）。残影实现留在历史里，别再试

### 2026-10-28 深夜二 · 银夜微调：K 换三随机池 / 技能击退修复 / I 时长对齐 / O 双模式

#### 四点修改（全部用户拍板）
- **K 换池**：原 #89 skill14_02 单动画 → **atk03_03 / atk04_02 / skill01 三随机池**（编号 #15/#17/#70）。speed 0.8 慢放后实长 1.21/1.44/1.98s；霸体、sword_qi 接口保留。配置从 hits 数组改 `hit_at`/`range` 字典（引擎新增支持）。**hit_at 三轮标定**（0.34/0.53/0.25）：首版按满伸展峰值（0.41/0.58/0.85）伤害慢半拍；二版改扫出中段，但 skill01 是**起手早挥**（0.23s 左挥峰值 L320≈138px，之后长收势，0.85 才是终斩）——用户实测"很早就出刀但伤害很迟"，三版把 skill01 标到起手斩出点 0.25s，与短动画手感一致
- **L 击退失效根因**：`_deal_skill_hit` 只结算伤害，launch/knockback 原本只有普攻 `_deal_hit` 处理 → 抽 `_skill_kinetic` 两分支共用，技能 hits 从此支持击退/击飞
- **I 觉醒时长对齐**：`align_max: true`——抽中短动画时 `_skill_speed *= base/max`（池内最长 skill18_02 2.3s，skill10 慢放到 ~0.23 倍），三种动画统一撑满 2.3s
- **O 双模式位移**：blink 闪现（skill11/skill23_03）+ `teleport_anims` 瞬移（#87 skill11-cankao）：原地播放、尾声提前 0.12s 零混合 `clear_track`+瞬时切 stand（`set_default_mix(0)` 手术期 + `_mix_restore` 次帧恢复 0.2，防 clear_track 的旧轨道淡出），收招帧瞬移 600px + hit_at 99 补结算。O 加 `invincible: true` 全程无敌。**残影方案试过已回滚**（196da12）：把 #87 改成"本体不动、释放残影"，用户实测"更难看"，回退到瞬移版（4978714）
- **银夜五技能全霸体**：L/U/I/O 补 `poise: true`（K 原本就有）

#### 随本轮一起提交的上轮微调
- K skill14_02 speed 0.8；银夜 dash 动画 `dash_anim_speed: 0.4`（autorush 0.083s→0.21s）；O blink 改 0.15~0.90s × 800px/s（距离仍 600px）；sandbox 双方无限血 + 技能零 CD（`cooldown_scale=0`、`dash_cooldown=0`）

#### 引擎侧改动（player.gd）
- `_play(anim, loop, spd)`：set_animation 返回本条轨道，time_scale 只作用于它（探针实证 set/get 生效）
- `_start_skill`：`align_max` 算速、`hit_at`/`range` 字典按抽中动画构造单段 hits（旧 hits 数组写法兼容）、`teleport_anims` 初始化 `_skill_teleport`；`_skill_tick` 位移三分支（原地等瞬移/闪现/减速）+ `_invincible = _blink_active or cfg.invincible`；收招帧先瞬移再补结算；`swap_skull` 清 `_skill_teleport`
- 回归：player_test 全绿（spine 加载 ERROR 仍是已知噪音）。**肉眼验收点**：sandbox 连按 K 看三种随机蓄力斩、L 看击退撞人、I 看觉醒时长恒定、O 反复按直到抽中 #87 看原地播放+收尾瞬移

### 2026-10-28 深夜 · 银夜·将去未还（z003）实装，玩家形态回 5 席

#### 编号 → 动画名确认流程（有坑）
用户按 anim_viewer ↑↓ 的 **1 基序号** 给动画编号，先用 anim_list.tscn 跑全表（z003 共 128 个动画）再逐个对号。**坑：编号 = log 中 ANIM 行的 1 基序号，不是文件行号**（第一版按行号误读——把 28 当成 floated、71 当成 skill01，被用户纠正"28 有 0.083 秒"才对上 autorush）。确认结果：22=atked（受伤）、26=atked_fall_end + 53=dead 循环（死亡全过程：先播一次倒地再循环躺尸，anim 表拆 `dead` + `dead_hold` 两键）、28=autorush 0.083s（闪避）、56=jump、68=run、71=skill02、普攻段池 72/78=skill03/skill09 → 73/77/84=skill04/skill08/skill08-cankao → 74/76=skill05/skill07、75=skill06、79/95/101=skill10/skill18_02/skill24_03、80/87/100=skill11/skill11-cankao/skill23_03、89=skill14_02、胜利池 92/93/94=skill17_02 三变体、124=stand。

#### 形态配置（`skulls.gd` z003）
- scale 0.431（range_probe 实测 297.1px@scale1 → 128px 主角标准身高），body_radius 30
- **轻功** `qinggong: {jump_mul: 1.32, hover: 0.32}`：跳高 ×1.32 明显压过其他形态；起跳后 `velocity.y > -60` 的近顶点区间悬停 0.32s（velocity.y 锁 0），落地清零、换头清零
- **普攻三段随机池**：段1 pool=[skill03, skill09] dmg1；段2 pool=[skill04, skill08, skill08-cankao] dmg2 + `launch {vx:150, vy:520}` **击飞**（敌人活着才挑，尸体不挑）；段3 pool=[skill05, skill07] dmg3。hit_at/range 按动画名逐个字典查（探针标定 ×0.431）
- **K `skill14_02`**（cd 8）：蓄力 + `poise` 霸体，hit 0.59s range 130 dmg 3；`"sword_qi": null` **剑气远程接口预留**（只留桩不实装，用户明确）
- **L `skill02`**（cd 3）：快速出拳不动剑，hit 0.71s range 95 dmg 1 + `knockback {force: 620, impact: 1}`——敌人往攻击方向击退，撞到其他敌人（双方各吃 1）或撞墙（自己吃 1）触发组合伤害
- **U `skill06`**（cd 14）：拍击大地 = **时间暂停** `stop {at: 0.5, mob: 3.0, elite: 2.0, boss: 1.0}`，无伤害段不加特效；定住当前场景所有敌人，无视霸体打断一切准备动作（含 Boss 冲锋/技能前摇）
- **I 觉醒爆气**（cd 20）pool=[skill10, skill18_02, skill24_03]：`heal 2` + `buff_damage 2` / `buff_time 8.0s`——回血加伤全都要，`_buff_now()` 挂进全部伤害路径（普攻/投射物/技能 hit/path/tick）
- **O 位移斩杀**（cd 12）pool=[skill11, skill11-cankao, skill23_03]：伤害 6（用户批准超标），`path: true` 打位移区间内所有敌人；**三随机动画位移统一 600px**——以 #87=skill11-cankao 探针位移（R1780@scale1 ≈ 600px 游戏内）为标准，blink 0.15~1.35s × 500px/s，落点 hit at=1.35 range 90
- 胜利池 `victory = [skill17_02, skill17_02-, skill17_02-cankao]`

#### 引擎侧改动
- **player.gd**：KEY_LABELS 加 skill_i→I / skill_o→O；`_setup_spine` 预缓存全部 pool 动画时长（`_attack_durations`）；新增 `_attack_lock`（pool 段锁定 = 抽中动画真实时长，修掉"读不存在的 lock 键会崩"）；`_deal_hit` 支持 launch/knockback 段；`_start_skill` 抽 `_skill_anim`、hits 深拷贝；`_skill_tick` 加 stop 触发块（档位由敌人 `stop_tier()` 提供）；`die()` 播 dead 后 `_queue(dead_hold, true)` 循环躺尸；`_buff_timer` 倒计时，换头清 buff/hover
- **c016.gd**：新增 `State.FLY`（击飞/击退共用：重力抛物线 + 播 hurt 动画；击退带 `_fly_impact`，|vx|>130 时撞同伴**手动距离判定**（`_fly_hit` 去重，双方各吃 impact，自伤后 return）/ 撞墙 is_on_wall 自己吃；落地回 HURT 0.3s）；`time_stop(dur)` = sprite.process_mode=DISABLED + 主循环早退，到点 `_end_stop()`；时停中挨打伤害照算但不进硬直，打死先解冻再 die；`stop_tier()` 由 `elite` 字段分档
- **boss.gd**：同款时停块（变身/冲锋计时一并冻结）；`time_stop` 打断冲锋/转身/出手回 IDLE（冲锋进冷却），变身演出不取消；`launch`/`knock_back` 覆盖为空（Boss 霸体免疫）
- **settlement_panel.gd**：`_make_avatar()` 挂当前形态 SpineSprite（`process_mode=ALWAYS` 对抗 get_tree().paused，scale ×1.6，position (240,590)）；通关 victory 池随机播一遍接 idle，阵亡 dead 接 dead_hold 循环；无 victory 配置的形态 fallback 只待机（其他形态接口就此留好）
- **meta.gd**：UNLOCKS 加 `z003 {clears: 1}` + INK_SHOP `buyout_z003`（200 墨锭）；**project.godot**：新增输入 action `skill_i`(I) / `skill_o`(O)

#### 回归结果
7 项全绿：player_test（含 z003 换头，日志 `swap -> skull=z003 hud=["skill14_02",...] attacks=3 skills=[...]`，SWAP DONE）、enemy_test、room_test、boss_test、enemy_hit_test、settlement_clear_test、settlement_dead_test；range_probe 补 z003 十八个动画标定。**肉眼验收点已交用户**：sandbox.tscn [/] 切银夜——轻功跳跃悬浮、三段普攻随机动画、段2 击飞、L 击退撞人、U 时停、I 觉醒、O 位移斩杀；结算化身通关/阵亡各看一次。

### 2026-10-28 夜 · 青笠下架：玩家形态 5→4，c012 转生精英怪

#### 为什么
用户判定青笠·顾沧洲（c012）是五形态里最弱的（动画撑不起招式，整理质量差），决定**删掉玩家形态**，第 5 席由用户从素材库自选新角色填补；骨架不浪费，**转生为精英怪**——普攻 = 第 13 个动画 `skill01`（1.317s）两连击，技能 = 第 14 个动画 `skill02`（1.617s）跳斩伤害翻倍，并授权自由补强机制。

#### 精英青笠配置（`enemy_types.gd` c012）
- scale 0.563（骨架 262.9px → 约 148px 精英身高），hp 10，掉 3 墨骨，预警泛红 + 出手霸体档 armor=1
- **两连击 skill01**：`hit_at`/`ranges` 数组按段结算（0.80s 172px / 1.21s 138px，探针峰值 ×0.563）；两段间隔 0.41s < 玩家受击无敌 0.8s，站定玩家实际吃 1 段——两连击 = 两次独立命中机会，这是设计预期
- **跳斩 skill02**：伤害 2（翻倍）+ `poise_atk` 出手期间挨打不断招 + `lunge_mul` 2.0 跨步 + `hop` 260 腾空 + 0.89s 劈落 163px
- **半血狂暴 `enrage`**：hp ≤ 50% 触发一次，冷却 ×0.65（1.70→1.11）、追速 ×1.2——越残越凶
- `pick: "random"`：两招范围接近（172 vs 163），nearest 会让跳斩永远压过两连击
- 死亡动画 `dead` 是 0 秒空姿态，倒地用 `atked_fall_end`（z002 同款处理）；受击 = `atked`（0.333s）

#### c016.gd 框架扩展（支撑以上机制，全怪通用）
- `_attack_hits` 单值 → `_attack_hits_left` 命中段队列（{t=倒计时阈值, i=段序号} 降序弹出），`_range_of(anim, seg)` 支持 ranges 数组
- 新形态字段：`damage`（每招伤害）/ `poise_atk` / `lunge_mul` / `hop` / `enrage{below,cd,speed}`
- **坑**：ranges 支持数组后，挑招 pool 里 `float(_ranges.get(...))` 对数组会崩，三处全部改 `_range_of(n, 0)`

#### 玩家侧删除面
skulls.gd 整段移除 c012；meta.gd 删解锁项（通关1）+ INK_SHOP 删 buyout_c012；run_state.gd FORM_UPGRADES 删疾影/连突（10→8）；player.gd 删 blink_scale（form_swift 唯一消费点，死代码）；player_test 换头循环删 c012。面板数据驱动无需改。素材 `git mv` 到 `art/characters/enemies/c012/`，.tres 与三个 .import 的 source_file 路径同步改写 + `--import` 重导。旧 meta 存档里残留的 c012 契合/解锁键无害。

#### 回归结果
- `enemy_test` 新增第 5 段：强制锁招验证两连击 hits_left=2、净掉 1 血（第二段被 0.8s 受击无敌吞）；跳斩 hits_left=1 命中掉 2；半血狂暴 cooldown 1.70→1.11；死亡正常。截图 ai_07_c012_leap.png 渲染正常
- `player_test` / `room_test` 全绿；化身谱截图确认 4 形态排版正常
- **坑：测试期望值受局外存档影响**——`c023 普攻总伤害=7` 一度疑似回归，实为本地 meta.json 里 c023 契合 Lv2（95≥80）普攻 +1/段（7=3+4）。player_test 日志已改为打印加成值（`伤害加成 %+d/段`），别再写死绝对值

#### 环境备注
本轮 IDE 沙箱对 `Start-Process` 持续报 `sandbox backend failed`（无 Godot 进程、--import 却正常），直接 `&` 调 mono Godot 静默不跑场景——**用 `mcp_godot_run_project` MCP 工具跑回归可绕过**

#### 同晚追加 · 试炼场 sandbox.tscn
用户要的调试单挑场：一块空地 + 任选敌人（小怪/精英/Boss 共 12 只，轮换表直读两张形态表，新增怪自动进表）+ 随意换玩家形态 + 双方无限血。键位 [/] 换形态、,/. 换敌人、R 重刷；换怪前若旧怪占着全局出手令牌须先归还，否则新怪永远出不了手。用户强调规则已写入「项目约束」：新模型必须可浏览（anim_viewer 自动扫描 art/characters，实装时同步确认）。

#### 同晚追加 · 受击体积跟体型走（body_radius）
用户实测发现马车（武车 c001）等大体积 Boss 受击判定太小、砍不动。实装 `body_radius` 受击半径：挨打判定 = 攻击方射程 + 目标半径（边缘到边缘），7 处判定全改（玩家普攻/技能/持续段/投射物 + 小怪近战 + Boss 冲锋），数值按体型配（小怪 28~40 / 精英 36~40 / Boss 55~300，武车 711px 宽配 300）。物理碰撞胶囊刻意不动——绕后穿裆机制依赖小胶囊。永久规则已写入「项目约束」，新角色/Boss 实装必配。顺带修了 enemy_test 收尾访问已释放 `_enemy` 的既有 bug（精英段把测试拉长到第一只小怪尸体释放之后，debugger 断在 line 124；加 `is_instance_valid` 守卫）。回归 player/enemy/room/boss 四项全绿。

### 2026-10-28 下午 · 关卡互动装饰 + 形态专属强化

#### 本轮干了什么
1. **关卡互动装饰**（P2 路线图勾掉）：普通房随机 2-3 个可互动物件（卷轴/香炉/石碑），程序化水墨 `_draw` 本体 + 走近 90px 自动触发 + 爆开特效/飘字/音效；触发逻辑参考 bone_pickup 吸附模式
2. **形态专属强化 ×10**：`run_state.gd` 新增 `FORM_UPGRADES`（按当前 skull 过滤），`player.set_upgrades` 统一消费（范围倍率/冷却/穿透/双发/霸体/饮血/突进距离），`projectile.gd` 支持穿透+多发；upgrade_panel 卡牌加图标（Y700 Icons → `art/ui/icons/` 6 枚 64px）
3. **随机树池**：普通房 2-3 棵场景树，新增红枫（素材库场景特效 E100167 整图裁帧）
4. **新工具** `tools/png2strip.py`：PNG 序列拼水平精灵条通用管线
5. 素材选型教训：spine 特效目录多为 additive 叠加层（单独看很淡不可用）、场景特效整图预览多为零件图——选中素材先用 contact_sheet 肉眼确认再拼条

#### ⚠️ 失误记录（用户要求写明，继任者警戒）
- **任务完成后没及时收工**：本轮回归 11:42 已全绿、截图已验收。之后因一张 **10/26 旧时间戳截图**（room_08_upgrade.png 无图标）误判要补验升级面板图标——新一轮 demo 流程根本不含面板环节，旧截图不作数
- **引擎环境问题没止损**：Godot 秒退后连续几十次命令排查（管道崩溃/沙箱/mono/[dotnet] 逐节二分），最终结论"mono 引擎环境问题、与业务代码零关系"——对项目零价值，白白烧掉大量积分
- **教训（务必遵守）**：① 截图验收先看文件时间戳，旧图一律不采信 ② 引擎/环境起不来最多试 2 种方式就停手报告用户，不自己深挖 ③ 一旦确认"与项目代码无关"立即收工汇报 ④ 排障产生的临时探针文件当场清理，别留到提交前

#### 同日返工（用户验收后）
- **化身光柱修复两连**：第一版补偿式下沉 55px 治标；根因是 pillar.png 帧内容没画到画布底（主体期留白 ~73px），根源修 = **裁掉贴条底部 65px**（8192x396→8192x331）+ 撤销代码补偿，bottom 锚点即脚底。**教训：bottom 锚点特效先用 PIL 查帧内容包围盒，留白从素材侧裁掉，别在代码里补偿**
- **随机树池撤销**：红枫/随机位置导致树飘空+画面缺块，用户判定不合格整体撤销，恢复固定 4 棵（松/樱/柳）定死坐标版；红枫素材已删。**教训：素材库 spine 整图裁帧的树不带"画布底=树根"保证，别拿来进随机池**
- **武车转身动画归位**：zhuanshen 双马调头原被当 P2 阶段变身演出播（用户：转向动画不该当技能）——P2 改直切提速；zhuanshen 改为**绕后转身演出**（boss_types `turn` 配置 + boss.gd S_TURN 状态）：玩家穿裆到背后时播调头动画 1.4s，播完才翻转朝向；转身期不还手（穿裆奖励窗口），4s 冷却防反复穿裆锁死。**冷却期内也绝不瞬转**——车身太重原地减速等冷却（父类 `_chase_tick` 会无条件翻朝向，必须在 boss.gd 提前 return 拦住）

### 2026-10-28 傍晚 · 梅剑改「数值怪」

#### 为什么
用户看完梅剑（c023）17 个动画后判定：没有能撑起普攻的好动作，与其硬找不如把她做成**数值怪**——招式少、数值高、节奏笨重但收益明确。

#### 定版方案（`skulls.gd` c023）
- **普攻 = `skill01`（1.883s，第 13 个动画）两段**：0.75s 鞭梢甩到 372px，伤害 **2**，命中后把敌人**拉回到身前 80px**（多目标依次错开 34px）；1.68s 前刺 145px，伤害 **3**。`lock=1.883`、`cancel=0`——普攻间隔锁满整段动画，播完才能接招或移动。
- **唯一技能 = `skill02`（4.167s，第 14 个动画）**，从 U 位（`skill_ult`）改到 **K 位**（`action: "skill"`），`hud_skills` 只剩它 → HUD 自动变 2 槽。
  - `poise: true`：起手即霸体，挨打掉血但不断招。
  - `tick`：0.15~3.0s 每 **0.5s** 对前后方 130px、上下 140px 内所有敌人各打 **1** 点（转鞭阶段）。
  - 末段：3.6s 超远甩鞭 500px，伤害 **2**。
  - `ranged_guard: true`：技能期间免疫敌方投射物并原路弹回"第一个遇到的敌人"。

#### 引擎侧改动（`player.gd`）
- 普攻 `hits` 从"纯秒数数组"扩为**字典段** `{at, damage, range, pull, sfx}`，`_hit_time()` 统一取时刻，旧格式（纯秒数）保持兼容；`_deal_hit(h)` 按段读数值并支持 `pull` 拉回。
- 新增 `_skill_tick_acc` + `_deal_skill_tick()`：技能持续伤害段，不顿帧不震屏，只轻播命中音。
- 新增 `try_reflect_ranged(damage, from_x, attacker) -> bool`：**预埋接口**。工程内目前**没有任何敌方投射物**（敌人全是近战 range 判定），所以本轮只做框架；以后敌方弹幕命中玩家前先调它，返回 true 就表示已免疫并原路弹回。Boss 原地火区走的是直接 `hurt()`，天然不进这个分支——正好符合用户要的"火焰不能免疫也不能反弹"。

#### 回归结果
- `player_test`：`c023 靶子起点距玩家 300px` → `鞭击后 80px` → `普攻总伤害=5（2+3）`；`12_skill_c023 state=6`；`技能中转鞭 ranged_guard=true`。`reflect_test c013` 与 `ult_after` 仍绿。
- `room_test`：`[R] ALL DONE`。

#### 教训
- **测试时序会吞键**：`_try_skill()` 只在 IDLE/RUN 调用，硬编码等待落在上一招锁定里时按键被静默吞掉（第一轮梅剑技能压根没测到，且同时把 c013 反伤测试带红）。已加 `_wait_free()` 兜底，见遗留坑「技能只能在 IDLE/RUN 起手」。
- spine 每次初始化打 3 条 `Resource file not found: 目录` ERROR 是既有噪音，别当资源损坏处理（见遗留坑）。

### 2026-10-28 文档同步

本文档曾与代码严重脱节（写于 10-27，但 5 形态、敌人池、波次刷怪、墨骨/墨锭经济、主菜单/设置/暂停、BGM/音效均已在库）。本轮按代码实况全面重写「已实现」区，路线图剔除已完成项（正式启动场景、音效全覆盖大头、存档持久化）。剩余真需求见 P1：焚鼎火区灼烧视觉、投射物精灵条弹道（用户点名）、音效补缺三条。

### 2026-10-27 收官（历史记录）

#### 本轮干了什么
1. **Boss 池 3 → 5**：碎岳 C008 / 鸣钟 C032 入池（探针实测 → 配表 → 硬编码回归法跑 boss_test → 截图验收）
2. **登场演出**：`Feel.intro_zoom` 镜头拉远缓推回 + 书法落款中央定格 + 大血条延迟淡入
3. **字体落地**：全局庞门正道粗书体 + Boss 名演示佛系体；踩了 project.godot 注释坑（见遗留坑）
4. **代码审查修了 5 个真 bug**：闪现受击残留穿怪、清场回调缺 `_ended` 守卫叠面板、买血上限公式漏算、cd 查询死代码、普攻缺 `_idle_queued`
5. **Boss 特效落点审计**：爪痕来袭侧（方向曾写反）、冲锋拖尾躯干高度（`off_y` 按体型）、撞墙 crack 贴墙根
6. **五张 Boss 房主题背景**：整图铺底，**用户明确否决了剪影拼接方案**；tint 调色后来也被否决（见第 7 条定版）
7. **Boss 房背景彻底单层 + 地面线对齐**：石板带仅普通房铺，Boss 房 = 一张整图 + 角色踩画中地面。最终定版：**1.25 原比例铺满**（1536x768→1920x960，整图完整不裁；1.875 放大裁掉右 1/3、比例失衡被判返工）、**不加 tint 滤镜**（染黄被判"太丑"）。`ground` 按 768 像素系离线 PIL 合成预览调准（曾误按 1024x512 缩略图量，全线飘空）；地面条实验弃用——ground_ink 深色石板纹与亮雾/灰石板场景都违和
8. **预警特效换墨环**：Boss 脚下棕绿脏块的真凶是 c016 `_telegraph` 的 gather 贴图脏底（不是背景也不是登场特效）；换程序化生成的 telegraph 墨环（`tools/gen_telegraph.py`），c016 出手预警 + boss.gd 火区预警两处都换，c032 enter/transform 顺带 gather→pillar
9. **小怪房"偏黄"真相 + 素材纸白回正**：用户反馈"看着还是有一点黄色"。逐点比对证明**引擎侧零滤镜**——相机锁 zoom=1 时屏幕坐标=世界坐标，可直接拿渲染像素减磁盘 PNG：天空区、石板带渲染值与源图**逐像素一致**，纸白 R−B=0.0。偏黄来自素材自身纸白偏暖（bg_main 纸白 (248,242,228) R−B+20、ground_ink +31、fg_tree_l/r +30/+21）。按"纸白回正"（最亮 1% 均值作纸白、保持 luma 算通道增益）修正 4 张 PNG：bg_main R×0.9784/G×0.9995/B×1.0642、ground_ink R×0.9512/G×1.0078/B×1.1043、fg_tree_l R×0.9486/G×1.0085/B×1.1095、fg_tree_r R×0.9643/G×1.0041/B×1.0825。小怪房天空均值 R−B 由 **+13.8 → −3.0**。改完**必须删 `.godot/imported` 对应 ctex 再开编辑器重导**，否则 `run_project` 仍读旧贴图

#### 经验心得（继任者必读）
- **探针先行**：新 Boss 永远是 range_probe 量骨架 → boss_types 配表 → boss_test 回归看截图，别拍脑袋填数
- **截图验收不可替代**：游戏视觉问题（特效位置/字体/背景）只有截图能查，日志全绿不代表画面正常
- **特效锚点两派**（fx.gd pivot bottom vs center）是落点错乱的重灾区，配新特效先想 pos 是脚底还是中心
- **脏块排查三步**：先 fx_test 隔离渲染确认贴图本身干净 → 再按时间线对撞（巡游 1.8s 截图正撞 c016 出手预警，起手慢的 c015a1"干净"是假象）→ 最后才怀疑贴图重抠（rekey_fx.py 对脏色块无效，别浪费功夫）
- **横版场景图当背景**：别按底边对齐视口，找画中地面线对齐 GROUND_Y；**缩放用"恰好铺满"的整数比**（1536x768→1.25 铺满 1920），为拓宽视野强行放大会比例失衡+裁掉画面；**先确认源图真实尺寸再量坐标**（Read 显示的图是缩略图，像素系以 `Image.open().size` 为准）；别给素材乱加 modulate 滤镜，原图画质就是最好画质；登场运镜时长 = chuchang 时长+0.5、每个 Boss 不同，巡游截图前必须 `Feel._zoom_tween.kill()` + `zoom=1` 收稳，否则拍到运镜中途画面，量地面线全白搭
- **"画面偏黄"先分清是滤镜还是素材**：把相机锁 `zoom=1`（屏幕坐标=世界坐标），拿 `get_viewport().get_texture().get_image()` 的像素直接减磁盘 PNG 同坐标像素——差值 ≤1 就说明引擎没染色，偏色在素材纸白里；改完 PNG 必须删 `.godot/imported` 对应 ctex 并重启编辑器重导，`run_project` 不会自动重导，否则改一通截图一模一样
- **PIL 画精灵条**：单帧画布用局部坐标（SIZE/2），拿条带坐标画会落到画布外丢帧
- **测试挂死先想"结算暂停"**：玩家死亡/通关都会 `paused=true`，测试流程里 `create_timer` 全部冻结；挂死先查玩家是不是死了
- **回归环境**：用户编辑器开着玩会污染导入缓存（骨架加载失败），重跑一次即可，别慌着改代码

#### Git 提交流程（本项目惯例）
1. **提交前核对**：`git status --short` + `git diff` 过一遍；实验性/已否决的改动先 `git restore` 还原（本轮还原过 4 张 rekey 无效的贴图），别把噪声带进仓库
2. **逐个暂存**：按文件名 `git add <文件...>`，不用 `git add -A`（防误带杂项）；`tests/*.log` 是验收产物要带上；美术资源必须连同 `.import` 一起提交，否则别人拉下来导入配置丢失
3. **提交信息中文**：首行一句话讲"为什么"，正文列点讲"改了什么"；PowerShell 没有 bash heredoc，多行信息用 here-string：`$msg = @'...'@; git commit -m $msg`
4. **推送**：`git push` 到 `main`（GitHub 远端 jiangqvweihuan/ink-construct），推完 `git status --short` 确认工作区干净；不 force push、不 amend、不动 git config
5. **提交时机**：回归全绿 + 截图验收通过才提交；测试场景/探针脚本随功能一起入库，方便继任者复跑

#### 下一步（按优先级，2026-10-28 已刷新为 P1 路线图）
1. **焚鼎 P3 火区灼烧视觉**：fire_hit 后玩家身上持续 0.4s 灼烧粒子
2. **投射物特效**：projectile.gd `_draw` 硬编码圆 → 精灵条弹道
3. **音效补缺**：dash / Boss 技能命中 / 火区爆炸
4. **C014 存档**：剪影左偏+伸展 <200px，适合做格挡/瞬移精英怪，不适合 Boss；C032 的 `transform2` 变身动画留着可开第 4 阶段
