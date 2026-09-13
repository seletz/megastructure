class_name TweakPanel
extends CanvasLayer
## Collapsible, scrollable panel of every tweakable shader parameter.
##
## Controls are generated from a ParamRegistry built on the target material,
## and every change is written straight back to the ShaderMaterial. Tab toggles
## the panel; while it is open the mouse is released and camera look is off.

const PANEL_WIDTH := 480.0
const LABEL_WIDTH := 160.0

## MeshInstance3D whose active surface material is the raymarch ShaderMaterial.
@export var material_source: NodePath
## FreeFlyCamera whose look input is suspended while the panel is open.
@export var camera: NodePath
@export var start_open := false

var registry: ParamRegistry

var _panel: PanelContainer
var _sections: VBoxContainer
## Param name -> Callable(value: Variant) that refreshes its controls.
var _refreshers := {}
var _mouse_mode_before_open := Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	var mesh := get_node_or_null(material_source) as MeshInstance3D
	var material: ShaderMaterial = null
	if mesh != null:
		material = mesh.get_active_material(0) as ShaderMaterial
	if material == null:
		push_warning("TweakPanel: no ShaderMaterial found at %s" % material_source)
		return
	registry = ParamRegistry.from_material(material)
	_build()
	_panel.visible = false
	if start_open:
		_set_open(true)


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_TAB:
		if _panel != null:
			_set_open(not _panel.visible)
		get_viewport().set_input_as_handled()


func is_open() -> bool:
	return _panel != null and _panel.visible


func _set_open(open: bool) -> void:
	if open == _panel.visible:
		return
	if open:
		_mouse_mode_before_open = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		var focused := _panel.get_viewport().gui_get_focus_owner()
		if focused != null:
			focused.release_focus()
		Input.mouse_mode = _mouse_mode_before_open
	_panel.visible = open
	var cam := get_node_or_null(camera) as FreeFlyCamera
	if cam != null:
		cam.look_enabled = not open


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -PANEL_WIDTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.06, 0.88)
	style.set_content_margin_all(8.0)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)

	_sections = VBoxContainer.new()
	_sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_sections)

	var title := Label.new()
	title.text = "Parameters (Tab to close)"
	_sections.add_child(title)

	_sections.add_child(SeedControl.new())
	_sections.add_child(HSeparator.new())

	for group in registry.groups:
		_build_group(group)


func _build_group(group: ParamRegistry.Group) -> void:
	var header := HBoxContainer.new()
	_sections.add_child(header)

	var toggle := Button.new()
	toggle.toggle_mode = true
	toggle.button_pressed = true
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(toggle)

	var reset := Button.new()
	reset.text = "Reset"
	header.add_child(reset)

	var body := VBoxContainer.new()
	_sections.add_child(body)

	var update_title := func(expanded: bool) -> void:
		toggle.text = "%s %s" % ["[-]" if expanded else "[+]", group.name]
		body.visible = expanded
	update_title.call(true)
	toggle.toggled.connect(update_title)

	for param in group.params:
		body.add_child(_build_param(param))

	reset.pressed.connect(func() -> void:
		registry.reset_group(group)
		for param in group.params:
			(_refreshers[param.name] as Callable).call(param.default_value)
	)


func _build_param(param: ParamRegistry.Param) -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = param.label
	label.tooltip_text = param.name
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.custom_minimum_size.x = LABEL_WIDTH
	label.clip_text = true
	row.add_child(label)

	var value: Variant = registry.get_value(param)
	match param.kind:
		ParamRegistry.Kind.FLOAT, ParamRegistry.Kind.INT:
			_build_scalar(row, param, value)
		ParamRegistry.Kind.BOOL:
			_build_bool(row, param, value)
		ParamRegistry.Kind.VEC2:
			_build_vec2(row, param, value)
		ParamRegistry.Kind.COLOR:
			_build_color(row, param, value)
	return row


func _build_scalar(row: HBoxContainer, param: ParamRegistry.Param, value: Variant) -> void:
	var slider := HSlider.new()
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_configure_range(slider, param)
	row.add_child(slider)

	slider.value = float(value)

	var spin := SpinBox.new()
	spin.custom_minimum_size.x = 90.0
	spin.select_all_on_focus = true
	# Sharing makes the slider and spin box one Range, so they never drift;
	# the spin box adopts the slider's already configured range.
	slider.share(spin)
	row.add_child(spin)

	var is_int := param.kind == ParamRegistry.Kind.INT
	slider.value_changed.connect(func(v: float) -> void:
		registry.set_value(param, int(v) if is_int else v)
	)
	_refreshers[param.name] = func(v: Variant) -> void:
		slider.value = float(v)


func _build_bool(row: HBoxContainer, param: ParamRegistry.Param, value: Variant) -> void:
	var check := CheckBox.new()
	check.button_pressed = bool(value)
	check.toggled.connect(func(on: bool) -> void:
		registry.set_value(param, on)
	)
	row.add_child(check)
	_refreshers[param.name] = func(v: Variant) -> void:
		check.button_pressed = bool(v)


func _build_vec2(row: HBoxContainer, param: ParamRegistry.Param, value: Variant) -> void:
	var spins: Array[SpinBox] = []
	for i in 2:
		var spin := SpinBox.new()
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spin.select_all_on_focus = true
		_configure_range(spin, param)
		spin.allow_greater = true
		spin.allow_lesser = true
		spin.prefix = "xy"[i]
		row.add_child(spin)
		spins.append(spin)
	var refresh := func(v: Variant) -> void:
		var vec := v as Vector2
		spins[0].value = vec.x
		spins[1].value = vec.y
	refresh.call(value)
	var push := func(_v: float) -> void:
		registry.set_value(param, Vector2(spins[0].value, spins[1].value))
	for spin in spins:
		spin.value_changed.connect(push)
	_refreshers[param.name] = refresh


func _build_color(row: HBoxContainer, param: ParamRegistry.Param, value: Variant) -> void:
	var picker := ColorPickerButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.custom_minimum_size.y = 24.0
	picker.edit_alpha = false
	picker.color = value as Color
	picker.color_changed.connect(func(c: Color) -> void:
		registry.set_value(param, c)
	)
	row.add_child(picker)
	_refreshers[param.name] = func(v: Variant) -> void:
		picker.color = v as Color


func _configure_range(control: Range, param: ParamRegistry.Param) -> void:
	control.min_value = param.min_value
	control.max_value = param.max_value
	control.step = param.step
