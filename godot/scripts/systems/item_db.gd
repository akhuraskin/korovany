class_name ItemDB
extends RefCounted
## Every item that can be bought, sold, looted or used.

const ITEMS := {
	"bandage": {"name": "Bandage", "price": 8, "desc": "Stops bleeding."},
	"potion": {"name": "Healing potion", "price": 25, "desc": "Restores 60 health."},
	"iron_sword": {"name": "Iron sword", "price": 60, "damage": 15.0, "slot": "weapon", "desc": "Damage 15."},
	"steel_sword": {"name": "Steel sword", "price": 160, "damage": 21.0, "slot": "weapon", "desc": "Damage 21."},
	"elven_blade": {"name": "Elven blade", "price": 140, "damage": 19.0, "slot": "weapon", "desc": "Light and sharp. Damage 19."},
	"black_blade": {"name": "Black blade", "price": 220, "damage": 25.0, "slot": "weapon", "desc": "Forged in the old fort. Damage 25."},
	"bow": {"name": "Hunting bow", "price": 90, "desc": "Right mouse button shoots arrows. Needs both hands."},
	"leather_armor": {"name": "Leather armor", "price": 50, "armor": 3.0, "slot": "armor", "desc": "Armor 3."},
	"chainmail": {"name": "Chainmail", "price": 170, "armor": 6.0, "slot": "armor", "desc": "Armor 6."},
	"prosthetic_arm": {"name": "Prosthetic arm", "price": 120, "prosthesis": "arm", "desc": "Replaces a lost arm."},
	"prosthetic_leg": {"name": "Prosthetic leg", "price": 110, "prosthesis": "leg", "desc": "Replaces a lost leg: walk and jump again."},
	"glass_eye": {"name": "Enchanted glass eye", "price": 90, "prosthesis": "eye", "desc": "Replaces a lost eye and restores sight."},
	"wheelchair": {"name": "Wheelchair", "price": 70, "desc": "Ride instead of crawling when a leg is lost."},
	"goods": {"name": "Caravan goods", "price": 35, "desc": "Trade goods. Sell them to a merchant."},
	"silk": {"name": "Bolt of silk", "price": 60, "desc": "Valuable cloth. Sell it to a merchant."},
}

const COMMON_STOCK := ["bandage", "potion", "leather_armor", "prosthetic_arm", "prosthetic_leg", "glass_eye", "wheelchair"]
const FACTION_STOCK := {
	0: ["iron_sword", "steel_sword", "chainmail", "bow"],
	1: ["iron_sword", "steel_sword", "chainmail"],
	2: ["elven_blade", "bow"],
	3: ["steel_sword", "black_blade", "chainmail"],
}


static func name_of(id: String) -> String:
	return ITEMS.get(id, {}).get("name", id)


static func price(id: String) -> int:
	return int(ITEMS.get(id, {}).get("price", 0))


static func sell_price(id: String) -> int:
	if id == "goods" or id == "silk":
		return price(id)
	return int(price(id) / 2.0)


static func stock_for(faction: int) -> Array:
	return COMMON_STOCK + FACTION_STOCK.get(faction, [])
