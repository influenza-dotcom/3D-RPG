class_name SettingsCatalog
extends Resource

## The ordered list of SettingSpec rows OptionsMenu builds its tabs from. Authored as
## resources/settings/SettingsCatalog.tres and preloaded by scripts/ui/options_menu.gd. Tabs appear in the
## order their first spec is seen; rows appear in spec order within each tab. See SettingSpec for the model.

@export var specs: Array[SettingSpec] = []
