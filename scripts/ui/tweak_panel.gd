class_name TweakPanel
extends CanvasLayer
## Collapsible, scrollable panel of every tweakable shader and script parameter.
##
## Controls are generated from a ParamRegistry built on the target material,
## and every change is written straight back to the ShaderMaterial. Nodes in
## `param_sources` add script parameters through their
## `register_params(registry: ParamRegistry)` method before the panel is built;
## their changes go to the setter they registered. Tab toggles the panel; while
## it is open the mouse is released and camera look is off.
##
## The Presets section at the top saves, loads and deletes PresetStore presets;
## the last used preset is restored when the panel starts.

const PANEL_WIDTH := 480.0
const LABEL_WIDTH := 160.0

## MeshInstance3D whose active surface material is the raymarch ShaderMaterial.
## May be empty in scenes without a shader, where only script params show.
@export var material_source: NodePath
## Nodes with a `register_params(registry: ParamRegistry)` method.
@export var param_sources: Array[NodePath] = []
## Show the presets section (presets only make sense for the main scene).
@export var show_presets := true
## FreeFlyCamera whose look input is suspended while the panel is open.
@export var camera: NodePath
@export var start_open := false
## Restore the last used preset on start (off for checks that need defaults).
@export var restore_last := true
@export var preset_directory := PresetStore.DEFAULT_DIRECTORY

var registry: ParamRegistry
var presets: PresetStore

var _panel: PanelContainer
var _sections: VBoxContainer
## Param name -> Callable(value: Variant) that refreshes its controls.
var _refreshers := {}
var _mouse_mode_before_open := Input.MOUSE_MODE_VISIBLE
## True while widgets are refreshed from values, so their change signals do not
## write rounded widget values back to the material.
var _refreshing := false
var _preset_list: OptionButton
var _preset_name: LineEdit
var _preset_delete: Button
var _preset_status: Label


func _ready() -> void:
	var material: ShaderMaterial = null
	if not material_source.is_empty():
		var mesh := get_node_or_null(material_source) as MeshInstance3D
		if mesh != null:
			material = mesh.get_active_material(0) as ShaderMaterial
		if material == null:
			push_warning("TweakPanel: no ShaderMaterial found at %s" % material_source)
			return
	registry = ParamRegistry.from_material(material)
	for path in param_sources:
		var source := get_node_or_null(path)
		if source == null or not source.has_method("register_params"):
			push_warning("TweakPanel: no register_params() on %s" % path)
			continue
		source.call("register_params", registry)
	var restored := PresetStore.BUILTIN_NAME
	if show_presets:
		presets = PresetStore.create(registry, _camera(), preset_directory)
		if restore_last:
			var preset := presets.load_preset(presets.last_used_name())
			if preset != null:
				presets.apply(preset, _camera())
				restored = preset.name
	_build()
	if show_presets:
		_refresh_preset_list(restored)
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
	var cam := _camera()
	if cam != null:
		cam.look_enabled = not open


func _camera() -> FreeFlyCamera:
	return get_node_or_null(camera) as FreeFlyCamera


## Loads a preset by name into the material, WorldState, camera and widgets.
func load_preset(preset_name: String) -> bool:
	var preset := presets.load_preset(preset_name)
	if preset == null:
		_set_status("could not load \"%s\"" % preset_name)
		return false
	presets.apply(preset, _camera())
	presets.set_last_used(preset.name)
	refresh_widgets()
	_refresh_preset_list(preset.name)
	_set_status("loaded \"%s\"" % preset.name)
	return true


## Saves the current state under a name; returns false when it could not.
func save_preset(preset_name: String) -> bool:
	var problem := PresetStore.validate_name(preset_name)
	if not problem.is_empty():
		_set_status(problem)
		return false
	var err := presets.save(presets.capture(preset_name, _camera()))
	if err != OK:
		_set_status("could not save \"%s\": %s" % [preset_name, error_string(err)])
		return false
	presets.set_last_used(preset_name)
	_refresh_preset_list(preset_name)
	_set_status("saved \"%s\"" % preset_name)
	return true


func delete_preset(preset_name: String) -> bool:
	var err := presets.delete(preset_name)
	if err != OK:
		_set_status("could not delete \"%s\": %s" % [preset_name, error_string(err)])
		return false
	_refresh_preset_list(PresetStore.BUILTIN_NAME)
	_set_status("deleted \"%s\"" % preset_name)
	return true


## Updates every parameter widget from the material without writing back.
func refresh_widgets() -> void:
	_refreshing = true
	for group in registry.groups:
		for param in group.params:
			(_refreshers[param.name] as Callable).call(registry.get_value(param))
	_refreshing = false


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

	if show_presets:
		_build_presets()
		_sections.add_child(HSeparator.new())

	_sections.add_child(SeedControl.new())
	_sections.add_child(HSeparator.new())

	for group in registry.groups:
		_build_group(group)


func _build_presets() -> void:
	var list_row := HBoxContainer.new()
	_sections.add_child(list_row)

	_preset_list = OptionButton.new()
	_preset_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preset_list.clip_text = true
	_preset_list.item_selected.connect(func(_index: int) -> void: _update_preset_buttons())
	list_row.add_child(_preset_list)

	var load_button := Button.new()
	load_button.text = "Load"
	load_button.pressed.connect(func() -> void: load_preset(_selected_preset()))
	list_row.add_child(load_button)

	_preset_delete = Button.new()
	_preset_delete.text = "Delete"
	_preset_delete.pressed.connect(func() -> void: delete_preset(_selected_preset()))
	list_row.add_child(_preset_delete)

	var save_row := HBoxContainer.new()
	_sections.add_child(save_row)

	_preset_name = LineEdit.new()
	_preset_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preset_name.placeholder_text = "preset name"
	_preset_name.select_all_on_focus = true
	_preset_name.text_submitted.connect(func(text: String) -> void:
		if save_preset(text):
			_preset_name.release_focus()
	)
	save_row.add_child(_preset_name)

	var save_button := Button.new()
	save_button.text = "Save as"
	save_button.pressed.connect(func() -> void: save_preset(_preset_name.text))
	save_row.add_child(save_button)

	_preset_status = Label.new()
	_preset_status.clip_text = true
	_sections.add_child(_preset_status)


func _refresh_preset_list(selected: String) -> void:
	_preset_list.clear()
	for preset_name in presets.list_names():
		_preset_list.add_item(preset_name)
		if preset_name == selected:
			_preset_list.select(_preset_list.item_count - 1)
	if _preset_list.selected < 0:
		_preset_list.select(0)
	if not PresetStore.is_builtin(selected):
		_preset_name.text = selected
	_update_preset_buttons()


func _selected_preset() -> String:
	return _preset_list.get_item_text(_preset_list.selected) if _preset_list.selected >= 0 else ""


func _update_preset_buttons() -> void:
	_preset_delete.disabled = PresetStore.is_builtin(_selected_preset())


func _set_status(text: String) -> void:
	_preset_status.text = text


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
		_refreshing = true
		for param in group.params:
			(_refreshers[param.name] as Callable).call(param.default_value)
		_refreshing = false
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
		if not _refreshing:
			registry.set_value(param, int(v) if is_int else v)
	)
	_refreshers[param.name] = func(v: Variant) -> void:
		slider.value = float(v)


func _build_bool(row: HBoxContainer, param: ParamRegistry.Param, value: Variant) -> void:
	var check := CheckBox.new()
	# The whole row right of the label is the hit target, and the box toggles on
	# press, like the sliders react, so a release that lands elsewhere still
	# counts. Clicking the label toggles it too.
	check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	check.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	check.button_pressed = bool(value)
	check.toggled.connect(func(on: bool) -> void:
		if not _refreshing:
			registry.set_value(param, on)
	)
	row.add_child(check)
	var label := row.get_child(0) as Label
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	label.gui_input.connect(func(event: InputEvent) -> void:
		var button := event as InputEventMouseButton
		if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
			check.button_pressed = not check.button_pressed
			label.accept_event()
	)
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
		if not _refreshing:
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
		if not _refreshing:
			registry.set_value(param, c)
	)
	row.add_child(picker)
	_refreshers[param.name] = func(v: Variant) -> void:
		picker.color = v as Color


func _configure_range(control: Range, param: ParamRegistry.Param) -> void:
	control.min_value = param.min_value
	control.max_value = param.max_value
	control.step = param.step
