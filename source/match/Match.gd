extends Node3D

const Unit = preload("res://source/match/units/Unit.gd")
const Structure = preload("res://source/match/units/Structure.gd")
const Player = preload("res://source/match/players/Player.gd")
const Human = preload("res://source/match/players/human/Human.gd")

const CommandCenter = preload("res://source/match/units/CommandCenter.tscn")
const DroneUnit = preload("res://source/match/units/Drone.tscn")
const WorkerUnit = preload("res://source/match/units/Worker.tscn")
const TankUnit = preload("res://source/match/units/Tank.tscn")
const HelicopterUnit = preload("res://source/match/units/Helicopter.tscn")

@export var settings: Resource = null

var map:
	set = _set_map,
	get = _get_map
var visible_player = null:
	set = _set_visible_player
var visible_players = null:
	set = _ignore,
	get = _get_visible_players
var start_time = null
var start_time_unix = null

@onready var navigation = $Navigation
@onready var fog_of_war = $FogOfWar

@onready var _camera = $IsometricCamera3D
@onready var _players = $Players
@onready var _terrain = $Terrain


func _enter_tree():
	assert(settings != null, "match cannot start without settings, see examples in tests/manual/")
	assert(map != null, "match cannot start without map, see examples in tests/manual/")


func _ready():
	MatchSignals.setup_and_spawn_unit.connect(_setup_and_spawn_unit)
	_setup_subsystems_dependent_on_map()
	_setup_players()
	_setup_player_units()
	visible_player = get_tree().get_nodes_in_group("players")[settings.visible_player]
	_move_camera_to_initial_position()
	if settings.visibility == settings.Visibility.FULL:
		fog_of_war.reveal()
	start_time = Time.get_datetime_dict_from_system()
	start_time_unix = Time.get_unix_time_from_system()

	# 创建 StyleBoxFlat 并设置底色和边框
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color("#2E3440")  # 背景颜色
	style_box.border_width_bottom = 2  # 底部边框宽度
	style_box.border_width_top = 2  # 顶部边框宽度
	style_box.border_width_left = 2  # 左侧边框宽度
	style_box.border_width_right = 2  # 右侧边框宽度
	style_box.border_color = Color("#4C566A")  # 边框颜色

	# 将 StyleBoxFlat 应用到按钮
	$HUD/MenuButton.add_theme_stylebox_override("normal", style_box)

	$HUD/MenuButton.pressed.connect(_on_menu_button_pressed)
	MatchSignals.match_started.emit()


func _on_menu_button_pressed():
	var menu = $Menu
	if menu:
		menu._toggle()


func _unhandled_input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if Input.is_action_pressed("shift_selecting"):
			return
		MatchSignals.deselect_all_units.emit()


func _set_map(a_map):
	assert(get_node_or_null("Map") == null, "map already set")
	a_map.name = "Map"
	add_child(a_map)
	a_map.owner = self


func _ignore(_value):
	pass


func _get_map():
	return get_node_or_null("Map")


func _set_visible_player(player):
	_conceal_player_units(visible_player)
	_reveal_player_units(player)
	visible_player = player


func _get_visible_players():
	if settings.visibility == settings.Visibility.PER_PLAYER:
		return [visible_player]
	return get_tree().get_nodes_in_group("players")


func _setup_subsystems_dependent_on_map():
	_terrain.update_shape(map.find_child("Terrain").mesh)
	fog_of_war.resize(map.size)
	_recalculate_camera_bounding_planes(map.size)
	navigation.setup(map)


func _recalculate_camera_bounding_planes(map_size: Vector2):
	_camera.bounding_planes[1] = Plane(-1, 0, 0, -map_size.x)
	_camera.bounding_planes[3] = Plane(0, 0, -1, -map_size.y)


func _setup_players():
	assert(
		_players.get_children().is_empty() or settings.players.is_empty(),
		"players can be defined either in settings or in scene tree, not in both"
	)
	if _players.get_children().is_empty():
		_create_players_from_settings()
	for node in _players.get_children():
		if node is Player:
			node.add_to_group("players")


func _create_players_from_settings():
	for player_settings in settings.players:
		var player_scene = Constants.Match.Player.CONTROLLER_SCENES[player_settings.controller]
		var player = player_scene.instantiate()
		player.color = player_settings.color
		if player_settings.spawn_index_offset > 0:
			for _i in range(player_settings.spawn_index_offset):
				_players.add_child(Node.new())
		_players.add_child(player)


func _setup_player_units():
	for player in _players.get_children():
		if not player is Player:
			continue
		var player_index = player.get_index()
		var predefined_units = player.get_children().filter(func(child): return child is Unit)
		if not predefined_units.is_empty():
			predefined_units.map(func(unit): _setup_unit_groups(unit, unit.player))
		else:
			_spawn_player_units(
				player, map.find_child("SpawnPoints").get_child(player_index).global_transform
			)


func _spawn_player_units(player, spawn_transform):
	var unit = CommandCenter.instantiate()
	_setup_and_spawn_unit(unit, spawn_transform, player, false)

	await get_tree().create_timer(0.1).timeout

	var drone_nums
	var worker_nums
	var helicopter_nums
	var tank_nums

	if player == _get_human_player():
		drone_nums = Globals.drone_nums
		worker_nums = Globals.worker_nums
		helicopter_nums = Globals.helicopter_nums
		tank_nums = Globals.tank_nums
	else:
		drone_nums = Globals.options.drone_nums
		worker_nums = Globals.options.worker_nums
		helicopter_nums = Globals.options.helicopter_nums
		tank_nums = Globals.options.tank_nums

	_spawn_units(player, unit, drone_nums, DroneUnit)
	_spawn_units(player, unit, worker_nums, WorkerUnit)
	_spawn_units(player, unit, helicopter_nums, HelicopterUnit)
	_spawn_units(player, unit, tank_nums, TankUnit)


func _spawn_units(player, unit, count, unit_prototype):
	for i in range(count):
		var produced_unit = unit_prototype.instantiate()
		var placement_position = (
			Utils
			. Match
			. Unit
			. Placement
			. find_valid_position_radially_yet_skip_starting_radius(
				unit.global_position,
				unit.radius,
				produced_unit.radius,
				0.1,
				Vector3(0, 0, 1),
				false,
				navigation.get_navigation_map_rid_by_domain(produced_unit.movement_domain),
				get_tree()
			)
		)
		MatchSignals.setup_and_spawn_unit.emit(
			produced_unit, Transform3D(Basis(), placement_position), player
		)


func _setup_and_spawn_unit(unit, a_transform, player, mark_structure_under_construction = true):
	unit.global_transform = a_transform
	if unit is Structure and mark_structure_under_construction:
		unit.mark_as_under_construction()
	_setup_unit_groups(unit, player)
	player.add_child(unit)
	MatchSignals.unit_spawned.emit(unit)


func _setup_unit_groups(unit, player):
	unit.add_to_group("units")
	if player == _get_human_player():
		unit.add_to_group("controlled_units")
	else:
		unit.add_to_group("adversary_units")
	if player in visible_players:
		unit.add_to_group("revealed_units")


func _get_human_player():
	var human_players = get_tree().get_nodes_in_group("players").filter(
		func(player): return player is Human
	)
	assert(human_players.size() <= 1, "more than one human player is not allowed")
	if not human_players.is_empty():
		return human_players[0]
	return null


func _move_camera_to_initial_position():
	var human_player = _get_human_player()
	if human_player != null:
		_move_camera_to_player_units_crowd_pivot(human_player)
	else:
		_move_camera_to_player_units_crowd_pivot(get_tree().get_nodes_in_group("players")[0])


func _move_camera_to_player_units_crowd_pivot(player):
	var player_units = get_tree().get_nodes_in_group("units").filter(
		func(unit): return unit.player == player
	)
	assert(not player_units.is_empty(), "player must have at least one initial unit")
	var crowd_pivot = Utils.Match.Unit.Movement.calculate_aabb_crowd_pivot_yless(player_units)
	_camera.set_position_safely(crowd_pivot)


func _reveal_player_units(player):
	if player == null:
		return
	for unit in get_tree().get_nodes_in_group("units").filter(
		func(a_unit): return a_unit.player == player
	):
		unit.add_to_group("revealed_units")


func _conceal_player_units(player):
	if player == null:
		return
	for unit in get_tree().get_nodes_in_group("units").filter(
		func(a_unit): return a_unit.player == player
	):
		unit.remove_from_group("revealed_units")
