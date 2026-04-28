-- NPCWaypointFollower (Loader Script)
-- Location : Inside the NPC Model in ReplicatedStorage (cloned to Workspace by NPCSpawner).
-- Purpose  : Minimal loader that activates NPC waypoint pathing.
--
-- The main logic is now in: ReplicatedStorage.Shared.Modules.NPCWaypointFollower

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NPCWaypointFollower = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("NPCWaypointFollower"))

local npc = script.Parent
NPCWaypointFollower.start(npc)
