--[[
	TutorialDefinitions  (ModuleScript)
	Location: ReplicatedStorage/Shared/TutorialDefinitions

	The first-five-minutes flow. The server (TutorialService) advances steps when the
	listed events happen; the client (TutorialController) shows Title/Text.

	Events: BuildSaved, HandlerHit, Dodged, CommandAttack, AbilityUsed, EnemyDefeated,
	        TutorialBossWon, EquippedReward
]]

local TutorialDefinitions = {}

TutorialDefinitions.Steps = {
	{
		Id = "Assemble",
		Title = "EVERY NIGHTMARE STARTS SOMEWHERE.",
		Text = "Yours starts in pieces. Press B (or BUILD) to open the Workshop, give it a name, then press CREATE.",
		Needs = { "BuildSaved" },
	},
	{
		Id = "Train",
		Title = "Training",
		Text = "Walk to the Training Arena (north-east corner of the Forge, red lights). Hit a dummy (Left Click / ATTACK) and DIVE once (Shift / B button): you leap the way you're moving, untouchable mid-air.",
		Needs = { "HandlerHit", "Dodged" },
	},
	{
		Id = "Command",
		Title = "Command your Nightmare",
		Text = "Look at an enemy and press R (SIC) to send your Nightmare. Then press Q to use its special ability.",
		Needs = { "CommandAttack", "AbilityUsed" },
	},
	{
		Id = "Defeat",
		Title = "First blood",
		Text = "Defeat a Scrapling together!",
		Needs = { "EnemyDefeated" },
	},
	{
		Id = "Boss",
		Title = "The Scrap Titan stirs...",
		Text = "Follow the ORANGE path west out of the Forge, through the Rusted Expanse, to the Titan's Foundry. Use the altar at its gate to challenge the Scrap Titan. Watch for red circles!",
		Needs = { "TutorialBossWon" },
	},
	{
		Id = "Equip",
		Title = "Your first Rare part!",
		Text = "Open the Workshop (B), equip your new part on your ACTIVE Nightmare and press SAVE.",
		Needs = { "EquippedReward" },
	},
}

function TutorialDefinitions.IndexOf(id: string): number?
	for index, step in TutorialDefinitions.Steps do
		if step.Id == id then
			return index
		end
	end
	return nil
end

return TutorialDefinitions
