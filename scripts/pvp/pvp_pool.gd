extends RefCounted

## 对战选角池：所有入口都只读「本机」Meta 的解锁状态。
## - 本机同屏：P1/P2 共用这一个池子。
## - 局域网：主机与客机各自在自己的进程里调用，因此天然各用各的解锁池。

const Skulls = preload("res://scripts/player/skulls.gd")


## 当前本机已解锁的化身 id（保持 Skulls.ids() 的原顺序）
static func unlocked_ids() -> Array:
	var out: Array = []
	for id in Skulls.ids():
		if Meta.is_unlocked(str(id)):
			out.append(str(id))
	return out


## 是否允许选中：id 必须存在且在本机已解锁
static func can_pick(id: String) -> bool:
	return Skulls.SKULLS.has(id) and Meta.is_unlocked(id)


## 没有显式选择时的默认化身：优先取本机第一个已解锁角色
static func default_id() -> String:
	var list := unlocked_ids()
	if not list.is_empty():
		return str(list[0])
	return Skulls.DEFAULT_ID
