-- Example weapon module: sword with placeholder slash/parry hooks

return {
	id = "Sword",
	displayName = "Sword",
	pickupModelName = "Sword",

	onEquip = function(ctx)
		print("[SWORD] Equipped")
	end,

	onUnequip = function(ctx)
		print("[SWORD] Unequipped")
	end,

	onPrimaryDown = function(ctx)
		print("[SWORD] Slash")
		-- TODO: add slash animation + server hit validation
	end,

	onSecondaryDown = function(ctx)
		print("[SWORD] Parry")
		-- TODO: add parry window + server state
	end,
}
