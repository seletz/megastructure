class_name SeedControl
extends HBoxContainer
## Seed field with Random and Copy buttons, bound to WorldState.seed.
##
## The field accepts an unsigned 32-bit integer; out-of-range numbers are
## clamped and anything else reverts to the current seed. R picks a random
## seed unless a text field has focus.

var _field: LineEdit


func _ready() -> void:
	var label := Label.new()
	label.text = "seed"
	add_child(label)

	_field = LineEdit.new()
	_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_field.select_all_on_focus = true
	_field.max_length = 20
	_field.tooltip_text = "World seed, 0..%d" % WorldState.MAX_SEED
	_field.text_submitted.connect(func(text: String) -> void:
		_commit(text)
		_field.release_focus()
	)
	_field.focus_exited.connect(func() -> void: _commit(_field.text))
	add_child(_field)

	var random := Button.new()
	random.text = "Random"
	random.tooltip_text = "New random seed (R)"
	random.pressed.connect(WorldState.randomize_seed)
	add_child(random)

	var copy := Button.new()
	copy.text = "Copy"
	copy.tooltip_text = "Copy the seed to the clipboard"
	copy.pressed.connect(func() -> void: DisplayServer.clipboard_set(str(WorldState.seed)))
	add_child(copy)

	WorldState.seed_changed.connect(_show)
	_show(WorldState.seed)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode != KEY_R:
		return
	if key.ctrl_pressed or key.alt_pressed or key.meta_pressed:
		return
	var focused := get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit:
		return
	WorldState.randomize_seed()
	get_viewport().set_input_as_handled()


## Parses seed text; returns -1 when it is not a non-negative decimal integer.
## Values above the uint32 range clamp to WorldState.MAX_SEED.
static func parse_seed(text: String) -> int:
	var digits := text.strip_edges()
	if digits.is_empty():
		return -1
	for c in digits:
		if c < "0" or c > "9":
			return -1
	digits = digits.lstrip("0")
	if digits.is_empty():
		return 0
	# More than ten digits always exceeds uint32 and could overflow int64.
	if digits.length() > 10:
		return WorldState.MAX_SEED
	return mini(digits.to_int(), WorldState.MAX_SEED)


func _commit(text: String) -> void:
	var value := parse_seed(text)
	if value >= 0:
		WorldState.seed = value
	_show(WorldState.seed)


func _show(seed: int) -> void:
	_field.text = str(seed)
