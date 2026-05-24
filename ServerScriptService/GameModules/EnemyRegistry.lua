local EnemyRegistry = {}

EnemyRegistry.Enemies = {
	Covet = { Tier = 1, LevelRequirement = 1, Enabled = true, Type = "Major", Health = 1000 },
	Nil = { Tier = 1, LevelRequirement = 1, Enabled = false, Type = "Major", Health = 1000 },
	Guardian = { Tier = 1, LevelRequirement = 1, Enabled = false, Type = "Major", Health = 1000 },
	Harbinger = { Tier = 1, LevelRequirement = 1, Enabled = true, Type = "Major", Health = 1000 },
	Shade = { Tier = 1, LevelRequirement = 1, Enabled = true, Type = "Minor", Health = 50, ArenaOnly = true },
}

function EnemyRegistry:GetEnemyData(name)
	return self.Enemies[name]
end

function EnemyRegistry:GetRandomEnemies(level, count)
	local pool = {}
	for name, data in pairs(self.Enemies) do
		local enabled = (data.Enabled ~= false)
		local reqLevel = tonumber(data.LevelRequirement) or 1
		if enabled and not data.ArenaOnly and (tonumber(level) or 1) >= reqLevel then
			table.insert(pool, name)
		end
	end
	for i = #pool, 2, -1 do
		local j = math.random(1, i)
		pool[i], pool[j] = pool[j], pool[i]
	end
	local out = {}
	for i = 1, math.min(count or 1, #pool) do
		table.insert(out, pool[i])
	end
	return out
end

return EnemyRegistry
