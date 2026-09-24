class_name PlayerAbilities
extends Node
## M2 能力系统：维护玩家运行时能力标志，广播解锁信号，并同步记录到 GameManager。
## 接口按路线图预留：unlock_ability(id) / has_ability(id) / ability_unlocked(id)；
## 后续升级为 Resource 定义（每个能力一个 .tres）时保持这三个接口不变即可平滑迁移。

## 能力解锁时广播（HUD / 存档监听；场景重入恢复时也会触发）
signal ability_unlocked(id: StringName)
## 能力被撤销时广播（仅调试切换使用）
signal ability_revoked(id: StringName)

## 二段跳能力 id
const DOUBLE_JUMP := &"double_jump"

var _unlocked: Dictionary = {}


func _ready() -> void:
	# 新的场景实例创建时，从 GameManager 记录恢复已解锁能力（跨场景保持）
	for id in GameManager.get_recorded_abilities():
		unlock_ability(id)


## 解锁能力；返回本次是否发生了变化（false = 之前已解锁）
func unlock_ability(id: StringName) -> bool:
	if _unlocked.has(id):
		return false
	_unlocked[id] = true
	GameManager.record_ability(id)
	ability_unlocked.emit(id)
	return true


## 撤销能力（调试对比用；同时清除全局记录，避免重进场景后又"复活"）
func revoke_ability(id: StringName) -> void:
	if not _unlocked.erase(id):
		return
	GameManager.erase_ability(id)
	ability_revoked.emit(id)


## 切换能力的解锁状态；返回切换后的状态（调试快捷键 F1 使用）
func toggle_ability(id: StringName) -> bool:
	if has_ability(id):
		revoke_ability(id)
		return false
	unlock_ability(id)
	return true


func has_ability(id: StringName) -> bool:
	return _unlocked.has(id)
