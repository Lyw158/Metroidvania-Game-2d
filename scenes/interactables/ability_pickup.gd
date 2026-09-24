class_name AbilityPickup
extends Area2D
## M2 能力拾取物：发光球体视觉（脚本绘制，零素材依赖）。
## 玩家进入范围 → 短暂定帧 → 光圈爆开 + 文字提示 → 玩家解锁能力并记录。
## 已拾取过的拾取物（GameManager 有记录）在进入场景时自动移除，防止重复获取。
## 通过 @export 配置能力 id / 名称 / 提示文字，可复用于后续所有能力（冲刺、滑铲等）。

## 拾取后解锁的能力 id（对应 PlayerAbilities 的常量）
@export var ability_id: StringName = &"double_jump"
## 拾取提示第一行显示的能力名
@export var ability_name := "二段跳"
## 拾取提示第二行的操作说明
@export var hint_text := "空中再按一次跳跃键"
## 唯一 ID（"已拾取"记录用）；留空时使用场景中的节点路径
@export var pickup_uid: StringName = &""

## 定帧时长（秒，真实时间，不受 time_scale 影响）
const FREEZE_TIME := 0.10
## 光圈特效时长
const RIPPLE_DURATION := 0.6
## 文字提示总时长
const TOAST_TIME := 1.5

var _uid: StringName
var _picked_up := false
var _time := 0.0


func _ready() -> void:
	_uid = pickup_uid if pickup_uid != &"" else StringName(str(get_path()))
	if GameManager.is_pickup_collected(_uid):
		queue_free()
		return
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	# 上下浮动 + 呼吸缩放
	draw_set_transform(Vector2(0.0, sin(_time * 2.2) * 12.0))
	var pulse := 1.0 + 0.05 * sin(_time * 2.6)
	# 光晕
	draw_circle(Vector2.ZERO, 105.0 * pulse, Color(0.35, 0.9, 1.0, 0.05))
	draw_circle(Vector2.ZERO, 78.0 * pulse, Color(0.35, 0.9, 1.0, 0.09))
	# 主体
	draw_circle(Vector2.ZERO, 46.0, Color(0.07, 0.35, 0.45, 0.92))
	draw_arc(Vector2.ZERO, 52.0, 0.0, TAU, 64, Color(0.55, 0.95, 1.0, 0.95), 6.0, true)
	# 双箭头符号（二段跳意象）
	var color := Color(0.85, 1.0, 1.0, 0.95)
	_draw_chevron(Vector2(0.0, -16.0), color)
	_draw_chevron(Vector2(0.0, 10.0), color)


func _draw_chevron(center: Vector2, color: Color) -> void:
	var points := PackedVector2Array([
		center + Vector2(-15.0, 9.0),
		center + Vector2(0.0, -7.0),
		center + Vector2(15.0, 9.0),
	])
	draw_polyline(points, color, 7.0, true)


func _on_body_entered(body: Node2D) -> void:
	if _picked_up:
		return
	var player := body as Player
	if player == null:
		return
	_picked_up = true
	set_deferred("monitoring", false)
	GameManager.record_pickup(_uid)
	player.unlock_ability(ability_id)
	_play_pickup_effect()


## 拾取演出：短暂定帧（真实时间）→ 光圈爆开 + 文字上浮 → 本体消失
## 注意：不能用 time_scale=0 + create_timer 恢复——time_scale=0 时定时器永远不超时（0 除法 NaN），这里用真实时间轮询。
func _play_pickup_effect() -> void:
	Engine.time_scale = 0.0
	var deadline := Time.get_ticks_msec() + int(FREEZE_TIME * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	Engine.time_scale = 1.0
	var fx_parent: Node = get_tree().current_scene
	if fx_parent == null:
		fx_parent = get_parent()
	_spawn_ripple(fx_parent)
	_spawn_toast(fx_parent)
	visible = false
	queue_free()


func _spawn_ripple(fx_parent: Node) -> void:
	var ripple := _Ripple.new()
	ripple.duration = RIPPLE_DURATION
	fx_parent.add_child(ripple)
	ripple.global_position = global_position


func _spawn_toast(fx_parent: Node) -> void:
	var toast := Label.new()
	toast.text = "获得能力：%s\n%s" % [ability_name, hint_text]
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.z_index = 10
	var settings := LabelSettings.new()
	settings.font_size = 40
	settings.font_color = Color(0.85, 1.0, 1.0)
	settings.outline_size = 10
	settings.outline_color = Color(0.0, 0.06, 0.1, 0.9)
	toast.label_settings = settings
	toast.size = Vector2(640.0, 120.0)
	fx_parent.add_child(toast)
	toast.global_position = global_position + Vector2(-320.0, -200.0)
	var tween := toast.create_tween()
	tween.set_parallel(true)
	tween.tween_property(toast, "position:y", toast.position.y - 90.0, TOAST_TIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(toast, "modulate:a", 0.0, TOAST_TIME).set_delay(0.3)
	tween.chain().tween_callback(toast.queue_free)


## 光圈特效（内部类）：短暂爆开并淡出
class _Ripple extends Node2D:
	var duration := 0.6
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		var k := clampf(_t / duration, 0.0, 1.0)
		modulate.a = 1.0 - k
		scale = Vector2.ONE * lerpf(0.7, 3.4, ease(k, 0.3))
		queue_redraw()
		if _t >= duration:
			queue_free()

	func _draw() -> void:
		draw_circle(Vector2.ZERO, 58.0, Color(0.6, 0.95, 1.0, 0.12))
		draw_arc(Vector2.ZERO, 58.0, 0.0, TAU, 64, Color(0.6, 0.95, 1.0, 0.9), 7.0, true)
