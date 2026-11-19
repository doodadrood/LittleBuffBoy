local Mock = require("tests.wow_mock")

describe("Scanner (Live Auras, Priority Targeting, Consumables) & Tracking Persistence", function()
	local env, LBB

	before_each(function()
		env = Mock.New()
		env:Install()
		LBB = env:LoadCore()
	end)

	it("detects live auras cast by un-synced teammates and never wastes mana re-casting", function()
		env:SetTime(1000)
		env:SetUnit("player", {
			name = "MyPriest",
			class = "PRIEST",
			subgroup = 1,
			auras = { { name = "Prayer of Fortitude", spellId = 21564, duration = 3600, expirationTime = 4500 } },
		})
		env:SetUnit("raid1", env.state.units["player"])
		env:SetUnit("raid2", {
			name = "TankAlreadyBuffed",
			class = "WARRIOR",
			subgroup = 1,
			role = "TANK",
			-- Buffed by an un-synced Priest without LittleBuffBoy!
			auras = { { name = "Power Word: Fortitude", spellId = 10938, duration = 1800, expirationTime = 2700 } },
		})
		env:SetGroup("RAID", { "raid1", "raid2" })
		env:SetKnownSpell(10938, "Power Word: Fortitude", 135987)
		env:SetKnownSpell(21564, "Prayer of Fortitude", 135941)

		LBB.Assignments:RefreshRosterFromGame()
		LBB.Capabilities:ScanPlayer()
		LBB.Assignments:SetGroupBuff("FORTITUDE", 1, "MyPriest", false)

		local duties = LBB.Assignments:GetPlayerDuties("MyPriest")
		assert.are.equal(1, #duties)

		local eval = LBB.Scanner:EvaluateDuty(duties[1], LBB.Assignments.roster)
		assert.are.equal(2, eval.totalEligible)
		assert.are.equal(2, eval.buffedCount)
		assert.are.equal(0, eval.missingCount)
		assert.are.equal(0, eval.expiringCount)
		assert.is_nil(eval.nextTarget)
		assert.is_false(eval.recommendGroup)
	end)

	it("prioritizes next cast target by in-range -> missing over expiring -> Tank > Healer > DPS and recommends group spell", function()
		env:SetTime(1000)
		env:SetUnit("player", {
			name = "MyPriest",
			class = "PRIEST",
			subgroup = 1,
			role = "HEALER",
			auras = { { name = "Power Word: Fortitude", spellId = 10938, duration = 1800, expirationTime = 2500 } },
		})
		env:SetUnit("raid1", env.state.units["player"])
		-- Out-of-range missing Tank
		env:SetUnit("raid2", { name = "FarTank", class = "WARRIOR", subgroup = 1, role = "TANK", auras = {} })
		-- In-range expiring DPS (60s left < 180s threshold)
		env:SetUnit("raid3", {
			name = "ExpiringRogue",
			class = "ROGUE",
			subgroup = 1,
			role = "DAMAGER",
			auras = { { name = "Power Word: Fortitude", spellId = 10938, duration = 1800, expirationTime = 1060 } },
		})
		-- In-range missing DPS
		env:SetUnit("raid4", { name = "MissingMage", class = "MAGE", subgroup = 1, role = "DAMAGER", auras = {} })
		-- In-range missing Tank (should win!)
		env:SetUnit("raid5", { name = "NearTank", class = "WARRIOR", subgroup = 1, role = "TANK", auras = {} })

		env:SetSpellInRange("raid2", "Power Word: Fortitude", false)
		env:SetSpellInRange("raid3", "Power Word: Fortitude", true)
		env:SetSpellInRange("raid4", "Power Word: Fortitude", true)
		env:SetSpellInRange("raid5", "Power Word: Fortitude", true)
		env:SetGroup("RAID", { "raid1", "raid2", "raid3", "raid4", "raid5" })

		env:SetKnownSpell(10938, "Power Word: Fortitude", 135987)
		env:SetKnownSpell(21564, "Prayer of Fortitude", 135941)
		env:SetItemCount(17029, 5) -- low reagents (< 20)

		LBB.Assignments:RefreshRosterFromGame()
		LBB.Capabilities:ScanPlayer()
		LBB.Assignments:SetGroupBuff("FORTITUDE", 1, "MyPriest", false)

		local duty = LBB.Assignments:GetPlayerDuties("MyPriest")[1]
		local eval = LBB.Scanner:EvaluateDuty(duty, LBB.Assignments.roster)

		assert.are.equal(3, eval.missingCount)
		assert.are.equal(1, eval.expiringCount)
		assert.are.equal("NearTank", eval.nextTarget.name)
		assert.are.equal("raid5", eval.nextTarget.unit)
		assert.is_true(eval.recommendGroup)
		assert.is_true(eval.lowReagent)
		assert.are.equal(5, eval.reagentCount)
	end)

	it("invalidates cached buffs on death so battle-rezzed teammates are highlighted mid-combat", function()
		env:SetTime(1000)
		env:SetCombat(false)
		env:SetUnit("raid1", {
			name = "TankRez",
			class = "WARRIOR",
			subgroup = 1,
			dead = false,
			auras = { { name = "Power Word: Fortitude", spellId = 10938, duration = 1800, expirationTime = 2800 } },
		})

		-- Pre-combat scan caches Fortitude
		local s1 = LBB.Scanner:ScanUnit("raid1", { guid = "GUID-TankRez" })
		assert.is_not_nil(s1.families.FORTITUDE)

		-- Mid-combat death wipes cached buffs
		env:SetCombat(true)
		env.state.units["raid1"].dead = true
		env.state.units["raid1"].auraBlocked = true
		LBB.Scanner:ScanUnit("raid1", { guid = "GUID-TankRez" })

		-- Tank is Battle-Rezzed mid-combat (still restricted combat auras)
		env.state.units["raid1"].dead = false
		local s3 = LBB.Scanner:ScanUnit("raid1", { guid = "GUID-TankRez" })
		assert.is_true(s3.battleRezzed)
		assert.is_nil(s3.families.FORTITUDE)
	end)

	it("scans consumables (Well Fed, Flask/Elixir, Weapon Oil) and builds Ready Check report by caster", function()
		env:SetTime(1000)
		env:SetUnit("player", {
			name = "RaiderMe",
			class = "PRIEST",
			subgroup = 1,
			auras = {
				{ name = "Well Fed", spellId = 25661, duration = 900, expirationTime = 1800 },
				{ name = "Flask of Distilled Wisdom", spellId = 17627, duration = 7200, expirationTime = 8000 },
			},
		})
		env:SetUnit("raid1", env.state.units["player"])
		env:SetUnit("raid2", { name = "UnbuffedWar", class = "WARRIOR", subgroup = 1, auras = {} })
		env:SetWeaponEnchant(true, 600000, false, 0)
		env:SetGroup("RAID", { "raid1", "raid2" })
		env:SetKnownSpell(10938, "Power Word: Fortitude", 135987)

		LBB.Assignments:RefreshRosterFromGame()
		LBB.Capabilities:ScanPlayer()
		LBB.Assignments:SetGroupBuff("FORTITUDE", 1, "RaiderMe", false)

		-- Scan player directly for weapon enchant + consumables
		local pScan = LBB.Scanner:ScanUnit("player", { guid = "GUID-RaiderMe" })
		assert.is_not_nil(pScan.consumables.WELL_FED)
		assert.is_not_nil(pScan.consumables.FLASK_ELIXIR)
		assert.is_not_nil(pScan.consumables.WEAPON_OIL)

		local report = LBB.Scanner:BuildReadinessReport(LBB.Assignments.roster, LBB.Assignments)
		assert.is_not_nil(report.missingByCaster["RaiderMe"])
		assert.are.equal(1, #report.missingByCaster["RaiderMe"])
		assert.are.equal(2, report.missingByCaster["RaiderMe"][1].missingCount)
	end)

	it("persists preferred minimap tracking, detects drops, and restores with one click", function()
		env:SetUnit("player", { name = "MinerGuy", class = "WARRIOR" })
		env:SetTrackingList({
			{ name = "Find Minerals", texture = 136025, active = true, spellID = 2580 },
			{ name = "Find Herbs", texture = 133939, active = false, spellID = 2383 },
		}, true)

		-- 1. First refresh auto-remembers Find Minerals
		local st1 = LBB.Tracking:Refresh()
		assert.is_true(st1.hasPreferred)
		assert.are.equal("Find Minerals", st1.preferred.name)
		assert.is_true(st1.isActive)
		assert.is_false(st1.needsRestore)

		-- 2. Tracking drops (e.g., player died/resurrected)
		env.state.tracking[1].active = false
		local st2 = LBB.Tracking:Refresh()
		assert.is_false(st2.isActive)
		assert.is_true(st2.needsRestore)
		assert.are.equal(1, st2.index)

		-- 3. Dismissing hides pill until clearDismiss trigger (e.g. READY_CHECK / login)
		LBB.Tracking:Dismiss()
		assert.is_false(LBB.Tracking:GetStatus().needsRestore)
		local stWake = LBB.Tracking:Refresh({ clearDismiss = true })
		assert.is_true(stWake.needsRestore)

		-- 4. One-click RestorePreferred calls C_Minimap.SetTracking(1, true)
		local ok = LBB.Tracking:RestorePreferred()
		assert.is_true(ok)
		assert.is_true(env.state.tracking[1].active)
		assert.is_true(LBB.Tracking:GetStatus().isActive)
		assert.is_false(LBB.Tracking:GetStatus().needsRestore)
	end)
end)
