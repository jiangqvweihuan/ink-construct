# 红蝶复活音效实装 + 多人小怪摆头修复 · 测试报告

- 日期：2026-11-08
- 引擎：Godot 4.6.2 stable mono（`Godot_v4.6.2-stable_mono_win64_console.exe`）
- 运行方式：`--headless --path E:\GodotProjects\ink-construct --log-file ...`
- 结论：6 个需求点全部完成，自动化验证 0 失败；真机听感（音量平衡、音画同步）需在编辑器/实机内人工确认，见第五节。

## 一、结论摘要

| # | 需求 | 结果 | 证据 |
|---|------|------|------|
| 1 | 音效资源导入与路径校验 + 单独加载测试 | 完成 | 40/40 检查（含 17 项资源/通道用例） |
| 2 | 复活生命周期节点绑定，不漏不误 | 完成 | 红蝶分支唯一注入点，6 条致死入口共用 |
| 3 | 音量 / 优先级 / 3D 参数按规范配置 | 完成 | 独立通道 + SFX 总线 + 0 dB；项目无 3D 音频 |
| 4 | 完整功能联调（延迟/重复/中断） | 完成 | 同帧触发、每局 1 次、独立通道不被打断 |
| 5 | 音效冲突检测（技能音 / BGM） | 完成 | SFX/Music 分总线，三路同播互不覆盖 |
| 6 | 多人夹击小怪快速摆头修复 | 完成 | 3 秒夹击晃动翻面 0 次；回归 27/27、21/21 |

## 二、需求逐项验证

### 1. 资源导入与路径校验

- 源文件：`e:\素材\墨构素材库\音效\绯刃触发红蝶复活的专属音效.wav`
- 项目内路径：`res://audio/sfx/assassin_revive.wav`（沿用绯刃既有 `assassin_*` 命名）
- 文件大小 635,652 字节，与源文件 MD5 一致：`1E503AF6C9AA34E056AE4248DAB55353`
- 导入产物：
  - `audio/sfx/assassin_revive.wav.import`
  - `.godot/imported/assassin_revive.wav-c321fe15f276d64b0e936fe18c66f92d.sample`（128,934 字节）
- 导入参数与既有同类音效（`assassin_basic_attack.wav.import`）逐项一致：
  `importer="wav"`、`edit/loop_mode=0`、`compress/mode=2`、`force/max_rate_hz=44100`、`force/8_bit=false`、`force/mono=false`

单独资源加载测试（无头运行专用探针）：

| 检查项 | 结果 |
|--------|------|
| `ResourceLoader.exists("res://audio/sfx/assassin_revive.wav", "AudioStream")` | PASS |
| `load()` 返回 `AudioStreamWAV`，时长 3.31s | PASS |
| `SFX` 总线存在 | PASS |
| `player_audio` 预载缓存命中且与直接 `load()` 同一资源 | PASS |
| `play_full` 返回独立 `AudioStreamPlayer`，仅新增 1 个通道 | PASS |
| 独立通道 `bus == "SFX"`、`volume_db == 0.0`、音源正确 | PASS |
| 调用后同帧 `playing == true` | PASS |
| 播放结束自动 `queue_free`，无残留通道 | PASS |

> 全端一致性：路径使用 `res://` 资源路径，与既有音效同一目录、同一导入器，不依赖外部绝对路径。

### 2. 复活生命周期节点绑定

- 绑定位置：[player.gd](file:///E:/GodotProjects/ink-construct/scripts/player/player.gd#L4584-L4590) `_try_revive()` 的 `if red_butterfly:` 分支尾部，与红蝶专属 `E54015` 特效同帧。
- 唯一性与覆盖面：`hurt`、流血 `_bleed_damage`、割伤 `_cut_damage`、魅唤/其他致死路径共 6 处调用 `_try_revive()`，全部收敛到同一出口，不存在漏绑。
- 不误触发：`red_butterfly` 仅在 `skull_id == "c021"` + 拥有被动 `c021_red_butterfly` + `Run.c021_red_butterfly_used == false` 时为真；赐福复活、复活墨符、其他角色、红蝶已消耗后均不会进入该分支。
- 不重复：进入分支前已将 `Run.c021_red_butterfly_used` 置 true（每局一次）。

验证结果（探针用例）：

| 场景 | 结果 |
|------|------|
| 红蝶首次被击败复活 | PASS：同帧新增 1 个复活音通道并立即播放 |
| 红蝶已消耗后再次归零 | PASS：进入死亡，不再播放 |
| 续命赐福复活 | PASS：复活成功，不播放红蝶音 |
| 复活墨符复活 | PASS：复活成功，不播放红蝶音 |
| 流血致死触发红蝶复活 | PASS：播放 1 次 |
| 割伤致死触发红蝶复活 | PASS：播放 1 次 |
| 非绯刃角色（c013）死亡 | PASS：不播放 |

### 3. 音量 / 播放优先级 / 3D 参数

- 音量：`0.0 dB`，与项目既有「完整施法音」默认音量一致；最终响度由 `Settings` 的 `SFX` 总线音量统一控制。
- 播放优先级：使用 [player_audio.gd](file:///E:/GodotProjects/ink-construct/scripts/player/player_audio.gd#L93-L105) 的 `play_full()`，每次新建独立 `AudioStreamPlayer`，`finished -> queue_free`。复活音不会与共享 `sfx_player` 上的普攻/受击短音抢通道，等效于最高播放优先级。
- 3D 参数（衰减距离、空间混响）：**不适用**。项目为 2D 水墨横版，工程内 `AudioStreamPlayer2D` / `AudioStreamPlayer3D` 使用数为 0，全部技能音效、BGM 均为非定位 2D 音频；因此本音效按同类技能音效标准走全局 `SFX` 总线，跨端表现一致，不存在需要标定的衰减/混响参数。

### 4. 完整功能联调

覆盖要求：无播放延迟、无重复触发、无中断异常。

| 验证点 | 结果 |
|--------|------|
| 复活瞬间音效与复活逻辑同帧触发（探针在 `hurt()` 返回后立即计数，未等待任何帧） | PASS |
| 每局仅触发一次（红蝶被动本身每局一次） | PASS |
| 播放中叠加普攻短音（共享通道） | PASS：复活音仍在播放，音源未被替换 |
| 播放中叠加 BGM | PASS |
| 3.31s 完整播放后自动释放节点 | PASS |

### 5. 音效冲突检测

| 验证点 | 结果 |
|--------|------|
| 复活音（SFX）与背景音乐（Music）分属两条总线 | PASS |
| BGM + 普攻短音 + 复活音三路同播，互不覆盖 | PASS |
| 与同类技能音效共用 `SFX` 总线，但快捷键音走独立通道，不会互相截断 | PASS |
| 异常叠加：复活分支只在一次红蝶复活内执行一次，不存在同一帧重复 `play_full` | PASS |
| 音量链路：`SFX` 总线滑条对复活音生效（与全部短音一致） | PASS |

### 6. 多人模式小怪左右快速摆头修复

根因：`_find_target()` 每物理帧重选「最近存活玩家」，两名玩家距离接近时目标逐帧切换；`_chase_tick()` 随即按目标 `dx` 立即翻面，形成逐帧左右摆头。

修复（[c016.gd](file:///E:/GodotProjects/ink-construct/scripts/enemies/c016.gd)）：

- 目标滞回 `TARGET_STICKY_RATIO = 0.75`：当前目标仍存活且未脱战时，新目标必须近 25% 以上才换人。
- 朝向死区 `FACE_DEADZONE = 22.0`：目标在中线附近小幅横移不翻面。
- 翻面冷却 `FACE_SWITCH_COOLDOWN = 0.12`：两次翻面之间留出转向反应时间。
- 变量 `_face_cd` 在 `_physics_process` 中按帧衰减。

验证结果：

| 场景 | 结果 |
|------|------|
| 左右各一名玩家、分别微幅晃动 3 秒 | PASS：翻面 0 次（修复前会随距离交替连续翻面） |
| 夹击期间目标保持不切换 | PASS |
| 新目标仅近 10% 时保持原目标 | PASS：不误换 |
| 新目标明显更近时切换 | PASS：不会因为滞回而锁死 |
| 冷却期内保持朝向，冷却结束才转身 | PASS |
| 小怪整体 AI 回归（巡逻/追击/攻击/受击/死亡/各精英专项） | PASS：27/27 |
| 联机稳定性探针（出生距离、最近玩家索敌、复活与伤害上限） | PASS：21/21 |

> `net_puppet` 联机镜像在 `_physics_process` 开头直接 return，本次改动不影响主机快照驱动的表现路径。

## 三、回归测试汇总

| 测试 | 日志 | 结果 |
|------|------|------|
| 本次音效 + 朝向专用探针 | `tests/audio_facing_probe.log` | 40/40，0 失败 |
| 玩家全量回归 | `tests/player_test.log` | 105/105，0 失败 |
| 小怪全量回归 | `tests/enemy_test.log` | 27/27，0 失败 |
| 联机稳定性探针 | `tests/godot_coop_probe.log` | 21/21，0 失败 |
| 设置/音量回归 | `tests/settings_test.log` | 音量与 BGM 切换通过；2 项分辨率用例 FAIL |

环境说明（非本次改动引入）：

- `settings_test` 的 2 项 FAIL 是 `分辨率应用` / `延迟后窗口保持`，无头模式下窗口尺寸为 `(0,0)` 无法应用分辨率，与音频无关；`Music/SFX` 总线与 BGM 快速切换均 PASS。
- 无头运行日志中会出现 Spine 图集贴图的 `Resource file not found: res://art/...` 报错，该现象在未修改的 `enemy_test` 中同样出现且测试全通过，属于无头环境纹理加载限制，不影响音频与 AI 逻辑验证。

## 四、改动清单

| 文件 | 改动 |
|------|------|
| `audio/sfx/assassin_revive.wav`（新增） | 导入的红蝶复活专属音效 |
| [player_audio.gd](file:///E:/GodotProjects/ink-construct/scripts/player/player_audio.gd#L22) | `SFX_PRECACHE` 增加 `assassin_revive`，开局预载 |
| [player.gd](file:///E:/GodotProjects/ink-construct/scripts/player/player.gd#L4584-L4590) | `_try_revive()` 红蝶分支调用 `_play_full_sfx("assassin_revive", 0.0)` |
| [c016.gd](file:///E:/GodotProjects/ink-construct/scripts/enemies/c016.gd#L22-L26) | 新增目标滞回/朝向死区/翻面冷却常量 |
| [c016.gd](file:///E:/GodotProjects/ink-construct/scripts/enemies/c016.gd#L2493-L2504) | `_find_target()` 玩家目标滞回 |
| [c016.gd](file:///E:/GodotProjects/ink-construct/scripts/enemies/c016.gd#L649-L654) | `_chase_tick()` 翻面死区与冷却 |

## 五、遗留事项与建议

1. 无头运行无法输出真实声音，音量平衡与音画同步请在实际游戏内试听一次（红蝶首死瞬间）。
2. 若希望小怪转身更「迟钝」或更「灵敏」，只需微调 `FACE_SWITCH_COOLDOWN` / `TARGET_STICKY_RATIO`，无需改动其他逻辑。
3. 同局多名 c021 玩家仍遵循既有设计「红蝶每局全局一次」，因此复活音每局最多播放一次；如需按玩家独立计算，需要另开需求调整 `Run.c021_red_butterfly_used` 的存储结构。
