local Mock = require("tests.wow_mock")

local function makeVec(name, class, buffs, extra)
	local bMap = {}
	for famID, cfg in pairs(buffs or {}) do
		local rank = cfg.rank or 6
		local tal = cfg.talent or 0
		local grp = cfg.hasGroup ~= false
		local score = cfg.score or ((rank * 10) + (grp and 15 or 0) + (tal * 25))
		bMap[famID] = {
			familyID = famID,
			known = true,
			bestSingleRank = rank,
			talentRank = tal,
			hasGroup = grp,
			priorityScore = score,
		}
	end
	return {
		name = name,
		guid = "GUID-" .. name,
		class = class,
		source = "LBB",
		buffs = bMap,
		auras = (extra and extra.auras) or {},
		totems = (extra and extra.totems) or {},
	}
end

describe("Negotiator (Deterministic Multi-Caster Consensus Solver)", function()
	local env, LBB

	before_each(function()
		env = Mock.New()
		env:Install()
		LBB = env:LoadCore()
	end)

	it("splits 2 Priests by buff family (Imp. Fort takes Fortitude; Spirit Priest takes Divine Spirit & Shadow Prot)", function()
		local roster = {
			{ name = "TankOne",   unit = "raid1", class = "WARRIOR", subgroup = 1, role = "TANK" },
			{ name = "RogueOne",  unit = "raid2", class = "ROGUE",   subgroup = 1, role = "DAMAGER" },
			{ name = "PriestA",   unit = "raid3", class = "PRIEST",  subgroup = 2, role = "HEALER" },
			{ name = "PriestB",   unit = "raid4", class = "PRIEST",  subgroup = 2, role = "HEALER" },
			{ name = "MageOne",   unit = "raid5", class = "MAGE",    subgroup = 3, role = "DAMAGER" },
		}
		LBB.Assignments:SetRoster(roster)

		local caps = {
			-- PriestB has 2/2 Imp. Fortitude; PriestA has 0/2 Imp. Fortitude + Divine Spirit
			PriestA = makeVec("PriestA", "PRIEST", {
				FORTITUDE = { rank = 6, talent = 0, hasGroup = true },
				SPIRIT = { rank = 4, talent = 1, hasGroup = true },
				SHADOW_PROT = { rank = 3, talent = 0, hasGroup = true },
			}),
			PriestB = makeVec("PriestB", "PRIEST", {
				FORTITUDE = { rank = 6, talent = 2, hasGroup = true },
				SHADOW_PROT = { rank = 3, talent = 0, hasGroup = true },
			}),
		}

		LBB.Negotiator.Solve(LBB.Assignments.roster, caps, LBB.Assignments)

		-- PriestB owns Fortitude across all 3 active subgroups
		for _, sg in ipairs({ 1, 2, 3 }) do
			assert.are.equal("PriestB", LBB.Assignments:GetGroupBuff("FORTITUDE", sg).caster)
		end

		-- PriestA owns Divine Spirit on mana subgroups (2, 3) and NOT pure melee subgroup (1)
		assert.is_nil(LBB.Assignments:GetGroupBuff("SPIRIT", 1))
		assert.are.equal("PriestA", LBB.Assignments:GetGroupBuff("SPIRIT", 2).caster)
		assert.are.equal("PriestA", LBB.Assignments:GetGroupBuff("SPIRIT", 3).caster)

		-- PriestA also takes Shadow Protection across all 3 subgroups
		for _, sg in ipairs({ 1, 2, 3 }) do
			assert.are.equal("PriestA", LBB.Assignments:GetGroupBuff("SHADOW_PROT", sg).caster)
		end
	end)

	it("partitions 8 raid subgroups evenly across 3 Priests (Groups 1-3, 4-6, 7-8) deterministically", function()
		local roster = {}
		for sg = 1, 8 do
			table.insert(roster, { name = "Member" .. sg, unit = "raid" .. sg, class = "MAGE", subgroup = sg })
		end
		table.insert(roster, { name = "PriestAlpha", unit = "raid9",  class = "PRIEST", subgroup = 1 })
		table.insert(roster, { name = "PriestBeta",  unit = "raid10", class = "PRIEST", subgroup = 2 })
		table.insert(roster, { name = "PriestGamma", unit = "raid11", class = "PRIEST", subgroup = 3 })
		LBB.Assignments:SetRoster(roster)

		local caps = {
			PriestAlpha = makeVec("PriestAlpha", "PRIEST", { FORTITUDE = { rank = 6, talent = 2 }, SPIRIT = { rank = 4, talent = 1 } }),
			PriestBeta  = makeVec("PriestBeta",  "PRIEST", { FORTITUDE = { rank = 6, talent = 1 }, SPIRIT = { rank = 4, talent = 1 } }),
			PriestGamma = makeVec("PriestGamma", "PRIEST", { FORTITUDE = { rank = 6, talent = 0 } }),
		}

		LBB.Negotiator.Solve(LBB.Assignments.roster, caps, LBB.Assignments)

		-- Fortitude split: Alpha (1,2,3), Beta (4,5,6), Gamma (7,8)
		assert.are.equal("PriestAlpha", LBB.Assignments:GetGroupBuff("FORTITUDE", 1).caster)
		assert.are.equal("PriestAlpha", LBB.Assignments:GetGroupBuff("FORTITUDE", 2).caster)
		assert.are.equal("PriestAlpha", LBB.Assignments:GetGroupBuff("FORTITUDE", 3).caster)
		assert.are.equal("PriestBeta",  LBB.Assignments:GetGroupBuff("FORTITUDE", 4).caster)
		assert.are.equal("PriestBeta",  LBB.Assignments:GetGroupBuff("FORTITUDE", 5).caster)
		assert.are.equal("PriestBeta",  LBB.Assignments:GetGroupBuff("FORTITUDE", 6).caster)
		assert.are.equal("PriestGamma", LBB.Assignments:GetGroupBuff("FORTITUDE", 7).caster)
		assert.are.equal("PriestGamma", LBB.Assignments:GetGroupBuff("FORTITUDE", 8).caster)

		-- Spirit only split across the 2 Priests who actually know Divine Spirit (Alpha 1-4, Beta 5-8)
		for sg = 1, 4 do
			assert.are.equal("PriestAlpha", LBB.Assignments:GetGroupBuff("SPIRIT", sg).caster)
		end
		for sg = 5, 8 do
			assert.are.equal("PriestBeta", LBB.Assignments:GetGroupBuff("SPIRIT", sg).caster)
		end
	end)

	it("handles solo / mixed addon groups by assigning full known coverage to the sole LBB caster", function()
		local roster = {
			{ name = "SoloDruid",  unit = "raid1", class = "DRUID",   subgroup = 1, role = "HEALER" },
			{ name = "NoAddonDru", unit = "raid2", class = "DRUID",   subgroup = 2, role = "DAMAGER" },
			{ name = "MainTank",   unit = "raid3", class = "WARRIOR", subgroup = 2, role = "TANK" },
		}
		LBB.Assignments:SetRoster(roster)

		-- Only SoloDruid advertises capabilities
		local caps = {
			SoloDruid = makeVec("SoloDruid", "DRUID", {
				MOTW = { rank = 7, talent = 5, hasGroup = true },
				THORNS = { rank = 6, talent = 0, hasGroup = false },
			}),
		}

		LBB.Negotiator.Solve(LBB.Assignments.roster, caps, LBB.Assignments)

		assert.are.equal("SoloDruid", LBB.Assignments:GetGroupBuff("MOTW", 1).caster)
		assert.are.equal("SoloDruid", LBB.Assignments:GetGroupBuff("MOTW", 2).caster)
		assert.are.equal("SoloDruid", LBB.Assignments:GetTargetBuff("THORNS", "MainTank").caster)
	end)

	it("preserves manual locked = true overrides during re-negotiation", function()
		local roster = {
			{ name = "PriestA", unit = "raid1", class = "PRIEST", subgroup = 1 },
			{ name = "PriestB", unit = "raid2", class = "PRIEST", subgroup = 2 },
		}
		LBB.Assignments:SetRoster(roster)

		local caps = {
			PriestA = makeVec("PriestA", "PRIEST", { FORTITUDE = { rank = 6, talent = 0 } }),
			PriestB = makeVec("PriestB", "PRIEST", { FORTITUDE = { rank = 6, talent = 2 } }),
		}

		-- Raid leader manually locks PriestA onto Group 1 Fortitude
		LBB.Assignments:SetGroupBuff("FORTITUDE", 1, "PriestA", true)

		LBB.Negotiator.Solve(LBB.Assignments.roster, caps, LBB.Assignments)

		-- Locked Group 1 MUST remain PriestA with locked = true; unlocked Group 2 gets PriestB
		local g1 = LBB.Assignments:GetGroupBuff("FORTITUDE", 1)
		local g2 = LBB.Assignments:GetGroupBuff("FORTITUDE", 2)
		assert.are.equal("PriestA", g1.caster)
		assert.is_true(g1.locked)
		assert.are.equal("PriestB", g2.caster)
		assert.is_false(g2.locked)
	end)

	it("assigns non-overlapping Shaman 4-totem sets by Melee vs Caster party role", function()
		local allTotems = {
			EARTH = { STRENGTH_OF_EARTH = { id = "STRENGTH_OF_EARTH" }, STONESKIN = { id = "STONESKIN" }, TREMOR = { id = "TREMOR" } },
			FIRE  = { FLAMETONGUE = { id = "FLAMETONGUE" }, SEARING = { id = "SEARING" }, FROST_RES_TOTEM = { id = "FROST_RES_TOTEM" } },
			WATER = { MANA_SPRING = { id = "MANA_SPRING" }, HEALING_STREAM = { id = "HEALING_STREAM" } },
			AIR   = { WINDFURY = { id = "WINDFURY" }, GRACE_OF_AIR = { id = "GRACE_OF_AIR" }, TRANQUIL_AIR = { id = "TRANQUIL_AIR" } },
		}

		local roster = {
			-- Subgroup 1: Melee party with 2 Shamans
			{ name = "War1",    unit = "raid1", class = "WARRIOR", subgroup = 1 },
			{ name = "Rog1",    unit = "raid2", class = "ROGUE",   subgroup = 1 },
			{ name = "ShamA",   unit = "raid3", class = "SHAMAN",  subgroup = 1 },
			{ name = "ShamB",   unit = "raid4", class = "SHAMAN",  subgroup = 1 },
			-- Subgroup 2: Caster party with 1 Shaman
			{ name = "Mage1",   unit = "raid5", class = "MAGE",    subgroup = 2 },
			{ name = "Lock1",   unit = "raid6", class = "WARLOCK", subgroup = 2 },
			{ name = "Priest1", unit = "raid7", class = "PRIEST",  subgroup = 2 },
			{ name = "ShamC",   unit = "raid8", class = "SHAMAN",  subgroup = 2 },
		}
		LBB.Assignments:SetRoster(roster)

		local caps = {
			ShamA = makeVec("ShamA", "SHAMAN", {}, { totems = allTotems }),
			ShamB = makeVec("ShamB", "SHAMAN", {}, { totems = allTotems }),
			ShamC = makeVec("ShamC", "SHAMAN", {}, { totems = allTotems }),
		}

		LBB.Negotiator.Solve(LBB.Assignments.roster, caps, LBB.Assignments)

		local tA = LBB.Assignments:GetShamanTotems(1, "ShamA")
		local tB = LBB.Assignments:GetShamanTotems(1, "ShamB")
		local tC = LBB.Assignments:GetShamanTotems(2, "ShamC")

		-- Melee group ShamA gets primary melee set; ShamB gets distinct non-overlapping secondary totems
		assert.are.equal("STRENGTH_OF_EARTH", tA.EARTH)
		assert.are.equal("WINDFURY", tA.AIR)
		assert.are_not.equal(tA.EARTH, tB.EARTH)
		assert.are_not.equal(tA.FIRE, tB.FIRE)
		assert.are_not.equal(tA.WATER, tB.WATER)
		assert.are_not.equal(tA.AIR, tB.AIR)
		assert.are.equal("GRACE_OF_AIR", tB.AIR)

		-- Caster group ShamC gets caster preset (Stoneskin + Tranquil Air)
		assert.are.equal("STONESKIN", tC.EARTH)
		assert.are.equal("TRANQUIL_AIR", tC.AIR)
	end)

	it("distributes distinct Paladin Blessings by talent priority and yields when pallyPowerYield is true", function()
		local roster = {
			{ name = "PallyKings", unit = "raid1", class = "PALADIN", subgroup = 1 },
			{ name = "PallyMight", unit = "raid2", class = "PALADIN", subgroup = 1 },
			{ name = "WarTank",    unit = "raid3", class = "WARRIOR", subgroup = 1 },
		}
		LBB.Assignments:SetRoster(roster)

		local caps = {
			PallyKings = makeVec("PallyKings", "PALADIN", {
				BOK = { rank = 1, talent = 1 },
				BOM = { rank = 7, talent = 0 },
				BOW = { rank = 6, talent = 2 },
			}),
			PallyMight = makeVec("PallyMight", "PALADIN", {
				BOM = { rank = 7, talent = 5 },
				BOW = { rank = 6, talent = 0 },
			}),
		}

		-- Yield mode: Paladins untouched
		LBB.Negotiator.Solve(LBB.Assignments.roster, caps, LBB.Assignments, { pallyPowerYield = true })
		assert.is_nil(LBB.Assignments:GetClassBuff("PallyKings", "WARRIOR"))
		assert.is_nil(LBB.Assignments:GetClassBuff("PallyMight", "WARRIOR"))

		-- Active mode: PallyKings gets Kings on Warriors, PallyMight gets Imp. Might on Warriors
		LBB.Negotiator.Solve(LBB.Assignments.roster, caps, LBB.Assignments, { pallyPowerYield = false })
		assert.are.equal("BOK", LBB.Assignments:GetClassBuff("PallyKings", "WARRIOR").familyID)
		assert.are.equal("BOM", LBB.Assignments:GetClassBuff("PallyMight", "WARRIOR").familyID)
	end)
end)
