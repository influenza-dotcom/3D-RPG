class_name NpcData
extends Resource

## A reusable NPC ARCHETYPE profile — the data-driven alternative to hand-overriding ~40 inspector fields on
## every enemy instance. Assign one to an NPC's `profile` export and `NPC._apply_profile()` stamps these
## values onto the NPC in _ready, BEFORE it reads its config. Author archetypes once in resources/characters/
## (raider, townsperson, sniper, shopkeeper) and reuse them, exactly like Faction.tres / WeaponData — instead
## of reassembling each enemy by hand (today Level.tscn's "Psycho Sniper" carries ~30 inline overrides).
##
## EITHER/OR by design: a profiled NPC is driven ENTIRELY by its profile (assign a profile XOR tune inline);
## to vary one stat, author a variant .tres. An NPC with NO profile keeps its inline exports unchanged, so
## every existing scene is unaffected.
##
## NOTE: threat_response is an int (@export_enum), NOT NPC.ThreatResponse — typing it as the NPC enum would
## form an NpcData <-> NPC class-compile cycle (NPC already references NpcData via its `profile` export). The
## int maps 1:1 onto NPC.ThreatResponse (0 = FIGHT, 1 = FLEE). Bark lines are a separate BarkSet (added next);
## this resource is the tuning layer.

@export var display_name: String = ""

@export_group("Vitals & outline")
@export var max_hp: float = 10.0
@export var has_outline: bool = true
@export var outline_color: Color = Color.BLACK
@export var outline_width: float = 0.085

@export_group("Hostility")
@export var faction: Faction = null
@export var disposition: Disposition.Kind = Disposition.Kind.HOSTILE
@export var disposition_overrides_faction: bool = false
@export var friendly_aggro_threshold: float = 8.0

@export_group("Weapon")
@export var weapon_data: WeaponData = null
@export var muzzle_offset: Vector3 = Vector3(0.0, 0.0, 0.0)
@export var weapon_mesh_rotation: Vector3 = Vector3(0.0, -90.0, 0.0)
@export var rate_of_fire_factor: float = 1.0
@export var miss_chance: float = 0.0
@export var fire_range: float = 30.0
@export var target_height: float = 0.0
@export var immune_to_weapon_knockback: bool = false
@export var starts_unloaded: bool = false

@export_group("Perception")
@export var sight_range: float = 25.0
@export var fov_degrees: float = 110.0
@export var time_to_detect: float = 1.0
@export var forget_time: float = 4.0
@export var eye_height: float = 1.4
@export var hearing: bool = true
@export var turn_speed: float = 8.0

@export_group("Laser")
@export var show_laser: bool = true
@export var laser_color: Color = Color(1.0, 0.1, 0.1)

@export_group("Movement")
@export var move_speed: float = 4.0
@export var move_accel: float = 25.0
@export var air_accel: float = 2.0
@export var engage_range_fraction: float = 0.9
@export var jump_velocity: float = 10.0
@export var dodge_interval: float = 2.5
@export_range(0.0, 1.0) var dodge_chance: float = 0.5
@export var dodge_duration: float = 0.35
@export var dodge_speed_fraction: float = 1.0

@export_group("Behavior")
## FIGHT = engage and shoot; FLEE = run away and never fire. Maps 1:1 onto NPC.ThreatResponse (0/1).
@export_enum("Fight", "Flee") var threat_response: int = 0
@export var temperament: float = 0.0
@export var wanders: bool = false
@export var wander_radius: float = 6.0
@export var wander_dwell_min: float = 1.5
@export var wander_dwell_max: float = 4.0
@export var flee_distance: float = 12.0
@export var talk_approach_distance: float = 2.5
@export var talk_approach_timeout: float = 4.0

@export_group("Barks")
## Optional per-archetype bark lines. Each category left empty falls back to the NPC's built-in defaults, so
## a profile overrides only the lines it cares about. Null = the NPC uses all its default lines.
@export var bark_set: BarkSet = null
