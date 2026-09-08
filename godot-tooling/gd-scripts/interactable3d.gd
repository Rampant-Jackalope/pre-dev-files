@tool
class_name Interactable3D
extends Area3D

## Drag-and-drop 3D node that reports hover and click state as signals.
##
## This node IS the collision object (extends Area3D). Give it a
## CollisionShape3D child to define its pickable area. Any visual
## (mesh, skeletal model, etc.) is entirely optional and irrelevant to
## this script it only detects and reports hover/click state.
## 
## Keep in mind that this node prevents normal collisions from working.
## If collisions are needed, add a PhysicsBody as a child and `Duplicate` NOT COPY
## the existing collision shape as a child of the PhysicsBody.
## Because the collision shapes are duplicates they occupy the same space.
## This will break either collision detection or any of the events.
## To fix this make the Interactable3D and PhysicsBody work on different collision layers.
##
## Works with two picking sources interchangeably:
##   1. Viewport screen-space picking (mouse_entered / input_event), used
##      automatically when input_ray_pickable is true and the mouse is free.
##   2. External raycasts (for example an FPS camera-forward ray) that call
##      notify_hover_start / notify_hover_end / notify_left_press / etc
##      directly. Useful when the mouse is captured and screen-space
##      picking has no meaningful cursor to project from.
##
## For sources with real press/release events (a held mouse button), use
## notify_left_press and notify_left_release as a pair. For sources with
## only a single "activate" event (a tap, a scripted trigger), use the
## one-shot notify_left_click / notify_right_click instead.
##
## Connect from the editor's Node dock > Signals tab:
##   hover_start, hover_end,
##   left_pressed, left_released, left_clicked,
##   right_pressed, right_released, right_clicked

# hover
signal hover_start
signal hover_end

# press / release
signal left_pressed(hit_position: Vector3, normal: Vector3)
signal left_released(hit_position: Vector3, normal: Vector3)
signal right_pressed(hit_position: Vector3, normal: Vector3)
signal right_released(hit_position: Vector3, normal: Vector3)

# simple click: press and release both landed on this object
signal left_clicked(hit_position: Vector3, normal: Vector3)
signal right_clicked(hit_position: Vector3, normal: Vector3)

var is_hovered: bool = false
var is_left_pressed: bool = false
var is_right_pressed: bool = false

func _ready() -> void:
	if Engine.is_editor_hint():
		return

	if _find_descendant_of_type(self, CollisionShape3D) == null:
		push_error("Interactable3D: no CollisionShape3D found, this object can't be picked.")

	input_ray_pickable = true

	mouse_entered.connect(notify_hover_start)
	mouse_exited.connect(notify_hover_end)
	input_event.connect(_on_input_event)

# Editor-only: shows a warning icon on the node if the collider is missing.
func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if _find_descendant_of_type(self, CollisionShape3D) == null:
		warnings.append("Add a CollisionShape3D somewhere under this node so it can be picked.")
	return warnings

## Recursively searches the subtree for the first node of the given type.
## Needed because in imported/skeletal scenes the collider may be
## nested a level or two down rather than a direct child.
func _find_descendant_of_type(node: Node, type: Variant) -> Node:
	for child in node.get_children():
		if is_instance_of(child, type):
			return child
		var found := _find_descendant_of_type(child, type)
		if found != null:
			return found
	return null

# ---------------------------------------------------------------------------
# Public API. Call these from any picking source: Viewport input_event,
# a player's camera-forward raycast, or anything else.
# ---------------------------------------------------------------------------

func notify_hover_start() -> void:
	if is_hovered:
		return
	is_hovered = true
	hover_start.emit()

func notify_hover_end() -> void:
	if not is_hovered:
		return
	is_hovered = false
	hover_end.emit()

func notify_left_press(hit_position: Vector3, normal: Vector3) -> void:
	is_left_pressed = true
	left_pressed.emit(hit_position, normal)

func notify_left_release(hit_position: Vector3, normal: Vector3) -> void:
	if not is_left_pressed:
		return
	is_left_pressed = false
	left_released.emit(hit_position, normal)
	left_clicked.emit(hit_position, normal)

func notify_right_press(hit_position: Vector3, normal: Vector3) -> void:
	is_right_pressed = true
	right_pressed.emit(hit_position, normal)

func notify_right_release(hit_position: Vector3, normal: Vector3) -> void:
	if not is_right_pressed:
		return
	is_right_pressed = false
	right_released.emit(hit_position, normal)
	right_clicked.emit(hit_position, normal)

func notify_left_click(hit_position: Vector3, normal: Vector3) -> void:
	notify_left_press(hit_position, normal)
	notify_left_release(hit_position, normal)

func notify_right_click(hit_position: Vector3, normal: Vector3) -> void:
	notify_right_press(hit_position, normal)
	notify_right_release(hit_position, normal)

## Dispatches a raw mouse button event to the correct press/release method.
## Any external picking source (a player's camera-forward raycast, a custom
## input handler, and so on) can forward its InputEventMouseButton straight
## here instead of re-implementing the button-index/pressed matching itself.
func notify_mouse_button(event: InputEventMouseButton, hit_position: Vector3, normal: Vector3) -> void:
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				notify_left_press(hit_position, normal)
			else:
				notify_left_release(hit_position, normal)
		MOUSE_BUTTON_RIGHT:
			if event.pressed:
				notify_right_press(hit_position, normal)
			else:
				notify_right_release(hit_position, normal)

# ---------------------------------------------------------------------------
# Internal: Viewport-driven screen-space picking (used when the mouse is
# free, not captured).
# ---------------------------------------------------------------------------

func _on_input_event(
	_camera: Node,
	event: InputEvent,
	hit_position: Vector3,
	normal: Vector3,
	_shape_idx: int
) -> void:
	if not (event is InputEventMouseButton):
		return

	notify_mouse_button(event as InputEventMouseButton, hit_position, normal)
