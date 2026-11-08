extends RefCounted

## 局域网自动发现：主机在 BEACON_PORT 监听探测并周期广播信标；
## 客户端在 SCAN_PORT 监听信标，同时主动向广播地址与回环地址发探测。
## 广播被系统/防火墙拦截时，主机仍会单播回复探测，因此同网段依旧可发现。

const Cfg = preload("res://scripts/net/net_config.gd")
const Proto = preload("res://scripts/net/net_protocol.gd")

var error := ""

var _udp: PacketPeerUDP = null
var _hosting := false
var _scanning := false
var _beacon_cb := Callable()
var _rooms := {}
var _acc := 0.0


## 主机：绑定发现端口，回调需返回当前房间信息字典
func start_host(info_provider: Callable) -> bool:
	stop()
	_udp = PacketPeerUDP.new()
	_udp.set_broadcast_enabled(true)
	var err := _udp.bind(Cfg.BEACON_PORT)
	if err != OK:
		error = "发现端口 %d 被占用（%s）" % [Cfg.BEACON_PORT, error_string(err)]
		_udp = null
		return false
	_hosting = true
	_beacon_cb = info_provider
	_acc = Cfg.BEACON_INTERVAL # 立即广播一次，别让客户端等一秒
	return true


## 客户端：绑定扫描端口。端口占用时退回随机端口（仍可收到探测的定向回复）
func start_scan() -> bool:
	stop()
	_udp = PacketPeerUDP.new()
	_udp.set_broadcast_enabled(true)
	var err := _udp.bind(Cfg.SCAN_PORT)
	if err != OK:
		err = _udp.bind(0)
	if err != OK:
		error = "扫描端口绑定失败（%s）" % error_string(err)
		_udp = null
		return false
	_scanning = true
	_acc = Cfg.BEACON_INTERVAL # 立即探测一次
	return true


func stop() -> void:
	if _udp != null:
		_udp.close()
	_udp = null
	_hosting = false
	_scanning = false
	_beacon_cb = Callable()
	_rooms.clear()
	_acc = 0.0


func is_active() -> bool:
	return _udp != null


## 每帧驱动：收包 + 按间隔广播/探测
func poll(delta: float) -> void:
	if _udp == null:
		return
	_read()
	_acc += delta
	if _acc < Cfg.BEACON_INTERVAL:
		return
	_acc = 0.0
	if _hosting:
		_broadcast()
	elif _scanning:
		_probe()


## 当前可加入房间（按人数降序，过期条目自动剔除）
func rooms() -> Array:
	var now := _now()
	var out: Array = []
	for key in _rooms.keys():
		var r: Dictionary = _rooms[key]
		if now - int(r.get("seen", 0)) > int(Cfg.ROOM_TTL * 1000.0):
			_rooms.erase(key)
			continue
		out.append(r)
	out.sort_custom(func(a, b): return int(a.get("players", 0)) > int(b.get("players", 0)))
	return out


## 指定端口最近一次收包是否来自本机（测试与同机双开时区分房间用）
func _read() -> void:
	while _udp.get_available_packet_count() > 0:
		var data := _udp.get_packet()
		var ip := _udp.get_packet_ip()
		var port := _udp.get_packet_port()
		if data.is_empty() or data.size() > 2048:
			continue
		var msg = JSON.parse_string(data.get_string_from_utf8())
		if typeof(msg) != TYPE_DICTIONARY:
			continue
		var kind := str((msg as Dictionary).get("kind", ""))
		if _hosting:
			if kind == "probe" and _beacon_cb.is_valid():
				var info: Dictionary = _beacon_cb.call()
				info["kind"] = "beacon"
				_send_to(info, ip, port)
		elif kind == "beacon":
			var parsed := Proto.parse_beacon(msg)
			if parsed.is_empty():
				continue
			parsed["ip"] = ip
			parsed["seen"] = _now()
			_rooms["%s:%d" % [ip, int(parsed["port"])]] = parsed


func _broadcast() -> void:
	if not _beacon_cb.is_valid():
		return
	var info: Dictionary = _beacon_cb.call()
	info["kind"] = "beacon"
	_send_raw(JSON.stringify(info).to_utf8_buffer(), "255.255.255.255", Cfg.SCAN_PORT)


func _probe() -> void:
	var msg := {"app": Cfg.APP_ID, "v": Cfg.PROTO_VERSION, "kind": "probe"}
	var bytes := JSON.stringify(msg).to_utf8_buffer()
	_send_raw(bytes, "255.255.255.255", Cfg.BEACON_PORT)
	_send_raw(bytes, "127.0.0.1", Cfg.BEACON_PORT) # 同机双开/回环测试的兜底


func _send_to(info: Dictionary, ip: String, port: int) -> void:
	_send_raw(JSON.stringify(info).to_utf8_buffer(), ip, port)


func _send_raw(bytes: PackedByteArray, ip: String, port: int) -> void:
	if _udp == null:
		return
	_udp.set_dest_address(ip, port)
	_udp.put_packet(bytes)


func _now() -> int:
	return Time.get_ticks_msec()
