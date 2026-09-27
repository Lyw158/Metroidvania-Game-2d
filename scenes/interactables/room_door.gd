class_name RoomDoor
extends Area2D
## M3 房间门：玩家进入区域即触发房间切换（过渡由 RoomManager 负责）。
## 视觉为半透明门框 + 指示箭头（脚本绘制，零素材）；door_size 同时驱动碰撞区与视觉。

## 目标房间场景路径（res://...）
@export var target_room_path := ""
## 目标房间中的出生点名（对应目标房间 SpawnPoints 下的 Marker2D）
@export var target_spawn: StringName = &"Default"
## 门区域尺寸（宽×高）
@export var door_size := Vector2(120.0, 300.0)
## 指示箭头方向；设为 Vector2.ZERO 则不画箭头
@export var arrow_direction := Vector2.RIGHT

var _triggered := false


func _ready() -> void:
	var rect := RectangleShape2D.new()
	rect.size = door_size
	$CollisionShape2D.shape = rect
	body_entered.connect(_on_body_entered)
	if target_room_path.is_empty():
		push_warning("RoomDoor '%s': target_room_path 未配置" % name)


func _draw() -> void:
	var rect := Rect2(-door_size * 0.5, door_size)
	draw_rect(rect, Color(0.35, 0.95, 0.75, 0.10))
	draw_rect(rect, Color(0.35, 0.95, 0.75, 0.5), false, 5.0)
	if arrow_direction.length_squared() > 0.0:
		var dir := arrow_direction.normalized()
		var side := Vector2(-dir.y, dir.x) * 16.0
		var tip := dir * 22.0
		var tail := -dir * 26.0
		var color := Color(0.6, 1.0, 0.85, 0.9)
		draw_line(tail, tip, color, 7.0, true)
		draw_line(tip, tip - dir * 18.0 + side, color, 7.0, true)
		draw_line(tip, tip - dir * 18.0 - side, color, 7.0, true)


func _on_body_entered(body: Node2D) -> void:
	if _triggered or not (body is Player):
		return
	if RoomManager.is_transitioning():
		return
	_triggered = true
	RoomManager.change_room(target_room_path, target_spawn)
