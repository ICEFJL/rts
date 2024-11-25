# 继承自 Node 类
extends Node

# 预加载结构体、工人和建造动作的脚本
const Structure = preload("res://source/match/units/Structure.gd")
const Worker = preload("res://source/match/units/Worker.gd")
const Constructing = preload("res://source/match/units/actions/Constructing.gd")

# 刷新间隔时间（秒）
const REFRESH_INTERVAL_S = 1.0 / 60.0 * 30.0

# 当前玩家
var _player = null


# 初始化控制器，设置玩家
func setup(player):
	_player = player
	_setup_refresh_timer()


# 设置刷新定时器
func _setup_refresh_timer():
	var timer = Timer.new()
	add_child(timer)
	timer.timeout.connect(_on_refresh_timer_timeout)
	timer.start(REFRESH_INTERVAL_S)


# 定时器超时处理函数
func _on_refresh_timer_timeout():
	# 获取当前玩家的所有工人
	var workers = get_tree().get_nodes_in_group("units").filter(
		func(unit): return unit is Worker and unit.player == _player
	)
	# 如果有工人正在执行建造动作，则返回
	if workers.any(func(worker): return worker.action != null and worker.action is Constructing):
		return

	# 获取当前玩家需要建造的结构体
	var structures_to_construct = get_tree().get_nodes_in_group("units").filter(
		func(unit):
			return unit is Structure and not unit.is_constructed() and unit.player == _player
	)

	# 如果有未建造的结构体且有可用的工人
	if not structures_to_construct.is_empty() and not workers.is_empty():
		# TODO: 引入基于距离的算法来优化分配
		workers.shuffle()
		structures_to_construct.shuffle()
		# 分配第一个工人去建造第一个结构体
		workers[0].action = Constructing.new(structures_to_construct[0])
