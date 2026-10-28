class_name LaunchArgs
extends RefCounted

## Launch options: `--name=value` or `--name` on the command line, or
## `?name=value` on the web page's address.


## The value of option `name`, "1" for a bare `--name`, or empty if it was not
## given.
static func value(name: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg == "--" + name:
			return "1"
		if arg.begins_with("--%s=" % name):
			return arg.substr(name.length() + 3)
	if OS.has_feature("web"):
		var found = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('%s')" % name)
		if found != null:
			return String(found)
	return ""
