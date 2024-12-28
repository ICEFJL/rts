extends CanvasLayer

const Human = preload("res://source/match/players/human/Human.gd")

@onready var _victory_tile = find_child("Victory")
@onready var _defeat_tile = find_child("Defeat")
@onready var _finish_tile = find_child("Finish")
@onready var _report_tile = find_child("Report")


func _ready():
	if not FeatureFlags.handle_match_end:
		queue_free()
		return
	hide()
	_victory_tile.hide()
	_defeat_tile.hide()
	_finish_tile.hide()
	_report_tile.hide()
	await find_parent("Match").ready
	MatchSignals.setup_and_spawn_unit.connect(_on_new_unit)
	for unit in get_tree().get_nodes_in_group("units"):
		unit.tree_exited.connect(_on_unit_tree_exited)


func _show():
	show()
	get_tree().paused = true


func _on_new_unit(unit, _transform, _player):
	unit.tree_exited.connect(_on_unit_tree_exited)


func _on_unit_tree_exited():
	if visible or not is_inside_tree():
		return
	var players = Utils.Set.new()
	for unit in get_tree().get_nodes_in_group("units"):
		players.add(unit.player)
	var human_players = get_tree().get_nodes_in_group("players").filter(
		func(player): return player is Human
	)
	if not human_players.is_empty() and not players.has(human_players[0]):
		_defeat_tile.show()
		_show_report(human_players[0])
		_show()
	elif not human_players.is_empty() and players.has(human_players[0]) and players.size() == 1:
		_victory_tile.show()
		_show_report(human_players[0])
		_show()
	elif players.size() == 1:
		_finish_tile.show()
		_show_report(players.get_any())
		_show()


# 将时间戳格式化为可读的时间字符串
func _format_time(current_datetime: Dictionary) -> String:
	# 提取年、月、日、时、分、秒
	var year = current_datetime["year"]
	var month = current_datetime["month"]
	var day = current_datetime["day"]
	var hour = current_datetime["hour"]
	var minute = current_datetime["minute"]
	var second = current_datetime["second"]

	# 格式化为字符串并返回
	return "%04d-%02d-%02d %02d:%02d:%02d" % [year, month, day, hour, minute, second]


# 将时间差（秒）格式化为可读的字符串
func _format_time_diff(time_diff: float) -> String:
	var hours = int(time_diff / 3600)  # 转换为整数
	var minutes = int((int(time_diff) % 3600) / 60)  # 将 time_diff 转换为整数后再取模
	var seconds = int(int(time_diff) % 60)  # 转换为整数
	return "%02d 小时 %02d 分钟 %02d 秒" % [hours, minutes, seconds]


func _show_report(player):
	var match = find_parent("Match")
	var end_time = Time.get_unix_time_from_system()
	var duration = abs(end_time - match.start_time_unix)
	var formatted_duration = _format_time_diff(duration)

	var report_text = "战报:\n"
	report_text += "战斗开始时间: %s\n" % _format_time(match.start_time)
	report_text += "战斗时长: %s\n" % formatted_duration
	report_text += "玩家资源A: %d\n" % player.resource_a
	report_text += "玩家资源B: %d\n" % player.resource_b
	report_text += "创建的单位数量: %d\n" % player.units_created
	report_text += "被摧毁的单位数量: %d\n" % player.units_destroyed
	_report_tile.text = report_text
	_report_tile.show()


func _on_exit_button_pressed():
	get_tree().paused = false
	get_tree().change_scene_to_file("res://source/main-menu/Main.tscn")
