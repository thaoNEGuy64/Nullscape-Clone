-- ShadeServer.server.lua
-- ServerScriptService
-- Legacy auto-spawner intentionally disabled.
-- Shades are now spawned by requiring ServerScriptService.Enemies.ShadeModule
-- and calling ShadeModule.Spawn(position, options), so arena rooms can control
-- exactly when/how many Shades appear.

print("[SHADE] Legacy auto-spawn disabled; use Enemies.ShadeModule for arena spawns")
