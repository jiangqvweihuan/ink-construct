# 局域网联机功能 · 实现与测试验证报告

日期：2026-11-08
范围：同一局域网内的双人协作联机（主机权威 + 客户端镜像），沿用本机双人的 2 人同房间玩法。

---

## 一、功能实现概览

| 需求 | 实现位置 | 说明 |
| --- | --- | --- |
| 自动发现与配对 | `scripts/net/lan_discovery.gd` | 主机在 42420 监听探测并向 42421 广播信标；客户端在 42421 监听并主动探测（广播 + 回环兜底），主机单播回复 |
| 可靠点对点协议 | `scripts/net/net_protocol.gd` | `magic + type + ver + seq + len + payload(var_to_bytes) + crc32`；坏包/版本不符/长度不符一律丢弃并计数 |
| 主机创建 / 房间 / 成员 / 会话 | `scripts/net/lan_net.gd` | `host_room / join_room / start_game / set_ready / leave / host_change_room / host_end_session`，RPC 驱动完整会话状态机 |
| 断线重连 / 丢包 / 异常 | `scripts/net/lan_net.gd` | 心跳 2s、6s 无 pong 触发重连；主机保留席位 30s；客户端 1s 间隔最多重试 5 次；输入 200ms 过期、坏包计数 |
| 游戏状态同步 | `scripts/net/net_sync.gd` | 主机 20Hz 全量快照（玩家 + 敌人 + Run 摘要），客户端建/删镜像并按 `net_id` 插值 |
| 输入上送 | `scripts/net/lan_net.gd` | 客户端 30Hz 采样 P2 键位，`unreliable_ordered` 通道上送；主机侧读取即消费 |
| 大厅 UI | `scripts/ui/lan_panel.gd` + `scenes/ui/lan_panel.tscn` | 创建房间、扫描列表、自动加入、手动 IP、成员与就绪、开始、离开 |
| 入口接入 | `scripts/ui/mode_select.gd` | 「局域网联机」卡面改为实例化大厅面板 |

第三方依赖：未引入任何插件。发现层使用 Godot 内置 `PacketPeerUDP`，联机层使用内置 `ENetMultiplayerPeer`，无需下载安装。

---

## 二、端口与协议

| 项 | 值 | 说明 |
| --- | --- | --- |
| 游戏端口 | `42422/UDP` | ENet 主机监听，客户端连接 |
| 主机发现端口 | `42420/UDP` | 主机监听「探测」，客户端向此端口发探测 |
| 客户端扫描端口 | `42421/UDP` | 客户端监听「信标」，主机向此端口广播/单播 |
| ENet 通道 0 | RELIABLE | 控制：加入、就绪、开局、事件、离开 |
| ENet 通道 1 | UNRELIABLE_ORDERED | 输入帧与心跳 |
| ENet 通道 2 | UNRELIABLE_ORDERED | 快照 |
| 快照频率 | 20Hz | 全量快照，客户端缺失 300ms 才移除镜像 |
| 输入频率 | 30Hz | 方向轴 + 按住集合 + 本帧按下集合 |
| 信标频率 | 1s | 房间信息 TTL 3.5s |
| 心跳 / 超时 | 2s / 6s | 超时进入重连 |
| 重连宽限 / 重试 | 30s / 5 次 × 1s | 主机保留席位、客户端自动重试 |

封包格式：

```
[0]      magic 0x49 ('I')
[1]      type  1=INPUT 2=SNAPSHOT
[2]      version = 1
[3..6]   seq u32
[7..8]   payload len u16
[9..]    payload (var_to_bytes(Dictionary))
[尾 4B]  crc32(header+payload)
```

---

## 三、使用流程

1. 启动 -> 择途 -> 局域网联机。
2. 主机：填写房间名、玩法、问境、化身 -> 创建房间，等待队友。
3. 客机：大厅自动扫描同网段房间，点击列表房间「自动加入」；若广播被拦截，可手动输入主机 IP 后「直接加入」。
4. 客机点「我准备好了」，主机点「开始对局」，双方同时进入房间场景。
5. 主机跑完整战斗（P1 本机 + P2 远端输入），客机只上送输入并渲染主机快照。
6. 主机点「前进」推下一关时，由主机统一切场景并同步 Run 状态；对局结束/房主离开会通知客机回菜单。

同机双开调试：主机与客机均可用 `127.0.0.1`；客户端探测同时发往广播地址与 `127.0.0.1`，因此单机双开也能发现房间。

---

## 四、配置说明

### 1. Windows 防火墙

首次开房时系统可能弹出联网授权，需允许 Godot / 导出的游戏通过「专用网络」。
如未弹出或误点拒绝，可手动放行 UDP 入站：

```
42420, 42421, 42422  (UDP)
```

以管理员 PowerShell 放行示例：

```powershell
New-NetFirewallRule -DisplayName "InkConstruct LAN" -Direction Inbound -Protocol UDP `
  -LocalPort 42420,42421,42422 -Action Allow -Profile Private
```

两机需处于同一子网（同一路由器/同一 Wi-Fi），且路由器未开启「AP 隔离」。

### 2. Android

- 局域网联机需要网络权限。Godot 4 Android 导出默认包含 `android.permission.INTERNET`；若自定义导出模板移除了它，请在导出预设的自定义权限中补回：

```
android.permission.INTERNET
android.permission.ACCESS_NETWORK_STATE
```

- 若个别机型广播发现不生效，请使用「手动输入主机 IP」加入；同时确认 Wi-Fi 允许局域网设备互访。
- 手机端不显示「本机双人」，大厅与联机流程一致。

### 3. 端口占用排查

- 若提示「发现端口 42420 被占用」，通常是另一份游戏/调试进程仍在运行，结束进程后重试。
- 扫描端口 42421 被占用时会自动退回随机端口，仍能通过探测的定向回复发现房间，但广播信标可能收不到。

---

## 五、测试验证

### 1. 单元测试（单进程）

场景：`scenes/tests/net_unit_probe.tscn`
脚本：`scripts/tests/net_unit_probe.gd`

```powershell
& "E:\Godot\Godot_v4.6.2-stable_mono_win64_console.exe" --headless --path . `
  res://scenes/tests/net_unit_probe.tscn
```

覆盖：封包往返、CRC32 已知值、CRC 篡改拒绝、长度/魔数/版本拒绝、输入清洗（未知动作/去重/轴夹取）、快照清洗（玩家 ≤2、敌人 ≤64）、信标解析与拒绝、同进程自动发现、房间 TTL 过期、大厅 UI 实例化与开房视图、主机房间场景构建（双玩家 / NetSync / 敌人生成）。

实测结果（2026-11-08，日志 `tests/net_unit.log`）：

```
PROBE protocol_roundtrip PASS
PROBE crc32_known PASS
PROBE protocol_crc_reject PASS
PROBE protocol_length_reject PASS
PROBE protocol_magic_reject PASS
PROBE protocol_version_reject PASS
PROBE sanitize_axis_clamp PASS
PROBE sanitize_held PASS
PROBE sanitize_just PASS
PROBE sanitize_snapshot_players PASS
PROBE sanitize_snapshot_enemies PASS
PROBE sanitize_snapshot_run PASS
PROBE beacon_parse_ok PASS
PROBE beacon_reject_app PASS
PROBE beacon_reject_version PASS
PROBE discovery_host_bind PASS
PROBE discovery_scan_bind PASS
PROBE discovery_found_room PASS
PROBE discovery_ttl_expire PASS
PROBE lan_panel_instantiate PASS
PROBE lan_panel_host_room PASS
PROBE lan_panel_room_view PASS
PROBE room_host_netsync PASS
PROBE room_host_players PASS n=2
PROBE room_host_enemies PASS
PROBE RESULT fail=0
```

> 注：无头模式加载 Spine 时会打印既有的贴图路径告警（`res://art/characters/player/` 等），与联机功能无关，不影响断言结果。

### 2. 集成测试（双进程，真实 ENet）

场景：`scenes/tests/net_integration_probe.tscn`
脚本：`scripts/tests/net_integration_probe.gd`（`--role=host` / `--role=client`）

```powershell
$exe = "E:\Godot\Godot_v4.6.2-stable_mono_win64_console.exe"
$root = "E:\GodotProjects\ink-construct"

# 主机
Start-Process $exe -ArgumentList @('--headless','--path','.', `
  'res://scenes/tests/net_integration_probe.tscn','--','--role=host') `
  -WorkingDirectory $root -NoNewWindow

Start-Sleep -Seconds 3

# 客机
& $exe --headless --path . res://scenes/tests/net_integration_probe.tscn -- --role=client
```

覆盖链路：开房 -> 连接 -> 加入 -> 就绪 -> 开局 -> 客户端输入上送（主机确认收到）-> 主机快照下发（客户端确认玩家/敌人条目）-> 坏包被拒 -> 主动断开 -> 自动重连（`resumed=true`）-> 重连后快照序号继续推进 -> 正常离开。

实测结果（2026-11-08，日志 `tests/net_host.log` / `tests/net_client.log`）：

```
# 主机
PROBE host_create_room PASS
PROBE host_start_game PASS
PROBE host_remote_input PASS
PROBE host_bad_packet_rejected PASS
PROBE host_snapshot_sent PASS n=192
PROBE host_client_dropped PASS
PROBE host_client_rejoined PASS
PROBE RESULT fail=0

# 客机
PROBE client_join_call PASS
PROBE client_joined PASS resumed=false
PROBE client_joined PASS resumed=true
PROBE client_snapshot_players PASS
PROBE client_snapshot_enemies PASS
PROBE client_snapshot_seq PASS seq=41
PROBE client_reconnect PASS
PROBE RESULT fail=0
```

### 3. 局域网真机验证建议

本机测试使用回环地址完成；真机验证时请按以下步骤：

1. 两台设备连接同一 Wi-Fi/交换机，记录主机局域网 IP（`ipconfig`）。
2. 主机开房；客机大厅应能在 1~2 秒内看到房间（TTL 刷新）。
3. 若列表为空，先在客机手动输入主机 IP 直接加入，确认连通性；再排查防火墙 / AP 隔离。
4. 观察客机：P2 跟随主机操作移动/攻击，敌人位置平滑跟随；主机侧 P2 由客机输入驱动。
5. 断开客机 Wi-Fi 约 5 秒再恢复：客机应自动重连并继续同步（主机保留席位 30s）。

---

## 六、边界场景处理

| 场景 | 行为 |
| --- | --- |
| 广播被防火墙拦截 | 客户端探测附带回环/定向包，主机单播回复；大厅另提供手动 IP |
| 发现端口被占用 | 主机开房失败并提示；扫描端自动退回随机端口 |
| 坏包 / 截断包 | CRC、长度、魔数、版本任一不符即丢弃，计入 `bad_packets` |
| 序号过期 | 客户端丢弃 `seq <= snapshot_seq` 的快照 |
| 快照偶发丢失 | 全量快照 + 缺失 300ms 才移除镜像，避免闪烁 |
| 输入丢帧 | 下一帧全量输入到达即覆盖；`just` 200ms 过期，避免幽灵按键 |
| 客户端断线 | 主机保留席位 30s；客户端 1s 间隔最多重试 5 次，成功后 `resumed=true` |
| 重连失败 | 退出房间回大厅并给出提示 |
| 房满 | 拒绝加入并提示「房间已满」 |
| 版本不一致 | 拒绝加入并提示更新到同一版本 |
| 房主离开 / 对局结束 | 主机发送可靠事件后关闭连接，客机回菜单 |
| 客户端暂停 | 客户端禁用暂停菜单，避免与主机脱节 |

---

## 七、单机不受影响

所有联机分支都以 `Run.net_role != ""` 或 `net_puppet == true` 为前提：

- `player.gd` / 敌人 / Boss 脚本的 `net_puppet` 默认 `false`，单机路径不变。
- `room_01.gd` 仅在 `Run.net_role` 为 `host`/`client` 时走联机分支。
- 快照与输入采样只在 `LanNet.role` 非空时运行。

---

## 八、已知限制

- 不做客户端预测与回滚：客机操作需等主机执行后经快照回显，同局域网下延迟约 1 个快照周期（50ms）+ 渲染插值。
- 伤害数字、部分纯表现特效不镜像，客机以敌人血条/动作表现为主。
- 目前房间固定 2 人（沿用本机双人）。
- 无尽/冒险均可联机，但 Boss 战表现差异同上（无伤害数字镜像）。
