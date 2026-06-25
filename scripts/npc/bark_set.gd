class_name BarkSet
extends Resource

## Per-archetype combat/social BARK lines, carried by an NpcData profile (NpcData.bark_set). Each category
## defaults to EMPTY, which means "use the NPC's built-in default lines" — so a profile overrides only the
## categories it fills (a raider can have its own spot + death lines while inheriting the rest), and an NPC
## with no bark_set keeps every default. Lets a raider and a townsperson shout different lines, and opens the
## door to localization. Resolved per-category in NPC via _bark_pool / _pick_bark (empty -> the BARK_* const).

@export_group("Combat")
@export var spot: Array[String] = []            ## combat contact ("Contact!", "Enemy spotted!")
@export var hurt: Array[String] = []            ## low-HP ("I'm hit!")
@export var reload: Array[String] = []           ## reloading ("Cover me!")
@export var combat_end: Array[String] = []       ## target lost ("Where'd they go?")
@export var lost_interest: Array[String] = []    ## investigation gave up ("Must've imagined it.")
@export var search: Array[String] = []           ## actively searching/hunting a lost target ("Where are you?")
@export var flee: Array[String] = []             ## broke and ran under fire ("Forget this!")
@export var check_body: Array[String] = []       ## spotted a dead body ("Hey -- a body!")

@export_group("Social")
@export var greet: Array[String] = []            ## hover greeting ("Hey there.")
@export var thanks: Array[String] = []           ## assist thanks ("Hey, thanks!")

@export_group("Death Reactions")
@export var death_ally: Array[String] = []       ## a co-aligned peer was killed ("Murderer!")
@export var death_approve: Array[String] = []    ## a friendly approves an enemy's death ("Good riddance!")
@export var death_question: Array[String] = []   ## a bystander questions a death ("Was that necessary?")

@export_group("Player Aggression")
@export var warn_attack: Array[String] = []      ## the player hit us but DIDN'T aggro us ("Cut that out!")
@export var aggro: Array[String] = []            ## the player's attack just flipped us hostile ("Alright, that does it!")

@export_group("Music reactions")
## Said when an idle NPC hears a playing radio, keyed to the song-quality TIER (jukebox; gated by
## GameSettings.npc_ai.music_reactions). Each EMPTY category falls back to the NPC's built-in MUSIC_*_LINES
## defaults, so a profile overrides only the tiers it fills — same inherit-or-default rule as every category above.
@export var music_awful: Array[String] = []      ## an awful tune ("Ugh, turn that off.")
@export var music_meh: Array[String] = []        ## mediocre ("Eh, it's alright.")
@export var music_good: Array[String] = []       ## good ("Oh, nice tune.")
@export var music_great: Array[String] = []      ## great ("This is my JAM!")
