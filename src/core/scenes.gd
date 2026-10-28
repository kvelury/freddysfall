class_name Scenes
extends RefCounted

## Swapping the running scene, like DevSession._replace does for a dev rebuild.


## Frees `old` and puts `next` in its place, as the current scene if `old` was.
## Call it deferred: it is usually reached from a button inside `old`.
static func swap(old: Node, next: Node) -> void:
	var tree := old.get_tree()
	var parent := old.get_parent()
	var was_main := tree.current_scene == old
	old.free()
	tree.paused = false
	parent.add_child(next)
	if was_main:
		tree.current_scene = next
