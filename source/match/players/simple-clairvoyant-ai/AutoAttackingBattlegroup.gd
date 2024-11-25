# TODO: 监控附加的单位并根据需要修复它们的动作
extends Node

# 定义状态枚举，表示战斗群的状态
enum State { FORMING, ATTACKING }

# 切换攻击目标玩家的延迟时间（秒）
const PLAYER_TO_ATTACK_SWITCHING_DELAY_S = 0.5


# 定义动作类，预加载相关脚本
class Actions:
	const MovingToUnit = preload("res://source/match/units/actions/MovingToUnit.gd")
	const AutoAttacking = preload("res://source/match/units/actions/AutoAttacking.gd")


# 预期的单位数量
var _expected_number_of_units = null

# 需要攻击的玩家列表
var _players_to_attack = null

# 当前攻击的目标玩家
var _player_to_attack = null

# 当前状态
var _state = State.FORMING

# 附加的单位列表
var _attached_units = []


# 构造函数，初始化预期的单位数量和需要攻击的玩家列表
func _init(expected_number_of_units, players_to_attack):
	_expected_number_of_units = expected_number_of_units
	_players_to_attack = players_to_attack
	_player_to_attack = _players_to_attack.front()


# 返回当前附加单位的数量
func size():
	return _attached_units.size()


# 附加一个单位到战斗群
func attach_unit(unit):
	assert(_state == State.FORMING, "意外的状态")
	_attached_units.append(unit)
	unit.tree_exited.connect(_on_unit_died.bind(unit))
	if size() == _expected_number_of_units:
		_start_attacking()


# 开始攻击
func _start_attacking():
	_state = State.ATTACKING
	_attack_next_adversary_unit()


# 攻击下一个敌方单位
func _attack_next_adversary_unit():
	# 获取所有敌方单位
	var adversary_units = get_tree().get_nodes_in_group("units").filter(
		func(unit): return unit.player == _player_to_attack
	)
	if adversary_units.is_empty():
		_attack_next_player()
		return

	# 获取战斗群的位置
	var battlegroup_position = _attached_units[0].global_position

	# 按距离排序敌方单位
	var adversary_units_sorted_by_distance = adversary_units.map(
		func(adversary_unit):
			return {
				"distance":
				(adversary_unit.global_position * Vector3(1, 0, 1)).distance_to(
					battlegroup_position
				),
				"unit": adversary_unit
			}
	)
	adversary_units_sorted_by_distance.sort_custom(
		func(tuple_a, tuple_b): return tuple_a["distance"] < tuple_b["distance"]
	)

	# 为每个敌方单位分配攻击或移动动作
	for tuple in adversary_units_sorted_by_distance:
		var target_unit = tuple["unit"]
		if _attached_units.any(
			func(attached_unit):
				return Actions.AutoAttacking.is_applicable(attached_unit, target_unit)
		):
			target_unit.tree_exited.connect(_on_target_unit_died)
			for attached_unit in _attached_units:
				if Actions.AutoAttacking.is_applicable(attached_unit, target_unit):
					attached_unit.action = Actions.AutoAttacking.new(target_unit)
				else:
					attached_unit.action = Actions.MovingToUnit.new(target_unit)
			return

	# 如果无法攻击剩余的单位，则切换到下一个目标玩家
	_attack_next_player()


# 切换到下一个目标玩家
func _attack_next_player():
	var player_to_attack_index = _players_to_attack.find(_player_to_attack)
	var next_player_to_attack_index = (player_to_attack_index + 1) % _players_to_attack.size()
	_player_to_attack = _players_to_attack[next_player_to_attack_index]
	get_tree().create_timer(PLAYER_TO_ATTACK_SWITCHING_DELAY_S).timeout.connect(
		_attack_next_adversary_unit
	)


# 处理单位死亡事件
func _on_unit_died(unit):
	if not is_inside_tree():
		return
	_attached_units.erase(unit)
	if _state == State.ATTACKING and _attached_units.is_empty():
		queue_free()


# 处理目标单位死亡事件
func _on_target_unit_died():
	if not is_inside_tree():
		return
	_attack_next_adversary_unit()
