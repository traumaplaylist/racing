extends Node
## UI string table. Strings live in data/strings_<lang>.json, never in game logic.

const DEFAULT_LANG := "en"

var _strings: Dictionary = {}


func _ready() -> void:
	load_language(DEFAULT_LANG)


func load_language(lang: String) -> void:
	var path := "res://data/strings_%s.json" % lang
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Loc: cannot open %s" % path)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_strings = parsed
	else:
		push_error("Loc: bad JSON in %s" % path)


## Returns the string for key, with {0}, {1}... replaced by args.
func t(key: String, args: Array = []) -> String:
	var s: String = _strings.get(key, key)
	for i in args.size():
		s = s.replace("{%d}" % i, str(args[i]))
	return s


func place(n: int) -> String:
	if n >= 1 and n <= 3:
		return t("place_%d" % n)
	return t("place_n", [n])
