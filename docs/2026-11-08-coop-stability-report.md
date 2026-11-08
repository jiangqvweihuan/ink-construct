# 联机稳定版（0.10.0）回归与发布报告

日期：2026-11-08
版本：`0.10.0`（Android versionCode 14）
范围：单人 / 本机双人 / 局域网 4 人；敌人生成、索敌、难度、复活、伤害平衡、双端导出。

## 一、局域网 4 人架构

- 协议版本 `PROTO_VERSION = 2`，`MAX_PLAYERS = 4`（1 主机 + 最多 3 名客机）。
- 主机权威：主机跑完整战斗（本机 P1 + 远端玩家输入），客机只上送输入、接收 20Hz 快照镜像。
- 槽位：主机 `slot 0`，客机动态分配 `1~3`；`Run.net_slot` 记录本机槽位，输入/血量/复活均按槽位分桶。
- 房间满时加入返回「房间已满（最多 4 人）」；断线重连沿用原预留槽位。
- 大厅：任一非房主成员全部就绪后才允许开始；提示「1~4 人，人数越多敌人越强」，并显示「人数 N / 4」。
- HUD：右上角按槽位纵向排列 P2/P3/P4 血条（226×22），主机与客机都能看到全队血量。
- 房间构建：主机按 `Run.player_count()` 生成 4 名角色（出生 x 偏移 `[0, 130, -130, 260]`），客机生成同数量镜像（`net_puppet = true`），相机跟随本机槽位。

## 二、敌人生成安全距离

`wave_spawner.gd`：

- 新增 `spawn_safe_dist = 320`：出生点 `Vector2(x, spawn_y)` 与所有存活玩家（`hp > 0` 且 `state != 8`）的 **2D 距离** 必须 ≥ 320px，因此不会刷在面部/头顶（跳跃到高处也不会贴脸）。
- 固定出生点全部不安全时，在 600~1800 范围内按 100px 采样一圈；仍无安全点则本次 **延迟刷新**（返回 `NAN`，0.2s 后重试），绝不回落到贴脸位置。
- 同时保留与存活怪的水平间距 `> 110px`，避免怪物重叠。
- 房间把 4 名玩家引用传入 `spawner.player_refs`，多人局同样生效。

## 三、多人索敌：锁定最近玩家

`c016.gd`（普通怪通用索敌）：

- `nearest_living_player(from, nodes)`：遍历所有玩家，跳过已阵亡（`hp <= 0` 或 `state == 8`）与正在删除的节点，按平方距离取最近者。
- 目标变化后（原目标死亡/远离）立即改锁最近存活玩家，不再随机/黏住旧目标；全部玩家阵亡返回 `null`。
- 死亡自爆/前扑改为遍历全部存活玩家，不再固定只打 P1。
- 攻击者记录到 `Run.last_hit`，联机结算面板仍能正确显示补刀来源。

## 四、按人数动态难度

`Run.ENEMY_BALANCE` 按 `Run.player_count()` 取行（联机取 `net_players`，本机双人 2，单人 1）：

| 人数 | 生命 | 伤害 | 出手间隔 | 玩家承伤 | 波次数量 | 同屏上限 | 补怪间隔 | Boss 阶段伤害 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1P | 1.30 | 1.20 | 0.90 | 0.94 | 0.75 | 4 | 1.10 | 0.10 |
| 2P | 1.95 | 1.20 | 0.80 | 0.88 | 0.95 | 6 | 0.85 | 0.12 |
| 3P | 2.40 | 1.18 | 0.76 | 0.85 | 1.05 | 7 | 0.78 | 0.14 |
| 4P | 2.85 | 1.16 | 0.72 | 0.82 | 1.15 | 8 | 0.72 | 0.16 |

- 人数越多：敌人更硬、更多、出手更密；单击伤害倍率保持 1.16~1.20，取整后与单人同档。
- 局域网加入/离开时 `LanNet` 调用 `Run.set_net_players(members.size())`，后续波次立即套用对应行。

## 五、复活机制与伤害上限

- 联机按槽位独立生命：`Run.slot_hp / slot_dead / slot_revive`；形态、强化、赐福仍整局共享。
- 任意玩家阵亡：`Run.mark_slot_dead(slot)` 标记，进入下一房间时 `Run.advance()` 统一结算 `slot_revive`，按 **50% 生命上限** 复活；快照随房间同步下发，客机无需复活标记即可正确显示。
- 单击伤害硬上限 `Run.cap_enemy_hit(amount, target_max_hp)`：正式对局不超过目标生命上限的 **50%**（向上取整，`MAX_ENEMY_HIT_RATIO = 0.5`），小兵至少两击才可能击倒玩家；`balance_scaling == false`（测试/斗蛐蛐）时不生效。
- 例：8 血角色上限 4、12 血角色上限 6、梅剑 60 血上限 30；4 人局小兵单击最多 4 点，不会一击秒杀 8 血角色。

### 红蝶（c021）与梅剑（c023）

- 红蝶复活：新增 `Run.c021_revive_cap = 50`；复活后 `calculated_max_hp()` 封顶 50，复活血量同为 50（不再是满 100），**每秒 1 点生命流失保持不变**，燃尽死亡仍走「命火自熄」结算，不重演历史受击。
- 梅剑复活：先按 50% 拿 30 点；进入新房间时由 `on_room_enter()` 的「每房回满」补到 60，核心机制保留。

## 六、回归测试结果

命令统一为（测试隔离存档目录）：

```powershell
$env:APPDATA="E:\GodotProjects\ink-construct\.test_appdata_full"
& "E:\Godot\Godot_v4.6.2-stable_mono_win64_console.exe" --headless --path . res://scenes/tests/<scene>.tscn
```

| 测试 | 结果 |
| --- | --- |
| character_balance_probe | checks=21 fail=0 |
| enemy_balance_probe | checks=41 fail=0（含 1P~4P 独立数值行） |
| coop_balance_probe（本轮新增） | checks=21 fail=0（出生距离 / 最近索敌 / 伤害上限 / 复活血量） |
| net_unit_probe | fail=0（协议/清洗/发现/大厅 + 2 人与 **4 人房间**：4 玩家、槽位 0~3、生成器引用 4） |
| net_integration_probe（主机+客机双进程） | host fail=0 / client fail=0（建房、加入、开局、远端输入、坏包拒绝、断线重连） |
| player_test | checks=105 failed=0 |
| pipa_test | checks=195 failed=0 |
| sui_yue_test / fen_ding_test / mo_ting_test | 102 / 87 / 94 failed=0 |
| ming_zhong_test / wu_che_test / enemy_test | 80 / 79 / 27 failed=0 |
| ui_test / enemy_hit_test / start_flow_test | ALL DONE（无断言失败） |
| settlement_dead_test | checks=18 failed=0（红蝶纯流失死亡用例已按 50% 伤害上限适配） |
| settlement_clear_test | checks=9 failed=1：仅「战斗内隐藏鼠标」在 headless 下 `Input.mouse_mode` 无法生效 |
| settings_test | 窗口分辨率/位置断言在 headless 下返回 (0,0)，属无窗口环境限制 |

本次修复：`settlement_dead_test` 原通过 `hurt(20)` 直接击杀触发红蝶；加入 50% 单击上限后不可能一击致死，测试改为显式标记「红蝶已消耗」后走纯流失燃尽，断言全部通过。

## 七、双端导出

- Windows：`build/windows/InkConstruct.exe`（Release，内嵌 PCK，约 388 MB），导出成功。
- Android：`build/android/InkConstruct.apk`（Debug 导出 + Godot 调试签名 `debug.keystore`，arm64-v8a，versionName 0.10.0 / versionCode 14），导出并验签成功。
- 说明：仓库内无正式 `.keystore/.jks`，因此 Android 只能产出调试签名包；商店发布需提供正式签名文件后重新导出 Release。

## 八、版本与提交

- `project.godot`：`config/version = "0.10.0"`。
- `export_presets.cfg`：Android `version/code = 14`、`version/name = "0.10.0"`。
- `build/` 已在 `.gitignore` 中忽略，不入库；产物保留在本地。
