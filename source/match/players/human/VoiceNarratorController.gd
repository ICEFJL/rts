extends Node

# 在节点准备好后找到子节点 "AudioStreamPlayer"
@onready var _player = find_child("AudioStreamPlayer")


# 初始化函数
func _ready():
	# 连接比赛开始信号
	MatchSignals.match_started.connect(
		_handle_event.bind(Constants.Match.VoiceNarrator.Events.MATCH_STARTED)
	)
	# 连接比赛中止信号
	MatchSignals.match_aborted.connect(
		_handle_event.bind(Constants.Match.VoiceNarrator.Events.MATCH_ABORTED)
	)
	# 连接单位死亡信号
	MatchSignals.unit_died.connect(_on_unit_died)
	# 连接单位生产开始信号
	MatchSignals.unit_production_started.connect(_on_production_started)
	# 连接资源不足生产信号
	MatchSignals.not_enough_resources_for_production.connect(
		_on_not_enough_resources_for_production
	)


# 处理事件并播放对应的声音
func _handle_event(event):
	# 根据事件类型选择对应的声音资源
	_player.stream = Constants.Match.VoiceNarrator.EVENT_TO_ASSET_MAPPING[event]
	# 播放声音
	_player.play()


# 处理单位死亡事件
func _on_unit_died(unit):
	# 如果死亡的单位属于控制组
	if unit.is_in_group("controlled_units"):
		# 触发单位丢失事件
		_handle_event(Constants.Match.VoiceNarrator.Events.UNIT_LOST)


# 处理单位生产开始事件
func _on_production_started(_unit_prototype, producer_unit):
	# 如果生产的单位属于控制组
	if producer_unit.is_in_group("controlled_units"):
		# 触发单位生产开始事件
		_handle_event(Constants.Match.VoiceNarrator.Events.UNIT_PRODUCTION_STARTED)


# 处理资源不足生产事件
func _on_not_enough_resources_for_production(player):
	# 如果资源不足的玩家是当前玩家
	if player == get_parent():
		# 触发资源不足事件
		_handle_event(Constants.Match.VoiceNarrator.Events.NOT_ENOUGH_RESOURCES)
