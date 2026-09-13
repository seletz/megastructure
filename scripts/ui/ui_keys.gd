class_name UiKeys
extends RefCounted
## Shared rules for single-key shortcuts (R, H, P, F1, F12).
##
## A shortcut fires on a fresh press without Ctrl, Alt or Meta, and never while
## a text field has focus, so typing a seed or preset name does not trigger it.


## True when `event` is a fresh press of one of `keycodes` without modifiers.
static func is_shortcut(event: InputEvent, keycodes: Array[Key]) -> bool:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return false
	if key.ctrl_pressed or key.alt_pressed or key.meta_pressed:
		return false
	return key.keycode in keycodes


## True when the focused control in `viewport` takes typed text.
static func text_field_focused(viewport: Viewport) -> bool:
	if viewport == null:
		return false
	var focused := viewport.gui_get_focus_owner()
	return focused is LineEdit or focused is TextEdit
