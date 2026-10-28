# 墨构 InkConstruct · 项目进度与路线图

> Godot 4.6.2 mono + spine-godot 4.2 水墨国风 Roguelite 横版动作
> 更新日期：2026-10-28（本文档已与代码现状全面对齐）

---

## 一、已实现 ✅

### 核心玩法

| 模块 | 文件 | 核心能力 |
|---|---|---|
| 玩家控制器 | `scripts/player/player.gd` + `scripts/player/skulls.gd` | **5 形态换头**（双刺·冷红绫 c021 / 梅剑·白疏影 c023 / 力僧·定山 c013 / 剑仙·洛惊鸿 z000 / 青笠·顾沧洲 c012，默认 c021）：各自独立骨架、普攻段、技能表、HUD 技能栏；普攻连段、多段技能命中、投射物（剑仙剑气）、blink 闪现、dash、jump、coyote、受伤无敌；Q 键呼出化身面板（暂停中选头，墨骨结算，契合 Lv3 免费）。技能支持可选字段：`poise`（自身霸体）/ `heal`（砸地回血，力僧 U 用） |
| 手感系统 | `scripts/systems/combat_feel.gd` | hitstop 顿帧、屏幕震、受击白闪；player 三档加速度（`accel`/`brake`/`turn_accel` 均 `@export`）、lunge 惯性（`brake*0.5`）、hit_at × 0.9 提前判定、预警泛红闪 0.2s；攻击后 30% 可取消窗口（`atk["cancel"]` 可调） |
| 小怪 AI | `scripts/enemies/c016.gd` + `scripts/enemies/enemy_types.gd` | 形态表驱动巡逻/追击/挑招式/出手令牌/攻击锁定/受击硬直分层（普通 vs 精英霸体）；三档加速度对齐玩家手感；range_probe 标定 ranges + hit_at |
| 敌人池 | `scenes/enemies/`（全部复用 c016.gd） | 小怪 4 种：c016 刀客 / z002 黑袍剑客 / c017 蛮兵 / c035 刺客；精英 3 种：c023_elite 落梅弓手 / c037_elite 大剑骑士 / c018_elite 双镰 |
| 波次刷怪 | `scripts/systems/wave_spawner.gd` | 每房 3 波（5/7/9 只，血量速度递增 + 精英混入），同屏上限 6，死一只补一只，波间喘息 1.6s；清完发 `all_cleared` |
| Boss 系统 | `scripts/enemies/boss.gd` + `scripts/enemies/boss_types.gd` | 五真身（墨霆巨兽骑手 C009 / 焚鼎紫焰巨汉 C015a1 / 武车双马战车 C001 / 碎岳墨甲巨汉 C008 / 鸣钟双斧武者 C032）；多阶段切换 + 变身无敌 + 僵直窗口 + 冲锋技 + **绕后转身演出**（配 `turn` 动画的 Boss 被穿裆时播调头动画再翻转朝向，不瞬转，转身期不还手是奖励窗口，带冷却防锁死）；C032 三套变身动画分 P2/P3；HUD 大血条 + 登场书法落款 + 运镜推拉；`ROSTER` 随机登场；每形态独立主题背景整图铺底 |
| 特效系统 | `scripts/systems/fx.gd` | GIF 精灵条逐帧播放器，12 条特效；Boss fx 配置表驱动 + 焚鼎 P3 封锁火区（聚气预警 → 火柱喷发 → 范围灼烧）；预警用程序化墨环（`tools/gen_telegraph.py`） |
| 房间流程 | `scripts/world/room_01.gd` + `scripts/systems/run_state.gd` | **3 普通房（波次清怪）→ Boss 房**；每清一房花墨骨强化三选一；首房出发前排赐福三选一；Boss 房按形态换主题背景（`BOSS_BG` 表）；普通房固定 4 棵远景树点缀 |
| 墨骨掉落 | `scripts/systems/bone_pickup.gd` | 敌人死亡掉墨骨：上抛落地 → 玩家靠近 95px 自动吸附 → 收下；14s 无人拾取消失；纯 `_draw` 墨点不依赖素材 |
| 关卡互动装饰 | `scripts/world/decor_interactive.gd` | 普通房随机刷 2-3 个可互动物件：卷轴回血 +1 / 香炉 +5 墨骨 / 石碑本房临时 buff（伤害 +2 或移速 ×1.25，换房自动失效）；走近 90px 自动触发 → decor_burst 爆开特效 + 飘字 + 音效（decor_pickup / decor_stele）→ 消失；香炉待机挂 decor_idle_fire 白焰 loop。**本体是程序化 `_draw` 临时绘制（偏简陋），待用户找到好素材整件替换（见 P1 标记）** |

### 经济 / 养成

| 模块 | 文件 | 说明 |
|---|---|---|
| 局内计数 | `scripts/systems/score.gd`（autoload Score） | 连击（窗口清零）/ 最高连击 / 击杀 / 墨骨；墨骨跨房间保留，开新局才清空；花墨骨 = 局内强化 + 换头 |
| 局外养成 | `scripts/systems/meta.gd`（autoload Meta） | `user://meta.json` 持久化；解锁条件：c021/c023 初始开放，力僧杀 25 → 青笠通关 1 → 剑仙杀 60（强度梯度，剑仙实测最强放最后）；契合度 Lv1(30) 冷却-10% / Lv2(80) 普攻+1 / Lv3(150) 化身免费 |
| 墨锭商栈 | `meta.gd` `INK_SHOP` + `forms_panel.gd` | 结算时本局剩余墨骨沉淀为局外货币**墨锭**；化身谱面板内消费：买断解锁（绕过条件）+ 永久开局加成（初始墨骨/生命上限，可升级） |

### UI / 流程

| 模块 | 文件 | 说明 |
|---|---|---|
| 主菜单 | `scripts/ui/main_menu.gd` | **启动场景**（`project.godot` run/main_scene）：水墨远山底 + 书法标题 + 开始/化身谱/设置/退出；启动时 `Settings.apply_all()` |
| 化身谱 | `scripts/ui/forms_panel.gd` | 主菜单入口：5 形态解锁条件/契合进度/各级加成一览 + 墨锭商栈 |
| 暂停菜单 | `scripts/ui/pause_menu.gd` | Esc 呼出：继续 / 设置 / 回主菜单 |
| 设置 | `scripts/ui/settings.gd` + `settings_panel.gd` | 音乐/音效音量（Music/SFX 总线）、全屏、分辨率（1280×720 / 1600×900 / 1920×1080）；`user://settings.cfg` 持久化，改动立即生效 |
| HUD | `scripts/ui/hud.gd` | 大血条 + 技能冷却遮罩 + 连击/墨骨 |
| 结算 | `scripts/ui/settlement_panel.gd` | 通关/阵亡结算 + 战绩行（最高连击/击杀/墨骨）+ 朱砂「讨伐 · Boss 名」+ 契合经验条动画 + 墨锭沉淀 |
| 换头面板 | `scripts/ui/swap_panel.gd` | Q 键呼出，暂停时间选形态 |
| 赐福 / 强化 | `scripts/ui/blessing_panel.gd` / `upgrade_panel.gd` | 开局三选一 / 每房清完墨骨三选一（cost = 8 + 4×已拥有等级）；强化池 = 通用 5 项 + **形态专属 10 项**（`FORM_UPGRADES` 按当前 skull 过滤：饮血/横扫/清心/阔剑/不动如山/裂地/穿云/双剑气/疾影/连突，player.set_upgrades 消费，投射物支持穿透+双发）；卡牌带 36px 水墨图标（`art/ui/icons/`） |
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
| 结算 | `settlement_clear_test.tscn` / `settlement_dead_test.tscn` |
| 特效/音效 | `fx_test.tscn`、`sfx_preview.tscn` |
| 骨架探针 | `range_probe.tscn`、`spine_probe.tscn`、`spine_test.tscn`、`hit_probe.tscn`、`hook_probe.tscn`、`anim_list.tscn`、`anim_sheet.tscn`、`anim_event_probe.tscn`、`face_check.tscn` |
| 战斗/UI 交互 | `combat_test.tscn`、`player_test.tscn`、`enemy_test.tscn`、`enemy_hit_test.tscn`、`skill_test.tscn`、`skill_preview.tscn`、`twitch_test.tscn`、`ui_test.tscn`、`settings_test.tscn`、`font_probe.tscn` |

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
| 力僧 U「定山」定位 | 低 | `skulls.gd` c013 | 蓄力 3.05s 期间**自身霸体**（挨打不断招），砸地造成 2 伤并**回 2 血**（`heal` 字段，与是否命中无关），9s 冷却——站桩换血的坦克循环，不再是纯自控 |
| push 报连接重置的排查顺序 | 中 | 全局 | 症状 `Recv failure: Connection was reset` / `Connection timed out`。按序查：①`git config --get http.proxy` 看是否写死代理 ②`curl.exe -x <代理> -I https://github.com` 测代理能否到目标站 ③代理通但 git 不通 → 换代理协议（HTTP ↔ SOCKS5，本项目实测 `socks5h` 可用、`http` 被重置）④协议通了仍失败 → `http.version=HTTP/1.1`（git 默认 HTTP/2 在该代理下被重置）。本仓库已固化 `socks5h://127.0.0.1:33210` + `HTTP/1.1`；**梯子关掉时 GitHub 直连完全不通（443 超时），必须开着梯子** |
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

- [ ] **额外化身**：素材库玩家骨架多的话，加第 6 个形态（SKULLS 加一项 + spine 三件套即可）
- [ ] **精英怪独立 AI 行为**：现在精英只是参数放大；可以加"蓄力重击"预警 1.5s 然后冲过来砸地（需要新骨架动画）

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
├── player/          # 玩家控制器 + 化身形态表（5 形态）
├── enemies/         # 通用小怪 AI c016.gd + 形态表 + Boss boss.gd + Boss 形态表
├── systems/         # fx 特效 + run_state + combat_feel + meta + score + wave_spawner + bone_pickup + projectile
├── audio/           # bgm.gd（autoload，双轨交叉淡化）
├── ui/              # main_menu / forms_panel / pause_menu / settings(+panel) / hud / settlement / swap / blessing / upgrade / damage_number / ink_tex
├── world/           # room_01
└── tests/           # 测试场景脚本

scenes/
├── ui/              # main_menu / forms_panel / pause_menu / settings_panel / hud / settlement / swap / blessing / upgrade
├── enemies/         # c016 / z002 / c017 / c035 + c023_elite / c037_elite / c018_elite + bosses/boss
├── player/          # player.tscn
├── world/           # room_01.tscn
└── tests/           # 测试场景（见上表）

audio/
├── music/           # home.wav（御风引·菜单）/ battle.wav（破阵·战斗）+ plot_01/02
├── bgm/             # bgm_menu.ogg / bgm_battle.ogg（备用）
└── sfx/             # ~28 条音效 wav

art/
├── characters/
│   ├── player/      # 5 形态骨架（skulls/<id>/ 三件套）
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

- **投射物特效用户不自理**：空闲就修改 `projectile.gd` 的 `_draw` 视觉
- **中文注释**：全项目中文注释
- **WTE 规范**：preload 不用 `class_name`、函数内不能声明 `const`
- **GIF → 精灵条**：spine-godot 4.2 不兼容老 Spine 3.8 GIF，统一走 `tools/gif2strip.py` + `key_alpha.py`

## 最重要
用户有无限的素材资源，想要查看或者使用啥的直接跟用户说想要看看新素材，我把整个文件给你你自己决断，当然，里面的spine版本可能比较低，你选好你想要的然后告诉我，我帮你转换成spine4.2版本

---

## 七、交接笔记

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
