# 继承自Node类
extends Node

# 定义无人机切换目标的时间范围
const TARGET_SWITICHING_TIME_MIN_S = 0.5
const TARGET_SWITICHING_TIME_MAX_S = 1.0


# 定义动作类
class Actions:
	const MovingToUnit = preload("res://source/match/units/actions/MovingToUnit.gd")


# 预加载无人机资源
const Drone = preload("res://source/match/units/Drone.gd")

# 变量定义
var _player = null  # 当前玩家
var _blacklisted_drone_target_paths = {}  # 被黑名单化的无人机目标路径


# 初始化方法，设置玩家并连接信号
func setup(player):
	_player = player
	await get_tree().create_timer(0.1).timeout
	_attach_current_drones()
	_initialize_movement_of_current_drones()


# 添加当前所有的无人机
func _attach_current_drones():
	for drone in _get_current_drones():
		_attach_drone(drone)


# 初始化当前所有无人机的移动
func _initialize_movement_of_current_drones():
	for drone in _get_current_drones():
		_navigate_to_random_unit(drone)


# 获取当前所有的无人机
func _get_current_drones():
	return get_tree().get_nodes_in_group("units").filter(
		func(unit): return unit is Drone and unit.player == _player
	)


# 添加无人机并连接信号
func _attach_drone(drone):
	drone.action_changed.connect(_on_drone_action_changed.bind(drone))


# 使无人机导航到随机单位
func _navigate_to_random_unit(drone):
	var players_in_random_order = get_tree().get_nodes_in_group("players").filter(
		func(player): return player != _player
	)
	players_in_random_order.shuffle()
	var random_player_to_visit = players_in_random_order.front()
	var random_player_units_in_random_order = get_tree().get_nodes_in_group("units").filter(
		func(unit): return unit.player == random_player_to_visit
	)
	var blacklisted_drone_target_path = _blacklisted_drone_target_paths.get(drone, NodePath())
	random_player_units_in_random_order = random_player_units_in_random_order.filter(
		func(unit): return unit.get_path() != blacklisted_drone_target_path
	)
	random_player_units_in_random_order.shuffle()
	if not random_player_units_in_random_order.is_empty():
		var target_unit = random_player_units_in_random_order.front()
		_blacklisted_drone_target_paths[drone] = target_unit.get_path()
		drone.action = Actions.MovingToUnit.new(target_unit)
	else:
		var units_in_random_order = get_tree().get_nodes_in_group("units").filter(
			func(unit): return unit.player != _player
		)
		units_in_random_order.shuffle()
		units_in_random_order = units_in_random_order.filter(
			func(unit): return unit.get_path() != blacklisted_drone_target_path
		)
		if not units_in_random_order.is_empty():
			var target_unit = units_in_random_order.front()
			_blacklisted_drone_target_paths[drone] = target_unit.get_path()
			drone.action = Actions.MovingToUnit.new(target_unit)


# 当无人机行动改变时的处理
func _on_drone_action_changed(new_action, drone):
	if new_action == null:
		await (
			get_tree()
			. create_timer(randf_range(TARGET_SWITICHING_TIME_MIN_S, TARGET_SWITICHING_TIME_MAX_S))
			. timeout
		)
		var drone_was_freed = not is_instance_valid(drone)
		if drone_was_freed:
			return
		_navigate_to_random_unit(drone)
