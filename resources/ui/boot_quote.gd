class_name BootQuote
extends Resource

## One boot-intro quote shown on the black loading card. Author these on a BootQuotes resource
## (res://resources/ui/boot_quotes.tres); the start menu picks one at random each game start.

## The quote text. Press Enter for a hard line break (the card centres each line).
@export_multiline var text: String = ""
## Attribution shown below the quote (the card prefixes it with an em dash). e.g. Samuel "Bodyshot" Johnson.
@export var attribution: String = ""
