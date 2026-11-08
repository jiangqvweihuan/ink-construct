extends RefCounted

## 局域网联机常量：端口、协议版本、频率与可同步动作。集中放置，便于测试与后续调整。

const APP_ID := "ink_construct"
const PROTO_VERSION := 2 # v2：局域网最多 4 人，输入按 slot 分发

const GAME_PORT := 42422 # ENet 游戏传输端口
const BEACON_PORT := 42420 # 主机发现端口（监听探测、发送信标）
const SCAN_PORT := 42421 # 客户端发现端口（接收信标/探测回复）

const MAX_PLAYERS := 4 # 1 主机 + 最多 3 客户端
const SNAPSHOT_HZ := 20.0 # 世界快照下发频率
const INPUT_HZ := 30.0 # 客户端输入上送频率

const BEACON_INTERVAL := 1.0
const ROOM_TTL := 3.5

const HEARTBEAT_INTERVAL := 2.0
const HEARTBEAT_TIMEOUT := 6.0
const RECONNECT_GRACE := 30.0
const RECONNECT_TRIES := 5
const RECONNECT_DELAY := 1.0
const INPUT_MUTE_TIMEOUT := 5.0
const INPUT_DROP_TIMEOUT := 15.0

## 与 LocalCoop 的 P2 逻辑动作一一对应；客户端按这套表采样上送
const ACTIONS := [
	"move_left", "move_right", "jump", "dash", "attack", "skill",
	"skill_sweep", "skill_ult", "skill_i", "skill_o", "skill_p",
]

const CH_CONTROL := 0
const CH_INPUT := 1
const CH_SNAPSHOT := 2
