# 电脑版 P2 改键 与 局域网联机 验证报告（2026-11-08）

> 验证目标：① 电脑版设置里能否自定义 P2 操作、该能力的可用性/生效范围/异常场景；② 电脑端与手机端的局域网联机是否可测、现状如何。
> 验证方式：静态代码审计 + 运行时探针（隔离 `user://`，不污染真实配置）。
> 结论性质：本次为**验证/研究**，未实现 P2 改键，也未实现真实联网；报告中“建议”部分不代表已落地。

## 0. 结论速览

| 验证项 | 结论 | 关键证据 |
|---|---|---|
| P2 操作能否自定义 | **不支持**（无任何入口） | 改键页仅 11 个 P1 动作；配置结构体无 `p2_*` |
| P2 键位是否可持久化 | **不能** | `settings.cfg` 的 `binds` 只写 P1 |
| P2 键位的实际来源 | 硬编码常量，进入双人时运行时注册 | `LocalCoop.P2_BINDS` / `ensure_input()` |
| P1 改键是否影响 P2 | **会**：P1 可抢 P2 保留键，造成同键双触发 | 冲突守卫只遍历 P1 表 |
| 局域网联机是否可用 | **不可用**，仅 UI 占位 | 全项目无网络 API 调用；点击只弹提示窗 |
| 桌面/手机入口是否正确 | 正确：桌面 3 项、手机预览 2 项，占位窗可开可关 | 探针均 0 失败 |

---

## 1. 步骤一：代码提交与推送

| 项 | 值 |
|---|---|
| 提交 | `1f74b4a feat: 手机触屏键位方案与电脑本机双人联机` |
| 推送 | `b3399a7..1f74b4a  main -> main` |
| 结果 | 成功，远程仓库已是最新 |

推送后工作区仅剩本次验证用的临时目录 `.test_appdata/`（隔离 `user://` 用，不属于产品代码），验证结束已清理。

---

## 2. 步骤二：电脑版 P2 自定义操作

### 2.1 静态研究：改键能力的边界

| 环节 | 代码事实 | 位置 |
|---|---|---|
| 可改键动作表 | `DEFAULT_BINDS` 仅 11 个 P1 动作（A/D/Space/Shift/J/K/L/U/I/O/P），无 `p2_*` | [settings.gd](file:///e:/GodotProjects/ink-construct/scripts/ui/settings.gd#L15-L19) |
| 动作显示名 | `ACTION_NAMES` 同样只有这 11 个 | [settings.gd](file:///e:/GodotProjects/ink-construct/scripts/ui/settings.gd#L22-L26) |
| 配置快照 | `snapshot()` 只导出 `binds`（P1 表）等字段，无 P2 字段 | [settings.gd](file:///e:/GodotProjects/ink-construct/scripts/ui/settings.gd#L171-L180) |
| 应用配置 | `apply_snapshot()` 只遍历 `DEFAULT_BINDS` 逐项写 InputMap，其余 `binds` 键一律忽略 | [settings.gd](file:///e:/GodotProjects/ink-construct/scripts/ui/settings.gd#L206-L210) |
| 改键页列表 | `KEY_ORDER` 为 11 个 P1 动作，桌面页按此建按钮 | [settings_panel.gd](file:///e:/GodotProjects/ink-construct/scripts/ui/settings_panel.gd#L28-L31) [settings_panel.gd](file:///e:/GodotProjects/ink-construct/scripts/ui/settings_panel.gd#L358-L367) |
| 冲突守卫 | `_draft_action_for_key()` 只查 `Settings.DEFAULT_BINDS`，不认识 P2 保留键 | [settings_panel.gd](file:///e:/GodotProjects/ink-construct/scripts/ui/settings_panel.gd#L493-L497) |
| P2 键位来源 | `P2_BINDS` 硬编码常量；`ensure_input()` 在运行时注册 `p2_*` 动作 | [local_coop.gd](file:///e:/GodotProjects/ink-construct/scripts/systems/local_coop.gd#L13-L26) [local_coop.gd](file:///e:/GodotProjects/ink-construct/scripts/systems/local_coop.gd#L44-L56) |
| 手机操作页 | 触屏版该页换成手势/摇杆说明，压根没有键位项 | [settings_panel.gd](file:///e:/GodotProjects/ink-construct/scripts/ui/settings_panel.gd#L353-L357) |

设计意图（代码注释已写明）：P2 动作刻意不写进 `project.godot`，就是为了“不和设置面板里的单人改键表混在一起”。因此当前架构下 P2 改键不是“漏做”，而是**未纳入配置体系**。

### 2.2 动态验证：运行时探针

**方法**：新建临时探针场景，直接实例化设置面板与模式选择，读取真实 `InputMap` 与 `settings.cfg`；用 `InputMap.event_is_action()` 做键位归属判定（避免依赖不稳定的按键注入）。

**环境**：Godot 4.6.2 stable mono，Windows，`APPDATA` 指向工程内隔离目录。

| # | 探针断言 | 结果 |
|---|---|---|
| 1 | `Settings.DEFAULT_BINDS` 无 `p2_attack` | 通过 |
| 2 | `Settings.ACTION_NAMES` 无 `p2_attack` | 通过 |
| 3 | `snapshot().binds` 无 P2 键 | 通过 |
| 4 | 改键页只有 11 项：`attack/dash/jump/move_left/move_right/skill/skill_i/skill_o/skill_p/skill_sweep/skill_ult` | 通过 |
| 5 | 改键页不含 `p2_*` | 通过 |
| 6 | 未进入双人前 `InputMap` 无 `p2_attack`（惰性注册） | 通过 |
| 7 | 调用 `LocalCoop.ensure_input()` 后存在 | 通过 |
| 8 | 小键盘 1 → `p2_attack` | 通过 |
| 9 | ← → `p2_move_left` | 通过 |
| 10 | ← 默认不触发 P1 `move_left`（P1 已移除方向键备用绑定） | 通过 |
| 11 | P1 普攻改到小键盘 1 后，同键同时触发 `attack` 与 `p2_attack` | 通过（问题复现） |
| 12 | P1 左移改到 ← 后，同键同时触发 `move_left` 与 `p2_move_left` | 通过（问题复现） |
| 13 | P1 改键不会改动 `p2_attack` 的事件列表 | 通过 |
| 14 | `_draft_action_for_key(KEY_LEFT) == ""`（守卫不认 P2 保留键） | 通过（问题复现） |
| 15 | `settings.cfg` 可读，落盘 `binds` 仅 `{attack: 4194439, move_left: 4194319}`（小键盘1 / ←） | 通过 |
| 16 | 落盘内容无 `p2_attack` | 通过 |

**探针总结论**：`PROBE RESULT fail=0`（16/16 全部符合预期）。

### 2.3 可用性结论

- **功能不存在，不存在“可用性”问题**：设置面板没有 P2 页签、没有 P2 动作行、没有 P2 捕获流程。
- **生效范围**：改键只作用于 11 个 P1 动作，且只在桌面版可见（手机操作页为触屏说明）。
- **P2 键位生效范围**：`p2_*` 动作仅在 `LocalCoop.ensure_input()` 被调用后进入 `InputMap`（进入本机双人 / 模式选择点“本机双人”），且一旦注册即为常量，不会被任何设置项覆盖。
- **持久化**：`settings.cfg [input] binds` 只保存 P1；读回时忽略一切非 `DEFAULT_BINDS` 的键，所以即使手工往文件里塞 `p2_attack` 也不会生效。

### 2.4 潜在异常场景（已确认或可推导）

| 场景 | 现象 | 严重度 | 说明 |
|---|---|---|---|
| P1 把普攻/技能改到小键盘 1~8 | 一颗键同时触发 P1 与 P2 动作 | 高 | **已实测**；双人时两人会同时出招 |
| P1 把左/右移改到 ← / → | 一颗方向键同时推动两个角色 | 高 | **已实测** |
| P1 把跳跃/闪避改到 ↑ / ↓ | 同上，两人同时跳/闪 | 高 | 同一机制推导（守卫不覆盖） |
| 改键冲突提示 | 抢占 P2 保留键时**没有任何警告** | 中 | `_draft_action_for_key` 只查 P1 表 |
| 恢复默认设置 | 只恢复 P1，P2 本来就没有可恢复项 | 低 | 行为一致，不产生脏数据 |
| 手工编辑 `settings.cfg` 加 `p2_*` | 不报错、不生效，且下次保存会被原样写回（脏字段） | 低 | `apply_snapshot` 忽略非 P1 键 |
| 手机端寻找 P2 改键 | 操作页只有触屏方案与布局调整，无键位项 | 低 | 手机本来无双人 |

**根因**：P2 输入走的是独立的 `p2_` 动作命名空间，与 `Settings` 的 P1 绑定表完全解耦；设置面板的冲突守卫也只认 P1 表。二者共用同一套物理键盘，才会出现“一键双触发”。

### 2.5 如后续需要支持（仅建议，本次未实现）

1. 把 P2 绑定并入 `Settings`：新增 `P2_DEFAULT_BINDS`，`snapshot/apply_snapshot` 合并应用，落盘仍写同一 `[input] binds`（用 `p2_` 前缀区分）。
2. 设置面板增加“操作 · P2”页签，复用现有捕获流程，并在 `_draft_action_for_key` 里跨 P1/P2 查重。
3. `LocalCoop.ensure_input()` 改为“注册动作 + 读取用户绑定”，保留常量作为默认值。
4. 冲突策略建议：P2 保留键被 P1 占用时给出显式提示并禁止确认，或自动互换。

---

## 3. 步骤三：电脑端与手机端局域网联机

### 3.1 静态研究：是否存在联网实现

| 检索项 | 结果 |
|---|---|
| `ENetMultiplayerPeer` / `WebSocketMultiplayerPeer` / `MultiplayerAPI` / `@rpc` / `MultiplayerSpawner` / `MultiplayerSynchronizer` | 全项目（产品代码）**0 命中** |
| `create_server` / `create_client` / `connect_to_host` / `TCPServer` / `UDPServer` / `PacketPeer` | **0 命中** |
| `project.godot` 网络相关配置 | 无（仅有窗口/视口/渲染项） |
| 局域网入口实现 | 只构建 dim + 窗纸 + 文案 + 返回按钮，无任何网络调用 | [mode_select.gd](file:///e:/GodotProjects/ink-construct/scripts/ui/mode_select.gd#L222-L274) |

结论：**当前没有任何组网代码**，局域网入口是纯 UI 占位；运行时 `multiplayer.multiplayer_peer` 保持 Godot 默认的 `OfflineMultiplayerPeer`（离线）。

### 3.2 桌面端探针

| # | 断言 | 结果 |
|---|---|---|
| 1 | 入口为 3 项：单人 / 本机双人 / 局域网 | 通过 |
| 2 | 点击局域网弹出占位层 | 通过 |
| 3 | 不发生场景切换（仍停在模式选择） | 通过 |
| 4 | 不进入战斗：`Run.active == false`、`Run.local_coop == false` | 通过 |
| 5 | 场上无玩家实例（`player` 组为 0） | 通过 |
| 6 | `multiplayer_peer` 仍为 `OfflineMultiplayerPeer` | 通过 |
| 7 | 文案为“局 域 网 联 机 / 此卷尚在研制 / 入口已预留，组网对局将于后续版本开放。” | 通过 |
| 8 | 遮罩 `MOUSE_FILTER_STOP`，点击不会穿透到下层卡面 | 通过 |
| 9 | 存在返回按钮 | 通过 |
| 10 | 重复点击不叠加第二个占位层 | 通过 |
| 11 | 返回按钮关闭占位层，且仍未开局、仍在模式选择 | 通过 |
| 12 | 场景树内无 Multiplayer/ENet/WebSocket 节点 | 通过 |

`PROBE RESULT fail=0`（桌面端）。

### 3.3 手机端（`--touch-preview`）探针

| # | 断言 | 结果 |
|---|---|---|
| 1 | 入口为 2 项：单人 / 局域网 | 通过 |
| 2 | 无“本机双人”入口 | 通过 |
| 3 | 点击局域网弹出占位层、文案正确 | 通过 |
| 4 | 不切场景、不开局、无玩家实例、无网络对端 | 通过 |
| 5 | 遮罩拦截穿透、返回可关闭、重复点击不叠加 | 通过 |

`PROBE RESULT fail=0`（手机预览）。

### 3.4 结论与差距

- **结论**：电脑端与手机端的“局域网联机”目前**不具备可测试的业务路径**——两端都无法创建房间、无法发现彼此、没有传输层。本次能验证的只有入口与占位表现，且桌面 / 手机均符合设计预期（桌面 3 项、手机 2 项、占位窗不影响任何游戏状态）。
- **若要做真正的联机，尚缺（按依赖顺序）**：
  1. 传输与会话层：`ENetMultiplayerPeer` 创建/加入、主机与客机角色、局域网发现（广播或手动填 IP）。
  2. 房间与开局协商：模式/难度/角色选择同步，双方就绪后统一进 `room_01`。
  3. 世界同步：敌人波次、Boss 状态、命中与伤害判定必须由主机权威结算（当前战斗逻辑为完全本地、随机数分散，直接多端跑会分叉）。
  4. 输入同步：远端玩家输入 → 本地代理角色；`input_slot` 需要扩展为网络槽位。
  5. 容错：断线重连、中途退出、版本/配置不一致提示。
  6. 跨端差异：手机无键盘，需复用现有触屏方案；两端分辨率/帧率不同，需确认逻辑帧与结算一致性。

---

## 4. 风险与建议

| 风险 | 影响 | 建议 |
|---|---|---|
| P1 改键抢占 P2 保留键 | 双人时一键双触发，体验错乱 | 短期：在改键页把 P2 保留键标记为“占用/禁用”；长期：纳入统一绑定表并跨表查重 |
| 局域网入口存在但无功能 | 玩家点进去只看到“尚在研制”，属可接受的占位；但若对外发布需确认文案 | 保持现占位；联机功能上线前不要移除入口 |
| 无网络代码却出现在模式选择第一屏 | 可能被误认为已支持 | 已在入口 foot 标注“入口已留 · 尚在研制”，建议保留 |

---

## 5. 附录

### 5.1 验证环境

| 项 | 值 |
|---|---|
| 引擎 | Godot 4.6.2 stable mono |
| 平台 | Windows（NVIDIA RTX 4070 Laptop，OpenGL 3.3 Compatibility） |
| 逻辑分辨率 | 1280×720（stretch canvas_items / keep_height） |
| 配置隔离 | `APPDATA=E:\GodotProjects\ink-construct\.test_appdata` |

### 5.2 复现命令

```powershell
$env:APPDATA="E:\GodotProjects\ink-construct\.test_appdata"
& "E:\Godot\Godot_v4.6.2-stable_mono_win64_console.exe" --path . res://build/probe_p2_settings.tscn *> build\probe_p2_settings.txt
& "E:\Godot\Godot_v4.6.2-stable_mono_win64_console.exe" --path . res://build/probe_lan.tscn *> build\probe_lan.txt
& "E:\Godot\Godot_v4.6.2-stable_mono_win64_console.exe" --path . --touch-preview res://build/probe_lan.tscn *> build\probe_lan_mobile.txt
```

### 5.3 临时文件

探针脚本、场景与输出（`build/probe_p2_settings.*`、`build/probe_lan.*`）及隔离目录 `.test_appdata/` 均为验证用临时产物，验证完成后已删除，不进入仓库。
