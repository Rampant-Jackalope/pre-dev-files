class_name Player
extends CharacterBody3D

@onready var cam_pivot: Node3D = $CamPivot
@onready var spring_arm: SpringArm3D = $CamPivot/SpringArm3D
@onready var camera: Camera3D = $CamPivot/SpringArm3D/Camera3D
@onready var collider: CollisionShape3D = $CollisionShape3D

@export var run_speed := 5.0
@export var jump_height := 0.5 # meters, average casual human jump
@export var gravity := 9.81

@export var mouse_sensitivity := 0.0025
@export var min_pitch_deg := -20.0 # how far down you can look
@export var max_pitch_deg := 30.0 # how far up you can look

@export var interact_range := 3.0

@export var third_person_spring_length := 4.0
@export var first_person_spring_length := 0.0
@export var first_person_cam_offset := Vector3(0, 1.75, 0)
@export var third_person_cam_offset := Vector3(0, 1.75, 0)

var jump_speed: float

var _current_interactable: Interactable3D = null
var _current_hit_position: Vector3 = Vector3.ZERO
var _current_hit_normal: Vector3 = Vector3.UP

enum CameraMode { FIRST_PERSON, THIRD_PERSON }
var camera_mode: int = CameraMode.FIRST_PERSON

func _ready() -> void:
	set_cam_perspective(camera_mode)
	camera.current = true
	jump_speed = sqrt(2.0 * gravity * jump_height)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _input(event: InputEvent) -> void:
	# Mouse look: yaw rotates the whole body, pitch only rotates the camera
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * mouse_sensitivity)
		cam_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
		cam_pivot.rotation.x = clamp(
			cam_pivot.rotation.x,
			deg_to_rad(min_pitch_deg),
			deg_to_rad(max_pitch_deg)
		)

	# Let Esc release the mouse (debugging/menu purposes)
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return

	if event is InputEventMouseButton:
		_handle_interact_input(event as InputEventMouseButton)

func get_input() -> void:
	if Input.is_action_just_pressed("toggle_camera_perspective"):
		toggle_cam_perspective()
	var input_dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		input_dir.z -= 1.0
	if Input.is_key_pressed(KEY_S):
		input_dir.z += 1.0
	if Input.is_key_pressed(KEY_D):
		input_dir.x += 1.0
	if Input.is_key_pressed(KEY_A):
		input_dir.x -= 1.0
	input_dir = input_dir.normalized()

	# Transform local input into world space using the body's yaw only
	var direction := (transform.basis * input_dir)
	velocity.x = direction.x * run_speed
	velocity.z = direction.z * run_speed

	if is_on_floor() and Input.is_action_just_pressed("ui_accept"):
		velocity.y = jump_speed

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	get_input()
	move_and_slide()
	_update_interaction_raycast()

## Casts a ray from the camera every physics frame to find whatever
## Interactable3D the player is currently looking at. This replaces
## Viewport screen-space picking, which cannot work while the mouse
## is captured for FPS look, since there is no cursor position to
## project a ray from.
func _update_interaction_raycast() -> void:
	var space_state := get_world_3d().direct_space_state
	var origin: Vector3 = camera.global_position
	var forward: Vector3 = -camera.global_transform.basis.z
	var query := PhysicsRayQueryParameters3D.create(origin, origin + forward * interact_range)
	query.collide_with_areas = true
	query.collide_with_bodies = false   # don't need bodies for interaction picking
	query.collision_mask = 1 << 2       # bit for layer 3 ("Interactable"), 0-indexed so layer 3 = bit 2
	var result := space_state.intersect_ray(query)

	var hit: Interactable3D = null
	if result and result.collider is Interactable3D:
		hit = result.collider
		_current_hit_position = result.position
		_current_hit_normal = result.normal

	if hit != _current_interactable:
		if _current_interactable:
			_current_interactable.notify_hover_end()
		if hit:
			hit.notify_hover_start()
		_current_interactable = hit

func _handle_interact_input(mb: InputEventMouseButton) -> void:
	if not _current_interactable:
		return
	_current_interactable.notify_mouse_button(mb, _current_hit_position, _current_hit_normal)

# Setters
func toggle_cam_perspective() -> void:
	camera_mode = CameraMode.THIRD_PERSON if camera_mode == CameraMode.FIRST_PERSON else CameraMode.FIRST_PERSON
	set_cam_perspective(camera_mode)

func set_cam_perspective(mode: CameraMode) -> void:
	if mode == Player.CameraMode.FIRST_PERSON:
		camera.set_cull_mask_value(2, false)
		spring_arm.add_excluded_object(get_rid())
		spring_arm.spring_length = first_person_spring_length
		cam_pivot.position = first_person_cam_offset
	else:
		camera.set_cull_mask_value(2, true)
		spring_arm.remove_excluded_object(get_rid())
		spring_arm.spring_length = third_person_spring_length
		cam_pivot.position = third_person_cam_offset

func set_fov(fov: float) -> void:
	camera.fov = fov

func set_run_speed(value: float) -> void:
	run_speed = value

func set_jump_height(value: float) -> void:
	jump_height = value

func set_gravity(value: float) -> void:
	gravity = value

func set_mouse_sensitivity(value: float) -> void:
	mouse_sensitivity = value

func set_min_pitch_deg(value: float) -> void:
	min_pitch_deg = value

func set_max_pitch_deg(value: float) -> void:
	max_pitch_deg = value

func set_interact_range(value: float) -> void:
	interact_range = value
