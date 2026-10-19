--[[
	ArchetypeDefinitions  (ModuleScript)
	Location: ReplicatedStorage/Shared/ArchetypeDefinitions

	Movement archetypes. The equipped Legs part decides the archetype.

	HitboxSize is the ONLY combat hitbox a Nightmare has. Visual parts never collide or
	register hits, so resizing/rotating parts in the workshop can never change how easy a
	Nightmare is to hit (fairness rule from the spec).

	Phase 3 adds Quadruped, Spider and Heavy Mechanical here.
]]

local ArchetypeDefinitions = {
	Biped = {
		DisplayName = "Biped",
		MaxHealth = 350,
		AttackPower = 100,
		Defence = 0,
		MoveSpeed = 16,
		AttackSpeed = 100,
		Reach = 5,
		HitboxSize = Vector3.new(4, 5, 3),
		CoreHeight = 0, -- core centre relative to the hitbox centre
		MinHipHeight = 0.5,
		HoverHeight = 0,
	},
	Quadruped = {
		DisplayName = "Quadruped",
		MaxHealth = 340,
		AttackPower = 100,
		Defence = 0,
		MoveSpeed = 18,
		AttackSpeed = 100,
		Reach = 5,
		HitboxSize = Vector3.new(4, 4, 5), -- low and long
		CoreHeight = 0,
		MinHipHeight = 0.5,
		HoverHeight = 0,
	},
	Floating = {
		DisplayName = "Floating",
		MaxHealth = 310,
		AttackPower = 100,
		Defence = 0,
		MoveSpeed = 17,
		AttackSpeed = 100,
		Reach = 5,
		HitboxSize = Vector3.new(4, 4, 4),
		CoreHeight = 0,
		MinHipHeight = 0.5,
		HoverHeight = 2.5, -- extra air gap under the lowest visual part
	},
}

return ArchetypeDefinitions
