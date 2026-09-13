extends SceneTree
## Renders one frame of a scene to a PNG: loads the scene, applies the seed,
## camera pose and registry params, waits some frames and saves the viewport.
## Needs a rendering device; `mise run shot` runs it under xvfb-run so no
## window opens. Arguments follow `--` on the Godot command line:
##     <scene> <out.png> [--seed N] [--pose x,y,z,yaw,pitch] [--frames N]
##         [--params name=value,...] [--resolution WxH] [--ui]
## Param values are typed by the registry: numbers, true/false, `x:y` for a
## Vector2 and `#rrggbb[aa]` or `r:g:b[:a]` for a Color. Without --ui the HUD
## and tweak panel are hidden for the captured frame. Exits with status 1 on
## any error.

const DEFAULT_FRAMES := 40

var _scene_path := ""
var _out_path := ""
var _seed := WorldState.DEFAULT_SEED
var _pose := PackedFloat64Array()
var _frames := DEFAULT_FRAMES
var _params := {}
var _resolution := Vector2i.ZERO
var _keep_ui := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var problem := _parse(OS.get_cmdline_user_args())
	if problem != "":
		_fail(problem)
		return
	var packed := load(_scene_path) as PackedScene
	if packed == null:
		_fail("could not load scene %s" % _scene_path)
		return

	if _resolution != Vector2i.ZERO:
		DisplayServer.window_set_size(_resolution)
	var scene := packed.instantiate()
	var panels := scene.find_children("*", "TweakPanel", true, false)
	if scene is TweakPanel:
		panels.append(scene)
	# A saved "last used" preset would override the seed, pose and params.
	for panel: TweakPanel in panels:
		panel.restore_last = false
	WorldState.seed = _seed
	root.add_child(scene)
	await process_frame

	if not _pose.is_empty():
		var cameras := scene.find_children("*", "FreeFlyCamera", true, false)
		if cameras.is_empty():
			_fail("--pose given but %s has no FreeFlyCamera" % _scene_path)
			return
		(cameras[0] as FreeFlyCamera).set_pose(
			Vector3(_pose[0], _pose[1], _pose[2]), _pose[3], _pose[4])
	for param_name: String in _params:
		problem = _apply_param(panels, param_name, _params[param_name])
		if problem != "":
			_fail(problem)
			return

	for i in _frames:
		await process_frame

	var hidden: Array[CanvasLayer] = []
	if not _keep_ui:
		for node in scene.find_children("*", "CanvasLayer", true, false):
			if node is Hud or node is TweakPanel:
				hidden.append(node as CanvasLayer)
	var image := await Hud.grab_frame(root, hidden)
	if image == null or image.is_empty():
		_fail("the viewport returned no image (no rendering device?)")
		return
	if _resolution != Vector2i.ZERO and image.get_size() != _resolution:
		_fail("image is %dx%d, expected %dx%d" % [
			image.get_width(), image.get_height(), _resolution.x, _resolution.y])
		return

	var path := ProjectSettings.globalize_path(_out_path)
	var error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if error == OK:
		error = image.save_png(path)
	if error != OK:
		_fail("could not save %s: %s" % [path, error_string(error)])
		return
	print("shot: %s (%dx%d, seed %d, %s, %s)" % [
		path, image.get_width(), image.get_height(), WorldState.seed,
		RenderingServer.get_current_rendering_driver_name(), DisplayServer.get_name()])
	scene.queue_free()
	await process_frame
	quit(0)


## Reads the arguments into the fields; returns a problem or an empty string.
func _parse(args: PackedStringArray) -> String:
	var positional: Array[String] = []
	var i := 0
	while i < args.size():
		var arg := args[i]
		if not arg.begins_with("--"):
			positional.append(arg)
			i += 1
			continue
		if arg == "--ui":
			_keep_ui = true
			i += 1
			continue
		if i + 1 >= args.size():
			return "%s needs a value" % arg
		var value := args[i + 1]
		i += 2
		match arg:
			"--seed":
				if not value.is_valid_int() or int(value) < 0 or int(value) > WorldState.MAX_SEED:
					return "--seed must be an integer from 0 to %d, not '%s'" % [WorldState.MAX_SEED, value]
				_seed = int(value)
			"--pose":
				var parts := value.split(",")
				if parts.size() != 5 or not Array(parts).all(func(p: String) -> bool: return p.strip_edges().is_valid_float()):
					return "--pose must be x,y,z,yaw,pitch, not '%s'" % value
				for part in parts:
					_pose.append(part.strip_edges().to_float())
			"--frames":
				if not value.is_valid_int() or int(value) < 1:
					return "--frames must be a positive integer, not '%s'" % value
				_frames = int(value)
			"--params":
				for pair in value.split(",", false):
					var eq := pair.find("=")
					if eq <= 0:
						return "--params entries must be name=value, not '%s'" % pair
					_params[pair.substr(0, eq).strip_edges()] = pair.substr(eq + 1).strip_edges()
			"--resolution":
				var size := value.to_lower().split("x")
				if size.size() != 2 or not size[0].is_valid_int() or not size[1].is_valid_int() \
						or int(size[0]) < 1 or int(size[1]) < 1:
					return "--resolution must be WIDTHxHEIGHT, not '%s'" % value
				_resolution = Vector2i(int(size[0]), int(size[1]))
			_:
				return "unknown option %s" % arg
	if positional.size() != 2:
		return "usage: shot.gd -- <scene> <out.png> [--seed N] [--pose x,y,z,yaw,pitch] [--frames N] [--params k=v,...] [--resolution WxH] [--ui]"
	_scene_path = positional[0]
	if not _scene_path.begins_with("res://"):
		_scene_path = "res://" + _scene_path.trim_prefix("./")
	_out_path = positional[1]
	if not _out_path.to_lower().ends_with(".png"):
		return "output must be a .png file, not '%s'" % _out_path
	return ""


## Sets one registry param from its text form; returns a problem or "".
func _apply_param(panels: Array[Node], param_name: String, text: String) -> String:
	for panel: TweakPanel in panels:
		if panel.registry == null:
			continue
		for group in panel.registry.groups:
			for param in group.params:
				if param.name != param_name:
					continue
				var value: Variant = _typed(param.kind, text)
				if value == null:
					return "--params %s: '%s' is not a valid %s" % [
						param_name, text, ParamRegistry.Kind.keys()[param.kind].to_lower()]
				panel.registry.set_value(param, value)
				return ""
	return "--params: no registry param named %s in %s" % [param_name, _scene_path]


## Parses `text` as a value of `kind`; null when it does not parse.
static func _typed(kind: ParamRegistry.Kind, text: String) -> Variant:
	match kind:
		ParamRegistry.Kind.FLOAT:
			return text.to_float() if text.is_valid_float() else null
		ParamRegistry.Kind.INT:
			return text.to_int() if text.is_valid_int() else null
		ParamRegistry.Kind.BOOL:
			match text.to_lower():
				"true", "1", "on":
					return true
				"false", "0", "off":
					return false
			return null
		ParamRegistry.Kind.VEC2:
			var parts := text.split(":")
			if parts.size() == 2 and parts[0].is_valid_float() and parts[1].is_valid_float():
				return Vector2(parts[0].to_float(), parts[1].to_float())
			return null
		ParamRegistry.Kind.COLOR:
			if text.begins_with("#"):
				return Color.from_string(text, Color()) if Color.html_is_valid(text) else null
			var channels := text.split(":")
			if channels.size() < 3 or channels.size() > 4:
				return null
			var values: Array[float] = []
			for channel in channels:
				if not channel.is_valid_float():
					return null
				values.append(channel.to_float())
			return Color(values[0], values[1], values[2], values[3] if values.size() == 4 else 1.0)
	return null


func _fail(message: String) -> void:
	printerr("shot: %s" % message)
	quit(1)
