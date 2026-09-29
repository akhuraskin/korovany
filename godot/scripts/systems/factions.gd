class_name Factions
extends RefCounted
## Faction ids, names and the base hostility table.

const HUMANS := 0   # neutral people, traders and caravans
const EMPIRE := 1   # Emperor's palace guard
const ELVES := 2    # forest elves
const VILLAIN := 3  # the Villain (name not invented yet) and his army

const NAMES := ["Humans", "Palace Guard", "Forest Elves", "Villain's Army"]
const ZONE_NAMES := ["Human lands (neutral)", "Emperor's lands", "Elven forest", "Villain's mountains"]
const COLORS := [
	Color(0.85, 0.72, 0.45),
	Color(0.85, 0.2, 0.2),
	Color(0.3, 0.75, 0.3),
	Color(0.6, 0.3, 0.75),
]


static func hostile(a: int, b: int) -> bool:
	if a == b:
		return false
	# Humans are neutral: nobody attacks them unless provoked.
	if a == HUMANS or b == HUMANS:
		return false
	# Palace, elves and the Villain are all at war with each other.
	return true
