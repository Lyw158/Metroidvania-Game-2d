class_name SavePoint
extends Area2D
## M4 存档点（长椅）：玩家进入范围后按 E → 回满生命 + 写入存档（房间 / 位置 / 能力 / 拾取物 / 存档点 ID）。
## 视觉为脚本绘制的长椅（零素材）；成为「当前存档点」后显示暖金色脉动。
## 经 @export 配置唯一 ID 与提示文案，可复用于后续所有房间（长椅 / 存档房）。

## 存档点唯一 ID（写入存档；用于判断"当前激活的存档点"）
@export var save_point_id: StringName = &"save_point"
## 未激活时的交互提示
@export var hint_text := "按 E 存档（回满生命）"
## 已激活时的交互提示
@export var active_hint_text := "按 E 休息（回满生命）"

var _player: Player = null
var _time := 0.0
var _flash := 0.0

@onready var _hint: Label = $Hint


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	var settings := LabelSettings.new()
	settings.font_size = 30
	settings.outline_size = 8
	settings.outline_color = Color(0.0, 0.0, 0.0, 0.85)
	_hint.label_settings = settings
	_hint.visible = false


func _process(delta: float) -> void:
	_time += delta
	_flash = maxf(_flash - delta * 1.6, 0.0)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if _player == null:
		return
	if event.is_action_pressed("interact"):
		_activate()


## 交互：回满生命 → 写入存档 → 视觉与文字反馈
func _activate() -> void:
	_player.heal_full()
	var scene := get_tree().current_scene
	var room_path := "" if scene == null else scene.scene_file_path
	if not SaveManager.save_game(room_path, _player.global_position, save_point_id):
		return
	_flash = 1.0
	_update_hint()
	_show_toast()


func _is_active() -> bool:
	return SaveManager.is_save_point_active(save_point_id)


func _update_hint() -> void:
	if _player == null:
		_hint.visible = false
		return
	_hint.visible = true
	_hint.text = active_hint_text if _is_active() else hint_text


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		_player = body
		_update_hint()


func _on_body_exited(body: Node2D) -> void:
	if body == _player:
		_player = null
		_hint.visible = false


func _draw() -> void:
	var active := _is_active()
	var pulse := 1.0 + 0.05 * sin(_time * 2.4)
	var wood := Color(0.55, 0.47, 0.32) if active else Color(0.38, 0.46, 0.6)
	var trim := Color(1.0, 0.83, 0.45, 0.95) if active else Color(0.75, 0.9, 1.0, 0.75)
	# 光晕（激活后常亮呼吸；保存瞬间闪光增强）
	var glow := (0.07 if active else 0.0) + _flash * 0.3
	if glow > 0.0:
		draw_circle(Vector2(0.0, -95.0), 150.0 * pulse, Color(1.0, 0.82, 0.42, glow * 0.35))
		draw_circle(Vector2(0.0, -95.0), 95.0 * pulse, Color(1.0, 0.85, 0.5, glow * 0.5))
	# 地面阴影（压扁圆）
	draw_set_transform(Vector2(0.0, -6.0), 0.0, Vector2(1.0, 0.28))
	draw_circle(Vector2.ZERO, 96.0, Color(0.0, 0.0, 0.0, 0.3))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 长椅（侧视）：椅背横板 + 两侧柱 + 座板 + 椅腿
	draw_rect(Rect2(-96.0, -172.0, 192.0, 20.0), wood)
	draw_rect(Rect2(-96.0, -152.0, 18.0, 76.0), wood)
	draw_rect(Rect2(78.0, -152.0, 18.0, 76.0), wood)
	draw_rect(Rect2(-100.0, -76.0, 200.0, 26.0), wood)
	draw_rect(Rect2(-100.0, -76.0, 200.0, 26.0), trim, false, 3.0)
	draw_rect(Rect2(-88.0, -50.0, 22.0, 50.0), wood)
	draw_rect(Rect2(66.0, -50.0, 22.0, 50.0), wood)
	# 激活标记：椅背中央的脉动光点
	if active:
		draw_circle(Vector2(0.0, -118.0), 9.0 * pulse, trim)


## 存档反馈：上浮"已存档"提示（占位 UI，M6 接入正式 HUD 前）
func _show_toast() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var toast := Label.new()
	toast.text = "已存档"
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.z_index = 10
	var settings := LabelSettings.new()
	settings.font_size = 36
	settings.font_color = Color(1.0, 0.92, 0.65)
	settings.outline_size = 9
	settings.outline_color = Color(0.05, 0.03, 0.0, 0.9)
	toast.label_settings = settings
	toast.size = Vector2(400.0, 60.0)
	scene.add_child(toast)
	toast.global_position = global_position + Vector2(-200.0, -240.0)
	var tween := toast.create_tween()
	tween.set_parallel(true)
	tween.tween_property(toast, "position:y", toast.position.y - 70.0, 1.2) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(toast, "modulate:a", 0.0, 1.2).set_delay(0.3)
	tween.chain().tween_callback(toast.queue_free)
