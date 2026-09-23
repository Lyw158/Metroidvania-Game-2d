class_name Player
extends CharacterBody2D


@export var move_speed := 140.0
@export var jump_velocity := -300.0
@export var gravity := 1000.0


func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
		velocity.y += gravity * delta

	# Handle jump.
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = jump_velocity

	# Get the input direction and handle the movement/deceleration.
	var direction := Input.get_axis("move_left", "move_right")
	velocity.x = direction * move_speed

	move_and_slide()
