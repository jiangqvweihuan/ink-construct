extends Node2D

## 小怪命中范围专项验证：玩家在不同距离，直接触发 _deal_hit，看是否掉血

var _log: FileAccess

func p(msg: String) -> void:
	print("[H] ", msg)
	if _log:
		_log.store_line("[H] " + msg)
		_log.flush()

func _ready() -> void:
	_log = FileAccess.open("res://tests/hit_range_test.log", FileAccess.WRITE)
	get_window().size = Vector2i(1280, 720)

	var ground := StaticBody2D.new()
	ground.position = Vector2(640, 660)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(1280, 80)
	shape.shape = rect
	ground.add_child(shape)
	add_child(ground)

	var player = load("res://scenes/player/player.tscn").instantiate()
	player.position = Vector2(560, 560)
	add_child(player)
	var enemy = load("res://scenes/enemies/c016.tscn").instantiate()
	enemy.position = Vector2(640, 560)
	add_child(enemy)
	await get_tree().physics_frame
	await get_tree().physics_frame

	enemy._target = player
	# 冻结双方 AI/物理：探针只验判定数学——别让敌人自主追击/前冲把 _current_anim 换成
	# 真实招式（多段命中后每招射程不同），也别让重力/击退污染传送后的距离
	enemy.set_physics_process(false)
	player.set_physics_process(false)
	var base: Vector2 = enemy.global_position
	# 逐个距离直接触发一次判定，检查玩家 hp
	# 受击规则 = 射程 + 目标 body_radius：c016 站立兜底射程 180 + 玩家 30 = 210 边界，距离按包住它来选
	for d in [100.0, 180.0, 205.0, 215.0, 300.0]:
		player.global_position = base + Vector2(d, 0)
		player.state = 0 # 清掉受击/冲刺等免伤状态
		player._hurt_invincible = 0.0 # 清受击无敌：每个距离独立判定，否则首刀之后全被无敌吞掉
		var before: int = player.hp
		enemy.facing = 1
		enemy._deal_hit()
		await get_tree().physics_frame
		var after: int = player.hp
		p("dist=%d -> hp %d->%d  %s" % [int(d), before, after, "HIT" if after < before else "MISS"])

	# 纵向容差
	for dy in [80.0, 95.0]:
		player.global_position = base + Vector2(120.0, -dy)
		player.state = 0
		player._hurt_invincible = 0.0
		player.velocity = Vector2.ZERO # 清下落速度，别让重力把 dy 拖过 hit_height
		await get_tree().physics_frame # 传送后等一帧再量，dy 才是真实值
		var b2: int = player.hp
		p("dy 设定=%d 实际dx=%.1f 实际dy=%.1f" % [int(dy),
			player.global_position.x - enemy.global_position.x,
			absf(player.global_position.y - enemy.global_position.y)])
		enemy._deal_hit()
		await get_tree().physics_frame
		p("dist=120 dy=%d -> %s" % [int(dy), "HIT" if player.hp < b2 else "MISS"])

	# attack_hit_range 字段已随多段命中改造移除，这里打印当前生效边界
	p("params: attack_range=%.0f hit_height=%.0f 生效边界=%.0f（射程+玩家 body_radius）" % [
		enemy.attack_range, enemy.attack_hit_height, enemy.attack_range + player.body_radius])
	p("ALL DONE")
	get_tree().quit()
