extends Node
## M2 全局单例：跨场景保留的"世界状态"记录（已解锁能力 / 已拾取物）。
## 能力运行时状态以玩家 PlayerAbilities 节点为准，这里只做持久记录与恢复来源；
## M4 接入 SaveManager 时，只需让本节点从存档读写这些记录，调用方接口不变。

var _ability_records: Dictionary = {}
var _pickup_records: Dictionary = {}


## 记录一项已解锁能力（幂等）
func record_ability(id: StringName) -> void:
	_ability_records[id] = true


## 清除能力记录（调试撤销时同步）
func erase_ability(id: StringName) -> void:
	_ability_records.erase(id)


func is_ability_recorded(id: StringName) -> bool:
	return _ability_records.has(id)


func get_recorded_abilities() -> Array:
	return _ability_records.keys()


## 记录一个已拾取物（幂等）
func record_pickup(uid: StringName) -> void:
	_pickup_records[uid] = true


func is_pickup_collected(uid: StringName) -> bool:
	return _pickup_records.has(uid)


## 清空所有记录（新游戏 / 调试用；M4 接入存档后配合读档调用）
func reset_records() -> void:
	_ability_records.clear()
	_pickup_records.clear()
