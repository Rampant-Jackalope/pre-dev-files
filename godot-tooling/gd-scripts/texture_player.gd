class_name TexturePlayer
extends TextureRect

@export var fps := 30.0
@export var frame_folder := ""
@export var loop := false

var frames: Array[Texture2D] = []
var current_frame := 0
var elapsed := 0.0

func _ready():
	if frame_folder.is_empty():
		return

	set_frame_dir(frame_folder)

func _process(delta: float):
	if frames.is_empty() or fps <= 0.0:
		return

	elapsed += delta

	if elapsed >= 1.0 / fps:
		elapsed -= 1.0 / fps
		play()

func set_frame_dir(dir: String):
	frame_folder = dir
	frames.clear()
	current_frame = 0
	elapsed = 0.0

	var directory := DirAccess.open(frame_folder)

	if directory == null:
		push_error("Could not open: " + frame_folder)
		return

	var files := directory.get_files()
	files.sort()

	for file in files:
		if file.ends_with(".png"):
			var tex := load(frame_folder + file) as Texture2D
			if tex:
				frames.append(tex)

	if not frames.is_empty():
		texture = frames[0]

func play():
	if frames.is_empty():
		return

	current_frame += 1

	if current_frame >= frames.size():
		if loop:
			current_frame = 0
		else:
			current_frame = frames.size() - 1

	texture = frames[current_frame]
