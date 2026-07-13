@tool
class_name HazardZone
extends Area3D

## A drop-in HAZARD ZONE (SE-2): while a body stands in this volume it takes periodic damage (fire, acid,
## radiation, a gas cloud) and optionally a status effect. Drop the area over a region, give it a CollisionShape3D,
## and set damage_per_tick + tick_interval (+ an optional on_tick_effect StatusEffect). AMBIENT by design — the
## damage is attributed to NO ONE (attacker = null), so standing in fire never provokes a faction or credits a
## kill. The "stand in fire and take ticks" verb; pushing/throwing a body into it (knockback) is free.

## Bodies in `damage_group` take the tick. Empty = ANY body with take_damage (the default — fire burns everything).
@export var damage_group: StringName = &""
## HP removed per tick from each body inside. 0 = no damage (a status-only zone).
@export var damage_per_tick: float = 1.0
## Seconds between ticks. The first tick lands one interval after entering.
@export var tick_interval: float = 0.5
## OPTIONAL status applied to a Character on each tick (burning / poison / slow) — uses CT-3's apply_status_effect.
## It refreshes by id, so it lingers a beat after you leave the zone. Null = damage only.
@export var on_tick_effect: StatusEffect = null

var _bodies: Array[Node] = []  ## bodies currently overlapping (added on enter, removed on exit / when freed)
var _tick_t: float = 0.0

func _ready() -> void:
	if Engine.is_editor_hint():
		return  # @tool: only the configuration warning runs in-editor; the ticking is runtime-only
	# Detect a body on ANY physics layer + filter by group (matches AudioZone / TriggerVolume), so the designer
	# never has to match mask numbers.
	collision_mask = 0xFFFFFFFF
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node) -> void:
	if _qualifies(body) and not _bodies.has(body):
		_bodies.append(body)

func _on_body_exited(body: Node) -> void:
	_bodies.erase(body)

## A body the zone damages: able to take_damage AND in damage_group (or any body, when the group is blank).
func _qualifies(body: Node) -> bool:
	if body == null or not body.has_method(&"take_damage"):
		return false
	return damage_group == &"" or body.is_in_group(damage_group)

func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _bodies.is_empty():
		return
	# Freeze hazard ticking (damage + on_tick_effect status application) for a control-locked body during a
	# cinematic (C34). Placed AFTER the editor-hint guard so this @tool node stays inert in-editor; placed BEFORE
	# `_tick_t += delta` so there's no catch-up burst when the cinematic ends (the accumulator doesn't advance).
	if InputManager.world_frozen():
		return
	_tick_t += delta
	if _tick_t < tick_interval:
		return
	_tick_t = 0.0
	_apply_tick()

## Damage (+ optionally status) every overlapping body. AMBIENT: attacker = null, so it never provokes / credits.
## Freed or invalid bodies are pruned. Split out so a test can drive it without a physics frame.
func _apply_tick() -> void:
	for i in range(_bodies.size() - 1, -1, -1):
		var body := _bodies[i]
		if not is_instance_valid(body):
			_bodies.remove_at(i)
			continue
		if damage_per_tick > 0.0:
			body.take_damage(damage_per_tick, false, null)  # null attacker = ambient (no provoke / no kill credit)
		if on_tick_effect != null and body is Character:
			(body as Character).apply_status_effect(on_tick_effect)

func _get_configuration_warnings() -> PackedStringArray:
	for c in get_children():
		if c is CollisionShape3D or c is CollisionPolygon3D:
			return PackedStringArray()
	return PackedStringArray(["HazardZone needs a CollisionShape3D child — the volume that detects bodies."])
