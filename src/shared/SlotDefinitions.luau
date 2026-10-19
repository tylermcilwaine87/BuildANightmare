--[[
	SlotDefinitions  (ModuleScript)
	Location: ReplicatedStorage/Shared/SlotDefinitions

	The seven functional build slots. "PartSlot" is which kind of part fits the slot
	(both arm slots accept "Arm" parts; the left arm is mirrored automatically).
]]

local SlotDefinitions = {}

SlotDefinitions.Order = { "Core", "Head", "LeftArm", "RightArm", "Legs", "Back", "Tail" }

SlotDefinitions.Info = {
	Core = { DisplayName = "Core / Body", PartSlot = "Core", Required = true },
	Head = { DisplayName = "Head", PartSlot = "Head", Required = true },
	LeftArm = { DisplayName = "Left Arm", PartSlot = "Arm", Required = false, Mirror = true },
	RightArm = { DisplayName = "Right Arm", PartSlot = "Arm", Required = false },
	Legs = { DisplayName = "Legs / Movement", PartSlot = "Legs", Required = true },
	Back = { DisplayName = "Back", PartSlot = "Back", Required = false },
	Tail = { DisplayName = "Tail", PartSlot = "Tail", Required = false },
}

return SlotDefinitions
