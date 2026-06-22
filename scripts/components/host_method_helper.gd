class_name HostMethodHelper
extends RefCounted

## Duck-typed host probe (static-only). Calls `method` on a possibly-null / possibly-method-less object and coerces
## the result to bool, falling back to `default` when the object is null or lacks the method. Replaces the scattered
## `obj.has_method(&"x") and bool(obj.call(&"x"))` idiom with one call.
##
## For a NEGATED read, pick the default that preserves the no-method case. e.g. the old
## `airborne = obj.has_method(&"is_on_floor") and not bool(obj.call(&"is_on_floor"))` (false when absent) becomes
## `airborne = not try_call_bool(obj, &"is_on_floor", true)`.
static func try_call_bool(obj: Object, method: StringName, default: bool = false) -> bool:
	if obj != null and obj.has_method(method):
		return bool(obj.call(method))
	return default
