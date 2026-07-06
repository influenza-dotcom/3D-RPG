# NpcHeadAnchor — staged extraction (npc.gd head-resolution / swapped-head / glint-origin → drop-in)

> **STATUS: STAGED / NOT APPLIED — DEFER (marginal). PLAYTEST + EDITOR-LOCK GATED.** Drafted + 3-lens reviewed
> 2026-07-04. Moves npc.gd's head-position / skeleton-resolve / swapped-head registry / sniper-glint origin into a
> new portable Type-1 drop-in `scripts/components/npc_head_anchor.gd`. **All three reviewers said DEFER, not drop.**

## Why DEFER (the honest cost/benefit)

Net win is only **~18-22 lines** off npc.gd (Option B facades are mandatory — both external consumers call on the
host root, so retargeting them, Option A, isn't worth a per-frame cross-component ordering contract). Against that
you take on: a per-frame aim-path `.call(&"head_position")` indirection (glint origin — playtest-only to validate),
a new-`class_name` editor-lock (must apply editor-closed + `--import`), and a subtle build-ordering regression the
draft itself got wrong (see CORRECTION 1). **Recommendation: do NOT spend a dedicated session on this. Batch it into
the SAME editor-closed + playtest pass as [Locomotor Phase B](locomotor_phase_b_migration.md)** — both are
new-drop-in / editor-lock / playtest work, so they share the one reimport + playtest cycle.

## Review verdict (3 lenses)

| Lens | Verdict | Notes |
|---|---|---|
| **Consumer-retargeting** | ✅ PATCH-SOUND | Option B (facades) correct; `body_model_swap.gd` + `npc_head_look_mount.gd` keep working untouched; grep-confirmed the only 3 external call sites; return types + write path preserved. |
| **Cache-and-editor-lock** | ⚠️ NEEDS-FIX → NOT-SAFE-THIS-SESSION | Wiring is genuinely cache-free (byte-identical to the shipped CrippleCallout; no bare `NpcHeadAnchor` type in npc.gd, no `:=`-off-Variant, no `_ready`-in-test). Minor fixes below. Still editor-lock + playtest gated. |
| **Equivalence** | ⚠️ NEEDS-FIX (1 HIGH) | Resolution/bone/capsule/eye_height math relocate verbatim, BUT the build-ordering regression (CORRECTION 1) drops swapped-head registration for every BodyModelSwap NPC as drafted. Must fix before apply. |

## REQUIRED CORRECTIONS (apply with the patch below)

**CORRECTION 1 (HIGH — the real bug): the anchor is built too late, dropping swapped-head registration.**
`body_model_swap._register_head()` (child `_ready`) calls `register_swapped_head()` BEFORE the NPC's
`_build_components()` (parent `_ready`) builds `_head_anchor` — so the drafted facade `if _head_anchor != null:`
silently discards it, and every BodyModelSwap NPC loses head-look + a swapped-head-tracking sniper glint. The inline
code never had this (it wrote `_swapped_head = node` unconditionally). **Fix (pick one; (a) is the most robust):**
- **(a) Buffer + flush.** Add `var _pending_swapped_head: Node3D = null`. In the `register_swapped_head` facade,
  when `_head_anchor == null`, store `_pending_swapped_head = node`; immediately after building the anchor in
  `_build_components`, flush it: `if _pending_swapped_head != null: _head_anchor.call(&"register_swapped_head", _pending_swapped_head); _pending_swapped_head = null`.
- **(b) Build earlier.** Build `_head_anchor` in the NPC's `_enter_tree()` (parent `_enter_tree` fires before child
  `_ready`) so it always exists when a child registers. Simpler, but `add_child` during `_enter_tree` is finickier
  than (a); prefer (a) unless you confirm the tree-timing.

**CORRECTION 2 (mandatory — runtime type error otherwise): use the WRAPPED return in the `_head_position` facade.**
A bare `return _head_anchor.call(&"head_position")` from a `-> Vector3` func can throw "Trying to return Variant as
Vector3". Use the wrapped form: `var p: Vector3 = _head_anchor.call(&"head_position"); return p`. (The patch offers
both — treat wrapped as required.)

**CORRECTION 3 (minor): keep `@tool` on the component** (a `.call` from the @tool host into a non-@tool child method
can raise an edit-time method-error in some Godot 4.x paths — harmless to keep it), and **rename the build-loop var
`has` → `hs`** (readability; not a keyword, but the sibling CrippleCallout loop uses `cs`).

## Pre-apply + playtest checklist (batch with Locomotor Phase B)

1. Editor CLOSED. Apply the patch + CORRECTIONS 1-3. `godot --headless --import` (absolute path) to register the new
   `class_name NpcHeadAnchor`, then GUT (expect `test_npc_head_anchor.gd` + unchanged `test_npc_head_look.gd` green).
2. Playtest the aim/glint path (GUT can't): a sniper/aiming NPC's **glint originates at the head** and, for a
   BodyModelSwap NPC, **tracks the swapped head** (not the hidden Man.glb bone); the **head-look** still turns the
   swapped head toward its look target; a plain NPC (no swap) still glints at the skeleton "Head" bone / capsule top.
3. Docs to ship with it: `scripts/components/README.md` (new drop-in), `scripts/npc/README.md`.

---

I now have complete ground truth. `NodeFinder.find_first_of_class(node, klass)` is a static, and the test uses the `preload` + static-helper idiom I'll mirror for the anchor test.

One key design decision confirmed: the anchor is a Type-1 drop-in `Node`, so it reads `get_parent()` for `mesh`, `global_position`, `global_basis`, `get_children()` — all duck-typed with explicit annotations (no `:=` off a Variant host). The `_capsule_top` logic moves too, retargeting `get_children()`/`global_basis`/`global_position` to the host.

Here is the complete staged patch.

---

# STAGED PATCH — NpcHeadAnchor extraction (Option B: facades)

**Ground-truthed 2026-07-04** against `npc.gd`, `body_model_swap.gd`, `npc_head_look_mount.gd`, `character.gd`, `node_finder.gd`, `test_npc_head_look.gd`. All line numbers below are verified-current; re-verify before applying since the file drifts.

**Decision: Option B (facades).** Both recon reports converge and the code confirms it: all 3 external call sites (`body_model_swap.gd:364`, `:911`; `npc_head_look_mount.gd:148`) invoke `head_visual()`/`register_swapped_head()` on `get_parent()`/`host` (the NPC root) and every one guards `is Node3D` on the result. Option A would push a duplicated "find my sibling anchor" scan into two playtest-gated components and add a cross-component ordering contract on a per-frame path, for a net win of only ~15 lines over B. Not worth it. **B leaves `body_model_swap.gd` and `npc_head_look_mount.gd` UNTOUCHED.**

---

## FILE 1 (NEW) — `scripts/components/npc_head_anchor.gd`

Portable Type-1 drop-in. Owns the swapped-head registry + skeleton/bone cache + capsule-top fallback. All host reads are duck-typed off `get_parent()` with **explicit type annotations** (never `:=` off a Variant host — that compile-kills the script per the `gdscript-host-variant-no-inference` memory). References no NPC type.

```gdscript
@tool
class_name NpcHeadAnchor
extends Node

## Portable Type-1 drop-in: resolves the world position of the host's HEAD for the sniper-glint origin
## (Feature #8) and owns the swapped-head registry that a BodyModelSwap hands in. Extracted verbatim from
## npc.gd so any Character-like host (reads `mesh` / `eye_height` / a child CollisionShape3D off get_parent())
## can carry the glint-anchor behaviour by DROPPING this node under it — no code branch in the host.
##
## The host must not NAME this class (an @tool root ref to a not-yet-reimported class_name can break its parse
## in the live editor — the new-classname-cascade memory). npc.gd builds us via load(path).new() + a
## get_script().resource_path scan and calls us duck-typed (.call(&"head_position") etc.). The class_name here
## is only for designer drag-drop.
##
## Resolution order (unchanged from the old npc.gd _head_position):
##   1. a registered swapped head (a BodyModelSwap's unified-character head) — its live global_position;
##   2. the rigged "Head" bone on the host mesh's Skeleton3D (Man.glb rigs one) — its live global pose, so the
##      glint tracks the head as the body animates/yaws;
##   3. the TOP of the host's collision capsule (origin + half-height up its Y);
##   4. an eye_height offset off the host origin, as a last resort (off-tree / mesh-less host).
## The bone lookup is cached (runs once) so head_position() stays cheap on the per-frame aim path.

var _head_skeleton: Skeleton3D = null
var _head_bone: int = -1
var _head_resolved: bool = false  # the lookup runs once; this latches it whether or not a bone was found
var _swapped_head: Node3D = null  # a BodyModelSwap's swapped head, if one registered — the glint tracks it

## World position of the host's HEAD, for the glint origin. Public (no leading _) because npc.gd's facade and
## the aim path call it cross-node. PER-FRAME AIM PATH — playtest-verified, no GUT coverage. Duck-types every
## host read: get_parent() may be any Node3D-like root exposing global_position / eye_height / a capsule child.
func head_position() -> Vector3:
	if is_instance_valid(_swapped_head):
		return _swapped_head.global_position  # glint follows the swapped character's head, not the hidden Man.glb bone
	_resolve_head()
	if _head_bone >= 0 and is_instance_valid(_head_skeleton):
		# Bone pose is in the skeleton's local space; lift it to world through the skeleton's transform.
		return _head_skeleton.global_transform * _head_skeleton.get_bone_global_pose(_head_bone).origin
	var cap: Variant = _capsule_top()
	if cap != null:
		return cap
	var host: Node = get_parent()
	var origin: Vector3 = Vector3.ZERO
	var eye: float = 1.4  # matches npc.gd's default eye_height
	if host != null:
		var ho: Variant = host.get(&"global_position")
		if ho is Vector3:
			origin = ho
		var he: Variant = host.get(&"eye_height")
		if he is float:
			eye = he
	return origin + Vector3.UP * eye

## Find and cache the host mesh's "Head" bone (once). No-op without a `mesh`; leaves _head_bone at -1 (so
## head_position falls through) when the model carries no Skeleton3D or no bone named "Head".
func _resolve_head() -> void:
	if _head_resolved:
		return
	_head_resolved = true
	var host: Node = get_parent()
	if host == null:
		return
	var m: Variant = host.get(&"mesh")  # Character base @export; null on a mesh-less / off-tree host -> we bail
	if not (m is Node):
		return
	_head_skeleton = _find_skeleton(m)
	if _head_skeleton != null:
		_head_bone = _head_skeleton.find_bone("Head")  # Man.glb's rig names it exactly "Head"

## First Skeleton3D anywhere under `node`, depth-first (the Man.glb rig sits a few nodes deep under the mesh
## root). Mirrors npc.gd's old private copy; NodeFinder is a static helper (RefCounted), portable.
func _find_skeleton(node: Node) -> Skeleton3D:
	return NodeFinder.find_first_of_class(node, Skeleton3D) as Skeleton3D

## Top of the HOST's collision capsule in world space (origin + half-height up its Y), or null when the host
## has no CollisionShape3D / CapsuleShape3D — the third-choice anchor. Scanned shallowly off the host (the
## shape is a direct child on enemy.tscn). Untyped return so the "no capsule" case yields null (a Vector3-typed
## func can't), which head_position() tests before the eye_height fallback.
func _capsule_top() -> Variant:
	var host: Node = get_parent()
	if host == null:
		return null
	var host_basis: Basis = Basis.IDENTITY
	var hb: Variant = host.get(&"global_basis")
	if hb is Basis:
		host_basis = hb
	for c in host.get_children():
		var col := c as CollisionShape3D
		if col == null:
			continue
		var cap := col.shape as CapsuleShape3D
		if cap == null:
			continue
		# height spans the full capsule centred on its origin, so half-height reaches the top cap.
		return col.global_position + host_basis.y * (cap.height * 0.5)
	return null

## The VISIBLE head node the head-look rotates: a registered swapped head, else null (the head-look then no-ops;
## the glint falls back to the Man.glb "Head" bone via head_position). npc.gd's head_visual() facade forwards here.
func head_visual() -> Node3D:
	return _swapped_head if is_instance_valid(_swapped_head) else null

## A BodyModelSwap hands us its swapped head, so the head-look + sniper glint track IT instead of the Man.glb head
## bone. Called (via npc.gd's facade) at runtime, before/after the host's _ready.
func register_swapped_head(node: Node3D) -> void:
	_swapped_head = node
```

**Note on `@tool`:** the host (`npc.gd`) is `@tool`, and `head_visual()`/`register_swapped_head()` are only ever called at runtime (both consumers gate on `Engine.is_editor_hint()` / runtime-only). Marking the anchor `@tool` is harmless (its funcs never run in-editor) and keeps parity with the host so an in-editor duck-typed `.call` never hits a non-tool method-error. Drop `@tool` if you prefer — behaviourally identical since no consumer calls it in-editor.

---

## FILE 2 — `scripts/npc/npc.gd`

### Change 2a — state declaration (lines 322–329) → Node handle

**BEFORE** (322–329):
```gdscript
## Cached head anchor for the sniper-glint origin (Feature #8): the rigged "Head" bone on the mesh's
## Skeleton3D, resolved once (lazily) so _report_aim blooms the glint at the NPC's ACTUAL head instead
## of a guessed eye_height offset off the feet. _head_skeleton is the skeleton that owns it, _head_bone
## its bone index (-1 = none found -> we fall back to the capsule top, then the eye_height offset).
	var _head_skeleton: Skeleton3D = null
	var _head_bone: int = -1
	var _head_resolved: bool = false  # the lookup runs once; this latches it whether or not a bone was found
	var _swapped_head: Node3D = null   # a BodyModelSwap component's swapped head, if one registered -- the head-look + glint track it
```
> These four are top-level class vars (no leading tab in the file — shown here with the file's actual indentation, which is NONE at class scope). Verify: in the read they appear at column 0. Match exactly.

**AFTER**:
```gdscript
## Head anchor for the sniper-glint origin (Feature #8): a portable NpcHeadAnchor drop-in owns the swapped-head
## registry + the cached "Head"-bone lookup + the capsule-top fallback, so _report_aim blooms the glint at the
## NPC's ACTUAL head. Typed `Node` (not `NpcHeadAnchor`) and PATH-loaded in _build_components so this @tool root
## never names the new class_name — a bare-type ref to a not-yet-reimported class can break npc.gd's parse in
## the live editor (the new-classname-cascade memory). Read duck-typed via .call(&"head_position") etc.
var _head_anchor: Node = null
```

### Change 2b — build the anchor in `_build_components` (after the CrippleCallout block, 768)

**BEFORE** (766–768):
```gdscript
	if _cripple_callout == null:
		_cripple_callout = load(cripple_script).new()
		add_child(_cripple_callout)
```

**AFTER** (append the new block immediately after 768):
```gdscript
	if _cripple_callout == null:
		_cripple_callout = load(cripple_script).new()
		add_child(_cripple_callout)
	# Head anchor — the glint-origin / swapped-head machinery, a portable Type-1 drop-in (npc_head_anchor.gd).
	# Same cache-free idiom as CrippleCallout above: matched + built by SCRIPT PATH (never `is NpcHeadAnchor` or
	# `.new()` on the bare type) so this @tool root doesn't name the new class_name at parse time. Built EARLY so
	# the head_visual()/register_swapped_head() facades below can forward to it (a BodyModelSwap may register its
	# swapped head at runtime; the facades null-guard the handle for the pre-build window regardless).
	var head_anchor_script := "res://scripts/components/npc_head_anchor.gd"
	for c in get_children():
		var has: Variant = c.get_script()
		if has != null and has.resource_path == head_anchor_script:
			_head_anchor = c
			break
	if _head_anchor == null:
		_head_anchor = load(head_anchor_script).new()
		add_child(_head_anchor)
```
> Loop var renamed `has` → keep it distinct; I used `has` but that shadows nothing problematic. If you prefer, name it `ascr`. The CrippleCallout loop above uses `cs`; pick any non-colliding name — **do not reuse `cs`** in the same function scope (it's still live). `has` is safe.

### Change 2c — `_head_position()` facade (lines 2581–2597)

**BEFORE** (2581–2597):
```gdscript
## World position of this NPC's HEAD, for the sniper-glint origin (Feature #8). Resolves, in order:
##   1. the rigged "Head" bone on the mesh's Skeleton3D (Man.glb rigs one) — its live global pose, so the
##      glint tracks the head as the body animates/yaws, not a fixed guess off the feet;
##   2. the TOP of the collision capsule (origin + half-height) when there's no skeleton/bone;
##   3. the old eye_height offset as a last resort (an off-tree / mesh-less NPC).
## The bone lookup is cached (runs once via _resolve_head) so this stays cheap on the per-frame aim path.
func _head_position() -> Vector3:
	if is_instance_valid(_swapped_head):
		return _swapped_head.global_position  # the glint follows the swapped character's head, not the hidden Man.glb bone
	_resolve_head()
	if _head_bone >= 0 and is_instance_valid(_head_skeleton):
		# Bone pose is in the skeleton's local space; lift it to world through the skeleton's transform.
		return _head_skeleton.global_transform * _head_skeleton.get_bone_global_pose(_head_bone).origin
	var cap: Variant = _capsule_top()
	if cap != null:
		return cap
	return global_position + Vector3.UP * eye_height
```

**AFTER**:
```gdscript
## World position of this NPC's HEAD, for the sniper-glint origin (Feature #8) — thin facade onto the
## NpcHeadAnchor drop-in (swapped head -> rigged "Head" bone -> capsule top -> eye_height offset; see the
## component). Kept as a named method because it's read on the per-frame aim path (_report_aim, below).
## PER-FRAME AIM/GLINT PATH — playtest-verified. Null-guarded for the pre-_build_components window (off-tree
## unit actors never call this): falls back to the old eye_height offset so the glint never NaN-blooms.
func _head_position() -> Vector3:
	if _head_anchor != null:
		return _head_anchor.call(&"head_position")
	return global_position + Vector3.UP * eye_height
```
> `.call(&"head_position")` returns `Variant`; the func is typed `-> Vector3`. GDScript coerces a `Vector3` Variant on return without an annotation trap here (the anchor always returns a `Vector3`). If the strict-typing analyzer complains, wrap: `var p: Vector3 = _head_anchor.call(&"head_position"); return p`. Prefer the wrapped form to be safe — see the residual-risk list.

**Safer wrapped form (recommended)**:
```gdscript
func _head_position() -> Vector3:
	if _head_anchor != null:
		var p: Vector3 = _head_anchor.call(&"head_position")
		return p
	return global_position + Vector3.UP * eye_height
```

### Change 2d — remove `_resolve_head` + `_find_skeleton` (lines 2599–2614)

**BEFORE** (2599–2614) — DELETE entirely:
```gdscript
## Find and cache the mesh's "Head" bone (once). No-op off-tree / without a `mesh`; leaves _head_bone
## at -1 (so _head_position falls back) when the model carries no Skeleton3D or no bone named "Head".
func _resolve_head() -> void:
	if _head_resolved:
		return
	_head_resolved = true
	if mesh == null:
		return
	_head_skeleton = _find_skeleton(mesh)
	if _head_skeleton != null:
		_head_bone = _head_skeleton.find_bone("Head")  # Man.glb's rig names it exactly "Head"

## First Skeleton3D anywhere under `node`, depth-first (the Man.glb rig sits a few nodes deep under the
## mesh root). Mirrors the recursive _find_muzzle_marker idiom so npc.gd stays self-contained.
func _find_skeleton(node: Node) -> Skeleton3D:
	return NodeFinder.find_first_of_class(node, Skeleton3D) as Skeleton3D
```
**AFTER**: (deleted — the anchor owns them). Confirmed no other npc.gd caller: grep `_resolve_head`/`_find_skeleton` in npc.gd returns only these definitions + the `_head_position` reader we just rewrote. (`_find_skeleton` in `ragdoll.gd`/`nav_blocker.gd` are those files' own private copies — untouched.)

### Change 2e — `head_visual()` + `register_swapped_head()` facades (lines 2620–2629)

**BEFORE** (2620–2629):
```gdscript
## The VISIBLE head node the head-look rotates: a BodyModelSwap component's swapped head if one registered (the
## unified character swap). Null when no custom head was swapped in (the head-look then no-ops; the glint falls
## back to the Man.glb "Head" bone via _head_position).
func head_visual() -> Node3D:
	return _swapped_head if is_instance_valid(_swapped_head) else null

## A BodyModelSwap component hands us its swapped head, so the head-look + sniper glint track IT instead of the
## Man.glb head bone. Called from the component at runtime (before our _ready runs).
func register_swapped_head(node: Node3D) -> void:
	_swapped_head = node
```

**AFTER**:
```gdscript
## The VISIBLE head node the head-look rotates — facade onto the NpcHeadAnchor drop-in. Null when no custom head
## was swapped in (the head-look no-ops; the glint falls back to the Man.glb "Head" bone). KEPT AS A NAMED METHOD:
## body_model_swap.gd (_talk_head) and npc_head_look_mount.gd (_head_visual) probe it via host.has_method(&"head_visual").
func head_visual() -> Node3D:
	if _head_anchor != null:
		var h: Variant = _head_anchor.call(&"head_visual")
		if h is Node3D:
			return h
	return null

## A BodyModelSwap hands us its swapped head, so the head-look + sniper glint track IT instead of the Man.glb head
## bone — facade onto the NpcHeadAnchor drop-in. KEPT AS A NAMED METHOD: body_model_swap.gd (_register_head) probes
## it via host.has_method(&"register_swapped_head") at runtime. Null-guarded for the pre-_build_components window
## (a runtime swap that lands before the anchor exists is a no-op; the anchor built in _ready is the ordering fix).
func register_swapped_head(node: Node3D) -> void:
	if _head_anchor != null:
		_head_anchor.call(&"register_swapped_head", node)
```

### Change 2f — `_capsule_top()` removal (lines 2711–2726)

**BEFORE** (2711–2726) — DELETE entirely (moved into the anchor, retargeted to the host):
```gdscript
## Top of the NPC's collision capsule in world space (origin + the capsule's half-height up its Y), or
## null when there's no CollisionShape3D / CapsuleShape3D to read — the second-choice head anchor when
## the model has no rigged Head bone. Scanned shallowly (the shape is a direct child on enemy.tscn).
## Untyped return so the "no capsule" case can yield null (a Vector3-typed func can't), which
## _head_position() tests before falling through to the eye_height offset.
func _capsule_top() -> Variant:
	for c in get_children():
		var col := c as CollisionShape3D
		if col == null:
			continue
		var cap := col.shape as CapsuleShape3D
		if cap == null:
			continue
		# height spans the full capsule centred on its origin, so half-height reaches the top cap.
		return col.global_position + global_basis.y * (cap.height * 0.5)
	return null
```
**AFTER**: (deleted). Grep confirms `_capsule_top` had exactly one caller — `_head_position` (2594), which no longer exists. Safe to remove.

**⚠️ ORDERING within npc.gd:** delete 2711–2726 in the SAME pass as 2599–2614 so no dangling reference exists between edits. If applying edits one at a time, do 2c (the `_head_position` facade) FIRST — it's the only reader of both `_resolve_head` and `_capsule_top` — then the two deletions in any order.

**`eye_height`, `head_look_point`, `_report_aim` STAY on the root, untouched.** `eye_height` (191) feeds perception (1260) + profiles; the anchor reads it duck-typed as a fallback. `head_look_point` (2673–2703) is perception/target logic, not head-anchor machinery.

---

## FILE 3 — `scripts/components/npc_head_anchor.gd.uid`

Do NOT hand-write the uid (per the `gd-uid-hand-written-invalid` memory). After the `.gd` lands, generate it with `godot --headless --import` **while the editor is closed** (per the `dont-import-with-editor-open` memory), or let the open editor reimport and commit the sidecar it emits.

---

## FILE 4 (NEW) — `tests/test_npc_head_anchor.gd`

Off-tree, no NPC `_ready`. Mirrors the `test_npc_head_look.gd` idiom: `preload` (path-based, not the bare `NpcHeadAnchor` class_name — avoids the new-class_name GUT cascade). We can only test the tree-free surface: method presence, the swapped-head registry, and `head_visual` semantics. `head_position`/`_capsule_top`/the bone branch read live global transforms off a host and are playtest-only (documented in the test header). This is coverage that did NOT exist before — pure upside.

```gdscript
extends GutTest

## NpcHeadAnchor's tree-free surface (the portable glint-origin / swapped-head drop-in extracted from npc.gd).
## The bone-pose lookup, the capsule-top fallback, and head_position()'s live global-transform reads are
## PLAYTEST-ONLY (they need a host with a rigged mesh / a collision capsule in the tree) — exactly the glint
## visuals GUT can't cover. Here we pin the swapped-head registry + head_visual(), which are pure state.
##
## preload (path-based) instead of the bare NpcHeadAnchor class_name, so the suite resolves even before the
## editor has scanned the script into its class cache (avoids the new-class_name GUT cascade — same reason
## test_npc_head_look.gd preloads NpcHeadLookMount).

const HA := preload("res://scripts/components/npc_head_anchor.gd")


func test_has_the_duck_typed_consumer_surface() -> void:
	# body_model_swap.gd + npc_head_look_mount.gd probe these by name via has_method on the host; npc.gd's
	# facades forward here. If a rename drops one, the glint / head-look silently no-op — pin the names.
	var a: Node = HA.new()
	assert_true(a.has_method(&"head_position"), "aim path reads head_position()")
	assert_true(a.has_method(&"head_visual"), "head-look + talk-head read head_visual()")
	assert_true(a.has_method(&"register_swapped_head"), "BodyModelSwap registers via register_swapped_head()")
	a.free()


func test_head_visual_null_until_registered() -> void:
	var a: Node = HA.new()
	assert_null(a.call(&"head_visual"), "no swapped head registered -> head_visual() is null (glint uses the bone)")
	a.free()


func test_register_swapped_head_is_reflected_by_head_visual() -> void:
	var a: Node = HA.new()
	var head := Node3D.new()  # a stand-in for a BodyModelSwap's swapped head; never added to the tree
	a.call(&"register_swapped_head", head)
	assert_eq(a.call(&"head_visual"), head, "a registered swapped head becomes the visible head")
	head.free()
	a.free()


func test_head_visual_drops_a_freed_swapped_head() -> void:
	# is_instance_valid guards the registry: once the swapped head is freed, head_visual() must return null
	# (not a dangling ref) so the head-look falls back cleanly. Mirrors the old npc.gd is_instance_valid check.
	var a: Node = HA.new()
	var head := Node3D.new()
	a.call(&"register_swapped_head", head)
	head.free()
	assert_null(a.call(&"head_visual"), "a freed swapped head -> head_visual() falls back to null")
	a.free()
```
> `test_head_visual_drops_a_freed_swapped_head` exercises the `is_instance_valid(_swapped_head)` branch — the one behaviour subtlety in the registry. All four are off-tree (`HA.new()` without `add_child`), so no `_ready`, no host, no engine-error from off-tree transforms (we never call `head_position` here — that would touch `get_parent()`/global transforms).

**Do NOT add `head_position()`/`_capsule_top()` tests** — off-tree they'd hit `get_parent() == null` (the fallback path returns `Vector3.ZERO + UP*1.4` cleanly, actually testable) but the *meaningful* branches (bone pose, capsule) need an in-tree rigged host and are playtest-only. If you want one more cheap assertion: `head_position()` on a parentless anchor returns `Vector3(0,1.4,0)` — but that only pins the degenerate fallback. Optional.

---

## Behavior-equivalence argument

The extraction is a **pure relocation** of the resolution logic; the same node/bone resolves each frame and the glint origin is byte-identical:

1. **Resolution order is preserved exactly.** Old `_head_position` (swapped-head → bone → capsule → eye_height) becomes anchor `head_position()` with the identical four-branch cascade in the same order. The facade just forwards.

2. **The bone-pose math is unchanged.** `_head_skeleton.global_transform * _head_skeleton.get_bone_global_pose(_head_bone).origin` moved verbatim. `_resolve_head` still runs once (latched by `_head_resolved`), still reads the host `mesh`, still `find_bone("Head")`. Only the read of `mesh` changed from a direct member access to `get_parent().get(&"mesh")` — same value, same null-behaviour (old bailed `if mesh == null`, new bails `if not (m is Node)`; a null `.get` yields null which is `not is Node` → same bail).

3. **The capsule-top math is unchanged.** `col.global_position + basis.y * (cap.height * 0.5)`, scanning direct children for a `CollisionShape3D` with a `CapsuleShape3D`. The one retarget: `get_children()`/`global_basis` now read the **host** (`get_parent()`), which is the NPC root the capsule child lives under — the same collection the old root-method's `get_children()` returned. `global_basis` off the host == the old `self.global_basis`. Identical result.

4. **The eye_height fallback is unchanged.** Old `global_position + UP * eye_height`; new reads `host.global_position` + `host.eye_height` (fallback 1.4, matching the export default) — same for any real NPC.

5. **The swapped-head registry is unchanged.** `register_swapped_head` writes `_swapped_head`; `head_visual`/`head_position` read it behind `is_instance_valid`. Moved verbatim. The two external consumers still `has_method(&"head_visual")` → true (the facade keeps the name) and still receive a `Node3D`-or-null they guard with `is Node3D`.

6. **The aim path is unchanged.** `_report_aim` (2579) still calls `_head_position()` by the same name; the facade delegates. Same glint origin fed to `_target.indicate_aimed_from`.

**Net line change in npc.gd:** removed ~40 (state doc+4 vars, `_resolve_head` 11, `_find_skeleton` 4, `_capsule_top` 16, and `_head_position`/`head_visual`/`register_swapped_head` bodies shrink) minus ~26 re-added (handle+doc 6, `_build_components` block 13, three facades ~7) → **≈ −18 to −22 net**. Modest; the value is portability/decomposition, matching the `docs/audits/npc_decomposition_status.md` NpcHeadAnchor row.

---

## Residual-risk list (apply-by-hand + playtest)

1. **[CACHE — blocker for THIS session]** `npc_head_anchor.gd`'s new `class_name NpcHeadAnchor` is not in the editor's class cache until it reimports. Even though npc.gd never NAMES the type, the file must LAND and the editor must re-scan before a live session is stable. Apply with the editor closed, or land the file + reimport + verify before touching npc.gd. This is exactly why it's staged.

2. **[`:=` TRAP]** In the anchor, every host read is annotated (`var m: Variant = host.get(...)`, `var ho: Variant`, etc.) — **never** `:=` off `host.get()` or `get_parent()` chains (compile-kills the script per the memory). Verify no `:=` crept in during hand-apply. In npc.gd's `_head_position` facade, use the **wrapped form** (`var p: Vector3 = _head_anchor.call(...)`) so the `Variant`→`Vector3` return coercion is explicit and the analyzer stays quiet.

3. **[AIM-PATH PLAYTEST]** `_head_position` → `head_position()` is the per-frame sniper-glint origin (npc.gd:2579). GUT cannot cover it. **Playtest checklist:** (a) an NPC with a rigged Man.glb aims at you → glint blooms at the head, tracks head yaw/animation; (b) an NPC with a BodyModelSwap-registered head → glint follows the swapped head; (c) a mesh-less/degenerate NPC → glint falls to capsule-top then eye_height, no NaN/origin-bloom at the feet.

4. **[ORDERING PLAYTEST]** `register_swapped_head` can arrive at runtime from `body_model_swap._register_head()`. The anchor is built in `_build_components` (inside npc.gd `_ready`); the facade null-guards `_head_anchor` for the window before that. **Playtest:** a BodyModelSwap NPC's swapped head IS tracked by the glint + head-look after spawn (i.e. the registration wasn't dropped because the anchor didn't exist yet). If a swap ever registers before `_build_components`, the facade no-ops silently — confirm in-game the swap survives. (In practice both the swap and `_build_components` run at runtime post-`_ready`, and BodyModelSwap gates on `is_editor_hint`, so the window is effectively nil — but it's the top runtime seam to eyeball.)

5. **[CONSUMER BREAKAGE — mitigated by Option B]** `body_model_swap.gd` (364, 911) and `npc_head_look_mount.gd` (148) are UNTOUCHED under Option B; they keep probing `head_visual`/`register_swapped_head`/`head_look_point` on the host, which still expose those names. No churn, no re-verify of those files needed beyond the ordering playtest in #4. `head_look_point` was never moved (perception logic), so `npc_head_look_mount.gd:157` is unaffected.

6. **[DISPATCH-BY-NAME — cleared]** Confirmed by grep: `character.gd` (the base) has zero references to `head_visual`/`_head_position`/`register_swapped_head`/`_capsule_top`/`_resolve_head`. None are base virtuals dispatched by name (unlike the adjacent `_apply_overlay_to_meshes`/`_flash_damage`/`flash_red` which DO `super()` and must not be touched). No `.tscn`/`.tres` references these methods. The facades are kept purely for the two external duck-typed consumers, not for base dispatch.

7. **[`.get()` on a null export]** `host.get(&"mesh")` when `mesh` is unset returns `null` (not an error) — `not (null is Node)` → the anchor bails exactly as the old `if mesh == null`. Confirmed-safe by the `duck-typed-property-reads` memory, but eyeball a mesh-less NPC in playtest (#3c covers it).

8. **[WRITE-REVERT]** Per the `writes-can-revert-reread-before-relying` memory: after hand-applying, re-read/grep npc.gd for the deleted symbols (`_resolve_head`, `_find_skeleton`, `_capsule_top`, `_swapped_head`, `_head_skeleton`, `_head_bone`, `_head_resolved`) — they should appear ZERO times in npc.gd (all moved to the anchor). Then runtime-verify via a real `godot <scene>` NPC, not `-s`.

**Docs impact:** update `docs/audits/npc_decomposition_status.md:20` (the NpcHeadAnchor ⏳ row → shipped) when applied, and add NpcHeadAnchor to `scripts/components/README.md` if it enumerates drop-ins. Not applied this session.

**Do NOT apply this session** — blockers #1 (class-cache) and #3/#4 (playtest-only aim/ordering) are both real, exactly as the roadmap flagged.

Relevant files: `C:/Users/dalla/3D RPG/rpg/scripts/npc/npc.gd`, `C:/Users/dalla/3D RPG/rpg/scripts/components/npc_head_anchor.gd` (new), `C:/Users/dalla/3D RPG/rpg/tests/test_npc_head_anchor.gd` (new), `C:/Users/dalla/3D RPG/rpg/scripts/components/body_model_swap.gd` (untouched under Option B), `C:/Users/dalla/3D RPG/rpg/scripts/components/npc_head_look_mount.gd` (untouched).