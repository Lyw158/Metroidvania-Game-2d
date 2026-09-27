extends Node
## M3 房间切换管理器（autoload）：
## - change_room()：淡出 → 切换场景 → 淡入，并把目标出生点传给下一个房间（由 Room 基类消费）。
## - 过渡期间 is_transitioning() 为 true，RoomDoor 会忽略触发，避免连续切换。
## 过渡 UI：内建 CanvasLayer + 全屏 ColorRect（初始透明），Tween 驱动淡入淡出。

## 淡出/淡入时长（秒）
const FADE_OUT_TIME := 0.25
const FADE_IN_TIME := 0.3

var _fade_rect: ColorRect
var _pending_spawn: StringName = &""
var _transitioning := false


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade_rect)


func is_transitioning() -> bool:
	return _transitioning


## 切换到目标房间，并让玩家在目标房间的指定出生点出现（spawn_name 为空则用房间的 default_spawn）
func change_room(room_path: String, spawn_name: StringName) -> void:
	if _transitioning or room_path.is_empty():
		return
	_transitioning = true
	_pending_spawn = spawn_name
	await _fade_to(1.0, FADE_OUT_TIME)
	var err := get_tree().change_scene_to_file(room_path)
	if err != OK:
		push_error("RoomManager: failed to change scene to '%s' (err %d)" % [room_path, err])
		_pending_spawn = &""
		await _fade_to(0.0, FADE_IN_TIME)
		_transitioning = false
		return
	# 等待新场景完成切换与 _ready（出生点定位由 Room 基类在 _ready 中处理）
	await get_tree().process_frame
	await get_tree().process_frame
	await _fade_to(0.0, FADE_IN_TIME)
	_transitioning = false


## 取走待用的出生点名（Room 基类在 _ready 调用；空字符串代表无指定）
func consume_pending_spawn() -> StringName:
	var spawn := _pending_spawn
	_pending_spawn = &""
	return spawn


func _fade_to(alpha: float, duration: float) -> void:
	var tween := create_tween()
	tween.tween_property(_fade_rect, "color:a", alpha, duration)
	await tween.finished
