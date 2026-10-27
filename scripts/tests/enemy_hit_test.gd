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
	var base: Vector2 = enemy.global_position
	# 逐个距离直接触发一次判定，检查玩家 hp
	for d in [100.0, 180.0, 235.0, 245.0, 300.0]:
		player.global_position = base + Vector2(d, 0)
		player.state = 0 # 清掉受击/冲刺等免伤状态
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
		var b2: int = player.hp
		p("dy 设定=%d 实际dx=%.1f 实际dy=%.1f" % [int(dy),
			player.global_position.x - enemy.global_position.x,
			absf(player.global_position.y - enemy.global_position.y)])
		enemy._deal_hit()
		await get_tree().physics_frame
		p("dist=120 dy=%d -> %s" % [int(dy), "HIT" if player.hp < b2 else "MISS"])

	p("params: attack_range=%.0f hit_range=%.0f hit_height=%.0f" % [enemy.attack_range, enemy.attack_hit_range, enemy.attack_hit_height])
	p("ALL DONE")
	get_tree().quit()
