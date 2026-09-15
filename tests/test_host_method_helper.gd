extends GutTest

## HostMethodHelper.try_call_bool (scripts/components/host_method_helper.gd) — the one duck-typed host probe that
## replaced the scattered `obj.has_method(&"x") and bool(obj.call(&"x"))` idiom (body_model_swap, fall_scream,
## character.is_following). Its contract is the DEFAULT: a null host or a host without the method returns
## `default`, so a NEGATED read picks the default that preserves the no-method case
## (`airborne = not try_call_bool(host, &"is_on_floor", true)` -> not airborne when the host can't say).
## A present method's result is coerced to bool (an int 0/1 from a legacy host still reads right).

## A host answering both ways plus non-bool truthy/falsy returns.
class Host extends RefCounted:
	var flag: bool = true
	func is_on_floor() -> bool:
		return flag
	func says_one() -> int:
		return 1
	func says_zero() -> int:
		return 0
	func says_float() -> float:
		return 0.5


class Mute extends RefCounted:
	pass


func test_null_host_returns_the_default() -> void:
	assert_false(HostMethodHelper.try_call_bool(null, &"is_on_floor"), "null host + default default = false")
	assert_true(HostMethodHelper.try_call_bool(null, &"is_on_floor", true), "null host returns the caller's default, here true")


func test_missing_method_returns_the_default() -> void:
	var m := Mute.new()
	assert_false(HostMethodHelper.try_call_bool(m, &"is_on_floor"), "no such method = the default (false)")
	assert_true(HostMethodHelper.try_call_bool(m, &"is_on_floor", true), "no such method = the default (true) — the negated-read idiom relies on this")
	m = null


func test_present_method_result_wins_over_the_default() -> void:
	var h := Host.new()
	assert_true(HostMethodHelper.try_call_bool(h, &"is_on_floor", false), "a true answer beats a false default")
	h.flag = false
	assert_false(HostMethodHelper.try_call_bool(h, &"is_on_floor", true), "a false answer beats a true default — the default is ONLY for the can't-answer case")
	h = null


func test_non_bool_returns_are_coerced() -> void:
	var h := Host.new()
	assert_true(HostMethodHelper.try_call_bool(h, &"says_one"), "int 1 coerces to true")
	assert_false(HostMethodHelper.try_call_bool(h, &"says_zero", true), "int 0 coerces to false even against a true default")
	assert_true(HostMethodHelper.try_call_bool(h, &"says_float"), "a non-zero float coerces to true")
	h = null


func test_works_on_nodes_too() -> void:
	var n := Node.new()
	assert_true(HostMethodHelper.try_call_bool(n, &"is_inside_tree", true) == false, "a real engine method is called (an off-tree node is not inside the tree)")
	assert_true(HostMethodHelper.try_call_bool(n, &"no_such_method", true), "an engine object without the method still yields the default")
	n.free()
