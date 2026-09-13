extends SceneTree
## Verifies the code map in docs/code/: every file under scripts/, shaders/ and
## scenes/ (except .uid and .import files) is linked from exactly one note, and
## every link into those folders points at a file that exists.
## Run headless with `mise run code-map-check`.

const NOTES_DIR := "res://docs/code"
const SOURCE_DIRS: Array[String] = ["res://scripts", "res://shaders", "res://scenes"]
const IGNORED_EXTENSIONS: Array[String] = ["uid", "import"]
## Target of an inline markdown link, without a title or anchor.
const _LINK_PATTERN := "\\]\\(<?([^)#\\s>]+)"

var _failures := 0


func _init() -> void:
	var sources := PackedStringArray()
	for dir in SOURCE_DIRS:
		_collect(dir, sources)
	sources.sort()

	# Source path -> notes linking it.
	var linked := {}
	for path in sources:
		linked[path] = PackedStringArray()

	var link_re := RegEx.create_from_string(_LINK_PATTERN)
	var notes := DirAccess.get_files_at(NOTES_DIR)
	for note in notes:
		if not note.ends_with(".md"):
			continue
		var text := FileAccess.get_file_as_string(NOTES_DIR.path_join(note))
		var seen := {}
		for link in link_re.search_all(text):
			var target := link.get_string(1)
			if target.contains("://"):
				continue
			var path := NOTES_DIR.path_join(target).simplify_path()
			if not _in_source_dirs(path) or seen.has(path):
				continue
			seen[path] = true
			if linked.has(path):
				# Packed arrays are copied on read, so store the grown array back.
				var owners: PackedStringArray = linked[path]
				owners.append(note)
				linked[path] = owners
			else:
				_fail("%s links %s, which is not a source file" % [note, target])

	for path in sources:
		var owners: PackedStringArray = linked[path]
		var file := path.trim_prefix("res://")
		if owners.is_empty():
			_fail("%s is not linked from any note" % file)
		elif owners.size() > 1:
			_fail("%s is linked from %s" % [file, ", ".join(owners)])
		else:
			print("  ok    %-42s %s" % [file, owners[0]])

	print("code map check: %d files, %s" % [sources.size(), "ok" if _failures == 0 else "%d failure(s)" % _failures])
	quit(0 if _failures == 0 else 1)


func _collect(dir: String, into: PackedStringArray) -> void:
	for file in DirAccess.get_files_at(dir):
		if file.get_extension() not in IGNORED_EXTENSIONS:
			into.append(dir.path_join(file))
	for sub in DirAccess.get_directories_at(dir):
		_collect(dir.path_join(sub), into)


static func _in_source_dirs(path: String) -> bool:
	for dir in SOURCE_DIRS:
		if path.begins_with(dir + "/"):
			return true
	return false


func _fail(message: String) -> void:
	_failures += 1
	printerr("  FAIL  %s" % message)
