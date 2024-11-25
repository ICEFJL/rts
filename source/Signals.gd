extends Node

# 定义信号用于通知god模式的启用和禁用
# 当god模式启用时，god_mode_enabled信号会被触发
# 当god模式禁用时，god_mode_disabled信号会被触发
signal god_mode_enabled
signal god_mode_disabled
