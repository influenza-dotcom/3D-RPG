class_name BootQuotes
extends Resource

## A designer-authored set of boot-intro quotes (res://resources/ui/boot_quotes.tres). The start menu picks one
## at random each game start for the black quote card. Add / edit / reorder entries right in the inspector — no
## code. (If this resource is ever missing or empty, the start menu falls back to a built-in quote, so the main
## menu always boots.)

## The pool of quotes. Add an element, then "New BootQuote", and fill its text + attribution.
@export var quotes: Array[BootQuote] = []

## A random quote, or null when the pool is empty (the caller then uses its built-in fallback).
func random() -> BootQuote:
	if quotes.is_empty():
		return null
	return quotes[randi() % quotes.size()]
