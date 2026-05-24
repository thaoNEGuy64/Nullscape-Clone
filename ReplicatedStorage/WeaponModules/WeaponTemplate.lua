-- Weapon module contract template
-- Drop new weapon modules into ReplicatedStorage/WeaponModules.

return {
	id = "TemplateWeapon", -- unique id, used by pickup model attribute/name
	displayName = "Template Weapon",
	pickupModelName = "TemplateWeapon", -- world model name fallback

	-- Optional lifecycle callbacks:
	onEquip = function(ctx)
		-- ctx.player, ctx.character, ctx.rootPart, ctx.workspace, ctx.remotes.enemyDamage
	end,
	onUnequip = function(ctx)
	end,

	-- Optional input callbacks:
	onPrimaryDown = function(ctx)
		-- e.g. slash start
	end,
	onPrimaryUp = function(ctx)
	end,
	onSecondaryDown = function(ctx)
		-- e.g. parry start
	end,
	onSecondaryUp = function(ctx)
	end,
}
