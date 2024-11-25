# 继承自Node类
extends Node

# 当资源需求发生变化时发出信号
signal resources_required(resources, metadata)

# 预加载各种资源和场景
const CommandCenter = preload("res://source/match/units/CommandCenter.gd")
const CommandCenterScene = preload("res://source/match/units/CommandCenter.tscn")
const Worker = preload("res://source/match/units/Worker.gd")
const WorkerScene = preload("res://source/match/units/Worker.tscn")
const CollectingResourcesSequentially = preload(
	"res://source/match/units/actions/CollectingResourcesSequentially.gd"
)

# 变量定义
var _player = null  # 当前玩家
var _ccs = []  # 命令中心列表
var _workers = []  # 工人列表
var _number_of_pending_cc_resource_requests = 0  # 待处理的命令中心资源请求数量
var _number_of_pending_worker_resource_requests = 0  # 待处理的工人资源请求数量
var _number_of_pending_workers = 0  # 待处理的工人数量
var _cc_base_position = null  # 命令中心的基础位置

# 在初始化时获取父节点AI
@onready var _ai = get_parent()


# 初始化方法，设置玩家并连接信号
func setup(player):
	_player = player
	_attach_current_ccs()
	_attach_current_workers()
	MatchSignals.unit_spawned.connect(_on_unit_spawned)
	_enforce_number_of_ccs()
	_enforce_number_of_workers()


# 处理资源供应
func provision(resources, metadata):
	if metadata == "worker":
		assert(
			resources == Constants.Match.Units.PRODUCTION_COSTS[WorkerScene.resource_path],
			"unexpected amount of resources"
		)
		_number_of_pending_worker_resource_requests -= 1
		if _ccs.is_empty():
			return
		if _ccs[0].production_queue.produce(WorkerScene, true) != null:
			_number_of_pending_workers += 1
	elif metadata == "cc":
		assert(
			resources == Constants.Match.Units.CONSTRUCTION_COSTS[CommandCenterScene.resource_path],
			"unexpected amount of resources"
		)
		_number_of_pending_cc_resource_requests -= 1
		if _workers.is_empty():
			return
		_construct_cc()
	else:
		assert(false, "unexpected flow")


# 添加命令中心
func _attach_cc(cc):
	_ccs.append(cc)
	cc.tree_exited.connect(_on_cc_died.bind(cc))


# 添加当前所有的命令中心
func _attach_current_ccs():
	var ccs = get_tree().get_nodes_in_group("units").filter(
		func(unit): return unit is CommandCenter and unit.player == _player
	)
	if not ccs.is_empty():
		_cc_base_position = ccs[0].global_position
	for cc in ccs:
		_attach_cc(cc)


# 添加工人
func _attach_worker(worker):
	if worker in _workers:
		return
	_workers.append(worker)
	worker.tree_exited.connect(_on_worker_died.bind(worker))
	worker.action_changed.connect(_on_worker_action_changed.bind(worker))
	if worker.action != null:
		return
	_make_worker_collecting_resources(worker)


# 添加当前所有的工人
func _attach_current_workers():
	var workers = get_tree().get_nodes_in_group("units").filter(
		func(unit): return unit is Worker and unit.player == _player
	)
	for worker in workers:
		_attach_worker(worker)


# 确保命令中心的数量符合预期
func _enforce_number_of_ccs():
	if (
		_ccs.size() + _number_of_pending_cc_resource_requests + _number_of_pending_workers
		>= _ai.expected_number_of_ccs
	):
		return
	var number_of_extra_ccs_required = (
		_ai.expected_number_of_ccs
		- (_ccs.size() + _number_of_pending_cc_resource_requests + _number_of_pending_workers)
	)
	for _i in range(number_of_extra_ccs_required):
		resources_required.emit(
			Constants.Match.Units.CONSTRUCTION_COSTS[CommandCenterScene.resource_path], "cc"
		)
		_number_of_pending_cc_resource_requests += 1


# 确保工人的数量符合预期
func _enforce_number_of_workers():
	if (
		_workers.size() + _number_of_pending_worker_resource_requests
		>= _ai.expected_number_of_workers
	):
		return
	var number_of_extra_workers_required = (
		_ai.expected_number_of_workers
		- (_workers.size() + _number_of_pending_worker_resource_requests)
	)
	for _i in range(number_of_extra_workers_required):
		resources_required.emit(
			Constants.Match.Units.PRODUCTION_COSTS[WorkerScene.resource_path], "worker"
		)
		_number_of_pending_worker_resource_requests += 1


# 构建新的命令中心
func _construct_cc():
	var construction_cost = Constants.Match.Units.CONSTRUCTION_COSTS[
		CommandCenterScene.resource_path
	]
	assert(
		_player.has_resources(construction_cost),
		"player should have enough resources at this point"
	)
	var unit_to_spawn = CommandCenterScene.instantiate()
	var placement_position = Utils.Match.Unit.Placement.find_valid_position_radially(
		_cc_base_position if _cc_base_position != null else _workers[0].global_position,
		unit_to_spawn.radius + Constants.Match.Units.EMPTY_SPACE_RADIUS_SURROUNDING_STRUCTURE_M,
		find_parent("Match").navigation.get_navigation_map_rid_by_domain(
			unit_to_spawn.movement_domain
		),
		get_tree()
	)
	var target_transform = Transform3D(Basis(), placement_position).looking_at(
		placement_position + Vector3(0, 0, 1), Vector3.UP
	)
	_player.subtract_resources(construction_cost)
	MatchSignals.setup_and_spawn_unit.emit(unit_to_spawn, target_transform, _player)


# 计算资源收集统计信息
func _calculate_resource_collecting_statistics():
	var number_of_workers_per_resource_kind = {
		"resource_a": 0,
		"resource_b": 0,
	}
	for worker in _workers:
		if worker.action != null and worker.action is CollectingResourcesSequentially:
			var resource_unit = worker.action.get_resource_unit()
			if resource_unit == null:
				continue
			if "resource_a" in resource_unit:
				number_of_workers_per_resource_kind["resource_a"] += 1
			elif "resource_b" in resource_unit:
				number_of_workers_per_resource_kind["resource_b"] += 1
			else:
				assert(false, "unexpected flow")
	return number_of_workers_per_resource_kind


# 使工人开始收集资源
func _make_worker_collecting_resources(worker):
	var number_of_workers_per_resource_kind = _calculate_resource_collecting_statistics()
	var resource_filter = null
	if (
		number_of_workers_per_resource_kind["resource_a"] != 0
		or number_of_workers_per_resource_kind["resource_b"] != 0
	):
		if (
			number_of_workers_per_resource_kind["resource_a"]
			<= number_of_workers_per_resource_kind["resource_b"]
		):
			resource_filter = func(resource_unit): return "resource_a" in resource_unit
		else:
			resource_filter = func(resource_unit): return "resource_b" in resource_unit
	var closest_resource_unit = (
		Utils
		. Match
		. Resources
		. find_resource_unit_closest_to_unit_yet_no_further_than(
			worker, Constants.Match.Units.NEW_RESOURCE_SEARCH_RADIUS_M, resource_filter
		)
	)
	if closest_resource_unit != null:
		worker.action = CollectingResourcesSequentially.new(closest_resource_unit)


# 如果必要，重新分配工人
func _retarget_workers_if_necessary():
	var number_of_workers_per_resource_kind = _calculate_resource_collecting_statistics()
	if (
		abs(
			(
				number_of_workers_per_resource_kind["resource_a"]
				- number_of_workers_per_resource_kind["resource_b"]
			)
		)
		>= 2
	):
		for worker in _workers:
			_make_worker_collecting_resources(worker)


# 当命令中心死亡时的处理
func _on_cc_died(cc):
	if not is_inside_tree():
		return
	_ccs.erase(cc)
	_enforce_number_of_ccs()


# 当工人死亡时的处理
func _on_worker_died(worker):
	if not is_inside_tree():
		return
	_workers.erase(worker)
	_enforce_number_of_workers()
	_retarget_workers_if_necessary()


# 当单位生成时的处理
func _on_unit_spawned(unit):
	if unit.player != _player:
		return
	if unit is Worker:
		if _number_of_pending_workers > 0:
			_number_of_pending_workers -= 1
		_attach_worker(unit)
	elif unit is CommandCenter:
		_attach_cc(unit)


# 当工人行动改变时的处理
func _on_worker_action_changed(new_action, worker):
	if new_action != null:
		return
	_make_worker_collecting_resources(worker)
