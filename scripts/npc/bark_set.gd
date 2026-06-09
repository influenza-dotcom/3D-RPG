class_name BarkSet
extends Resource

## Per-archetype combat/social BARK lines, carried by an NpcData profile (NpcData.bark_set). Each category
## defaults to EMPTY, which means "use the NPC's built-in default lines" — so a profile overrides only the
## categories it fills (a raider can have its own spot + death lines while inheriting the rest), and an NPC
## with no bark_set keeps every default. Lets a raider and a townsperson shout different lines, and opens the
## door to localization. Resolved per-category in NPC via _bark_pool / _pick_bark (empty -> the BARK_* const).

@export var spot: Array[String] = []            ## combat contact ("Contact!", "Enemy spotted!")
@export var hurt: Array[String] = []            ## low-HP ("I'm hit!")
@export var thanks: Array[String] = []           ## assist thanks ("Hey, thanks!")
@export var reload: Array[String] = []           ## reloading ("Cover me!")
@export var combat_end: Array[String] = []       ## target lost ("Where'd they go?")
@export var lost_interest: Array[String] = []    ## investigation gave up ("Must've imagined it.")
@export var greet: Array[String] = []            ## hover greeting ("Hey there.")
@export var death_ally: Array[String] = []       ## a co-aligned peer was killed ("Murderer!")
@export var death_approve: Array[String] = []    ## a friendly approves an enemy's death ("Good riddance!")
@export var death_question: Array[String] = []   ## a bystander questions a death ("Was that necessary?")
