extends RefCounted

## 联机封包：统一头部 + Variant payload + CRC32。
## 任何校验失败都返回空字典（调用方只做丢弃与计数），不抛异常、不信任对端数据。

const Cfg = preload("res://scripts/net/net_config.gd")

const MAGIC := 0x49 # 'I'
const HEADER := 9
const T_INPUT := 1
const T_SNAPSHOT := 2


## 组包：magic + type + version + seq + len + payload + crc32
static func pack(type: int, seq: int, payload: Dictionary) -> PackedByteArray:
	var body := var_to_bytes(payload)
	var head := PackedByteArray()
	head.resize(HEADER)
	head.encode_u8(0, MAGIC)
	head.encode_u8(1, type)
	head.encode_u8(2, Cfg.PROTO_VERSION)
	head.encode_u32(3, seq & 0xFFFFFFFF)
	head.encode_u16(7, body.size() & 0xFFFF)
	var buf := head.duplicate()
	buf.append_array(body)
	var tail := PackedByteArray()
	tail.resize(4)
	tail.encode_u32(0, crc32(buf))
	buf.append_array(tail)
	return buf


## 解包：校验失败返回 {}
static func unpack(buf: PackedByteArray) -> Dictionary:
	if buf.size() < HEADER + 4:
		return {}
	if buf.decode_u8(0) != MAGIC:
		return {}
	if buf.decode_u8(2) != Cfg.PROTO_VERSION:
		return {}
	var type := buf.decode_u8(1)
	var seq := int(buf.decode_u32(3))
	var plen := int(buf.decode_u16(7))
	if buf.size() != HEADER + plen + 4:
		return {}
	var want := int(buf.decode_u32(HEADER + plen))
	if want != crc32(buf.slice(0, HEADER + plen)):
		return {}
	var payload = bytes_to_var(buf.slice(HEADER, HEADER + plen))
	if typeof(payload) != TYPE_DICTIONARY:
		return {}
	var out: Dictionary = payload
	out["_type"] = type
	out["_seq"] = seq
	return out


## CRC32（IEEE 802.3），与联机无关的纯函数，单测直接调用
static func crc32(data: PackedByteArray) -> int:
	var crc := 0xFFFFFFFF
	for b in data:
		crc ^= int(b)
		for _i in 8:
			if crc & 1:
				crc = (crc >> 1) ^ 0xEDB88320
			else:
				crc >>= 1
	return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF


## 输入帧清洗：未知动作丢弃、重复去重、轴夹在 -1..1
static func sanitize_input(src: Dictionary) -> Dictionary:
	var held: Array = []
	var just: Array = []
	for a in src.get("held", []):
		var name := str(a)
		if Cfg.ACTIONS.has(name) and not held.has(name):
			held.append(name)
	for a in src.get("just", []):
		var name := str(a)
		if Cfg.ACTIONS.has(name) and not just.has(name):
			just.append(name)
	var axis := clampi(int(src.get("axis", 0)), -1, 1)
	return {"seq": int(src.get("seq", 0)), "axis": axis, "held": held, "just": just}


## 快照清洗：限制玩家/敌人条目数量与字段长度，防止异常包撑爆内存
static func sanitize_snapshot(src: Dictionary) -> Dictionary:
	var ps: Array = []
	for row in src.get("ps", []):
		if not (row is Array) or ps.size() >= Cfg.MAX_PLAYERS:
			continue
		ps.append(row)
	var es: Array = []
	for row in src.get("es", []):
		if not (row is Array) or es.size() >= 64:
			continue
		es.append(row)
	var run: Dictionary = src.get("run", {}) if src.get("run", {}) is Dictionary else {}
	return {"seq": int(src.get("seq", 0)), "ps": ps, "es": es, "run": run}


## 信标/房间信息解析：字段缺失时给安全默认值
static func parse_beacon(msg: Dictionary) -> Dictionary:
	if str(msg.get("app", "")) != Cfg.APP_ID:
		return {}
	if int(msg.get("v", 0)) != Cfg.PROTO_VERSION:
		return {}
	return {
		"name": str(msg.get("name", "未命名房间")).substr(0, 24),
		"port": clampi(int(msg.get("port", Cfg.GAME_PORT)), 1, 65535),
		"players": maxi(0, int(msg.get("players", 0))),
		"max": clampi(int(msg.get("max", Cfg.MAX_PLAYERS)), 1, 8),
		"mode": str(msg.get("mode", Run.MODE_ADVENTURE)),
		"difficulty": clampi(int(msg.get("difficulty", 1)), 0, 4),
		"state": str(msg.get("state", "lobby")),
		"skull": str(msg.get("skull", "")),
	}
