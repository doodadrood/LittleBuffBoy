local Mock = require("tests.wow_mock")

describe("Smart Anti-Stuck Buff Casting (Cross-Duty Range, LoS Rotation, Visibility/Phase & Unbuffable Guards)", function()
	local env, LBB

	before_each(function()
		env = Mock.New()
		env:Install()
		env:SetTime(1000)

		env:SetUnit("player", {
			name = "PaladinBuffer",
			class = "PALADIN",
			subgroup = 1,
			role = "HEALER",
			auras = {
				{ name = "Blessing of Wisdom", spellId = 25290, duration = 3600, expirationTime = 4600 },
				{ name = "Devotion Aura", spellId = 465, duration = 0, expirationTime = 0 },
			},
		})
		env.state.units["raid1"] = env.state.units["player"]
		env:SetUnit("raid2", {
			name = "FarWarrior",
			class = "WARRIOR",
			subgroup = 1,
			role = "TANK",
			auras = {},
		})
		env:SetUnit("raid3", {
			name = "NearMage",
			class = "MAGE",
			subgroup = 1,
			role = "DAMAGER",
			auras = {},
		})
		env:SetGroup("RAID", { "raid1", "raid2", "raid3" })

		env:SetKnownSpell(20217, "Blessing of Kings", 135995)
		env:SetKnownSpell(25290, "Blessing of Wisdom", 135970)
		env:SetKnownSpell(25291, "Blessing of Might", 135906)
		env:SetKnownSpell(465, "Devotion Aura", 135893)

		LBB = env:LoadFullAddon()
		LBB:OnEvent("ADDON_LOADED", "LittleBuffBoy")
		LBB:OnEvent("PLAYER_LOGIN")
		LBB:OnEvent("PLAYER_ENTERING_WORLD")
	end)

	it("skips an out-of-range missing class/person and casts the next available missing or expiring buff on an in-range person", function()
		-- Paladin assigned Kings on Warriors (FarWarrior is out of range) and Wisdom on Mages (NearMage is in range)
		LBB.Assignments:SetClassBuff("PaladinBuffer", "WARRIOR", "BOK", true)
		LBB.Assignments:SetClassBuff("PaladinBuffer", "MAGE", "BOW", true)
		LBB.Assignments:SetClassBuff("PaladinBuffer", "PALADIN", "BOW", true)

		env:SetSpellInRange("raid2", "Blessing of Kings", false)
		env:SetSpellInRange("raid3", "Blessing of Wisdom", true)

		LBB.BuffStrip:Refresh()
		local autoBtn = _G.LittleBuffBoyAutoBuffBtn

		-- Smart Auto-Buff MUST skip out-of-range FarWarrior and target in-range NearMage with Blessing of Wisdom!
		assert.are.equal("raid3", autoBtn:GetAttribute("unit1"))
		assert.are.equal("Blessing of Wisdom", autoBtn:GetAttribute("spell1"))

		-- Even if NearMage's buff is only EXPIRING (<3m) while FarWarrior is completely MISSING,
		-- Smart Auto-Buff still prioritizes in-range NearMage over out-of-range FarWarrior!
		env.state.units["raid3"].auras = {
			{ name = "Blessing of Wisdom", spellId = 25290, duration = 3600, expirationTime = 1090 },
		}
		LBB.BuffStrip:Refresh()
		assert.are.equal("raid3", autoBtn:GetAttribute("unit1"))
		assert.are.equal("Blessing of Wisdom", autoBtn:GetAttribute("spell1"))

		-- And the Kings tile clearly displays "OOR" so the player sees why Warriors aren't being buffed yet
		local bokEval = LBB.BuffStrip.lastEvals["CLASS:BOK"]
		assert.is_not_nil(bokEval)
		assert.is_true(bokEval.allOutOfRange)
	end)

	it("detects out-of-range units via UnitIsVisible, UnitInPhase, spellID fallback, and UnitInRange when spell name returns nil", function()
		-- C_Spell.IsSpellInRange returns nil for string name, but raid2 is not visible (>100 yds / other zone)
		env.state.units["raid2"].visible = false
		assert.is_false(LBB.Compat.IsSpellInRange("Blessing of Kings", "raid2", 20217))

		-- Visible but in a different layer/phase -> out of range
		env.state.units["raid2"].visible = true
		env.state.units["raid2"].inPhase = false
		assert.is_false(LBB.Compat.IsSpellInRange("Blessing of Kings", "raid2", 20217))

		-- Visible & in phase, C_Spell returns nil, falls back to UnitInRange(unit)
		env.state.units["raid2"].inPhase = true
		env:SetSpellInRange("raid2", "UnknownSpellName", "NIL")
		env:SetSpellInRange("raid2", 999999, "NIL")
		env.state.units["raid2"].unitInRange = false
		assert.is_false(LBB.Compat.IsSpellInRange("UnknownSpellName", "raid2", 999999))
		env.state.units["raid2"].unitInRange = true
		assert.is_true(LBB.Compat.IsSpellInRange("UnknownSpellName", "raid2", 999999))
	end)

	it("automatically rotates past a Line-of-Sight / failed-cast target to the next in-range player and returns later", function()
		-- Both raid2 (Tank) and raid3 (Mage) are in range and need Blessing of Kings
		LBB.Assignments:SetAllClassBuffs("PaladinBuffer", "BOK", true)
		env.state.units["player"].auras = {
			{ name = "Blessing of Kings", spellId = 20217, duration = 3600, expirationTime = 4600 },
			{ name = "Devotion Aura", spellId = 465, duration = 0, expirationTime = 0 },
		}
		env:SetSpellInRange("raid2", "Blessing of Kings", true)
		env:SetSpellInRange("raid3", "Blessing of Kings", true)

		LBB.BuffStrip:Refresh()
		local autoBtn = _G.LittleBuffBoyAutoBuffBtn
		-- Initially targets raid2 (Tank > DPS)
		assert.are.equal("raid2", autoBtn:GetAttribute("unit1"))

		-- Player clicks once on raid2, and WoW fires UNIT_SPELLCAST_FAILED (e.g. "Target not in line of sight")
		autoBtn:GetScript("PostClick")(autoBtn)
		LBB:OnEvent("UNIT_SPELLCAST_FAILED", "player")

		-- Immediately rotates to raid3 (NearMage) so player isn't stuck on pillar-blocked raid2!
		assert.are.equal("raid3", autoBtn:GetAttribute("unit1"))

		-- Now raid3 receives Blessing of Kings -> raid2 is the only unbuffed target left, so button returns to raid2!
		env.state.units["raid3"].auras = {
			{ name = "Blessing of Kings", spellId = 20217, duration = 3600, expirationTime = 4600 },
		}
		LBB:OnEvent("UNIT_AURA", "raid3")
		assert.are.equal("raid2", autoBtn:GetAttribute("unit1"))
	end)

	it("also rotates target on repeated PostClick within 3.5s even if no spellcast failure event fired", function()
		LBB.Assignments:SetAllClassBuffs("PaladinBuffer", "BOK", true)
		env.state.units["player"].auras = {
			{ name = "Blessing of Kings", spellId = 20217, duration = 3600, expirationTime = 4600 },
			{ name = "Devotion Aura", spellId = 465, duration = 0, expirationTime = 0 },
		}
		LBB.BuffStrip:Refresh()
		local autoBtn = _G.LittleBuffBoyAutoBuffBtn
		assert.are.equal("raid2", autoBtn:GetAttribute("unit1"))

		-- Click 1 records attempt on raid2; Click 2 (1s later, buff still missing) rotates to raid3!
		autoBtn:GetScript("PostClick")(autoBtn)
		env:AdvanceTime(1.0)
		autoBtn:GetScript("PostClick")(autoBtn)
		assert.are.equal("raid3", autoBtn:GetAttribute("unit1"))
	end)

	it("skips Mind-Controlled / hostile teammates and Spirit of Redemption Priests so buffing never fails with Invalid Target", function()
		LBB.Assignments:SetAllClassBuffs("PaladinBuffer", "BOK", true)
		env.state.units["player"].auras = {
			{ name = "Blessing of Kings", spellId = 20217, duration = 3600, expirationTime = 4600 },
			{ name = "Devotion Aura", spellId = 465, duration = 0, expirationTime = 0 },
		}

		-- raid2 is Mind Controlled (charmed) -> skipped in favor of raid3
		env.state.units["raid2"].charmed = true
		LBB.BuffStrip:Refresh()
		assert.are.equal("raid3", _G.LittleBuffBoyAutoBuffBtn:GetAttribute("unit1"))

		-- raid2 is un-charmed but has Spirit of Redemption (27827) -> also skipped in favor of raid3
		env.state.units["raid2"].charmed = false
		env.state.units["raid2"].auras = {
			{ name = "Spirit of Redemption", spellId = 27827, duration = 15, expirationTime = 1015 },
		}
		LBB.BuffStrip:Refresh()
		assert.are.equal("raid3", _G.LittleBuffBoyAutoBuffBtn:GetAttribute("unit1"))
	end)

	it("pre-stages in-range teammates (never resetting unit1 to 'player' or an OOR unit) when entering combat healthy", function()
		-- Everyone is buffed before combat; raid1 (player) was buffed 5s before raid2 (Tank) and raid3 (Mage)
		LBB.Assignments:SetClassBuff("PaladinBuffer", "WARRIOR", "BOM", true)
		LBB.Assignments:SetClassBuff("PaladinBuffer", "MAGE", "BOW", true)
		LBB.Assignments:SetClassBuff("PaladinBuffer", "PALADIN", "BOW", true)

		env.state.units["player"].auras = {
			{ name = "Blessing of Wisdom", spellId = 25290, duration = 600, expirationTime = 1595 },
			{ name = "Devotion Aura", spellId = 465, duration = 0, expirationTime = 0 },
		}
		env.state.units["raid2"].auras = {
			{ name = "Blessing of Might", spellId = 25291, duration = 600, expirationTime = 1500 },
		}
		env.state.units["raid3"].auras = {
			{ name = "Blessing of Wisdom", spellId = 25290, duration = 600, expirationTime = 1600 },
		}

		LBB.BuffStrip:Refresh()
		local autoBtn = _G.LittleBuffBoyAutoBuffBtn

		-- Even though everyone is healthy (0 missing, 0 expiring):
		-- 1) The BOM (Warrior) duty tile stays aimed at raid2 (FarWarrior), NEVER resetting to "player"!
		-- 2) The BOW (Mage + Paladin) duty tile prefers teammate raid3 (NearMage) over self (raid1) when buffed in the same session!
		-- 3) The AUTO button pre-stages BOM on raid2 because raid2's buff expires soonest (1500 < 1595)!
		local bomTile, bowTile
		for _, t in ipairs(LBB.BuffStrip.tiles) do
			if t:IsShown() and t._eval then
				if t._eval.duty.key == "CLASS:BOM" then bomTile = t end
				if t._eval.duty.key == "CLASS:BOW" then bowTile = t end
			end
		end
		assert.is_not_nil(bomTile)
		assert.is_not_nil(bowTile)
		assert.are.equal("raid2", bomTile:GetAttribute("unit1"))
		assert.are.equal("raid3", bowTile:GetAttribute("unit1"))
		assert.are.equal("raid2", autoBtn:GetAttribute("unit1"))
		assert.are.equal("Blessing of Might", autoBtn:GetAttribute("spell1"))
	end)

	it("rotates unit1 across alive teammates in combat via SecureHandlerWrapScript and supports @mouseover", function()
		LBB.Assignments:SetAllClassBuffs("PaladinBuffer", "BOK", true)
		env.state.units["player"].auras = {
			{ name = "Blessing of Kings", spellId = 20217, duration = 600, expirationTime = 1595 },
			{ name = "Devotion Aura", spellId = 465, duration = 0, expirationTime = 0 },
		}
		env.state.units["raid2"].auras = {
			{ name = "Blessing of Kings", spellId = 20217, duration = 600, expirationTime = 1600 },
		}
		env.state.units["raid3"].auras = {
			{ name = "Blessing of Kings", spellId = 20217, duration = 600, expirationTime = 1600 },
		}
		LBB.BuffStrip:Refresh()

		local autoBtn = _G.LittleBuffBoyAutoBuffBtn
		-- combat_units is pre-staged with Tank (raid2) -> DPS teammate (raid3) -> Self (raid1)
		assert.are.equal("raid2,raid3,raid1", autoBtn:GetAttribute("combat_units"))

		-- Enter combat lockdown! Normal Lua SetAttribute is now blocked, but SecureHandlerWrapScript runs on Click!
		env:SetCombat(true)

		-- Physical Click 1 in combat (MouseDown + MouseUp pair) -> targets raid2 (and does NOT double-increment on MouseUp!)
		autoBtn:Click("LeftButton", true)
		assert.are.equal("raid2", autoBtn:GetAttribute("unit1"))
		autoBtn:Click("LeftButton", false)
		assert.are.equal("raid2", autoBtn:GetAttribute("unit1"))

		-- Physical Click 2 in combat -> rotates in combat to raid3 (NearMage)!
		autoBtn:Click("LeftButton", true)
		autoBtn:Click("LeftButton", false)
		assert.are.equal("raid3", autoBtn:GetAttribute("unit1"))

		-- Physical Click 3 in combat -> rotates in combat to raid1 (Self)!
		autoBtn:Click("LeftButton", true)
		autoBtn:Click("LeftButton", false)
		assert.are.equal("raid1", autoBtn:GetAttribute("unit1"))

		-- If raid2 dies mid-combat, the next click automatically skips dead raid2 and targets alive raid3!
		env.state.units["raid2"].dead = true
		autoBtn:Click("LeftButton", true)
		autoBtn:Click("LeftButton", false)
		assert.are.equal("raid3", autoBtn:GetAttribute("unit1"))

		-- Hovering a friendly alive unit (@mouseover) in combat immediately targets "mouseover"!
		env:SetUnit("mouseover", { name = "HoveredFriend", class = "MAGE", online = true, dead = false })
		autoBtn:Click("LeftButton", true)
		autoBtn:Click("LeftButton", false)
		assert.are.equal("mouseover", autoBtn:GetAttribute("unit1"))
	end)

	it("updates auraCache on in-combat UNIT_SPELLCAST_SUCCEEDED and Judgement Seal consumption even when auras are secret", function()
		env:SetKnownSpell(21084, "Seal of Righteousness", 132325)
		env:SetKnownSpell(20271, "Judgement", 135959)
		LBB.Capabilities:ScanPlayer()
		LBB.Assignments:SetSelectedSeal({ id = "SEAL_OF_RIGHTEOUSNESS", name = "Seal of Righteousness" })
		LBB.Assignments:SetAllClassBuffs("PaladinBuffer", "BOK", true)

		-- Pre-combat scan caches Seal + Kings on player, while raid2 is missing Kings
		env.state.units["player"].auras = {
			{ name = "Blessing of Kings", spellId = 20217, duration = 600, expirationTime = 1600 },
			{ name = "Devotion Aura", spellId = 465, duration = 0, expirationTime = 0 },
			{ name = "Seal of Righteousness", spellId = 21084, duration = 30, expirationTime = 1030 },
		}
		LBB.BuffStrip:Refresh()
		assert.are.equal(0, LBB.BuffStrip.lastEvals["SELF:SEAL"].missingCount)
		assert.are.equal(2, LBB.BuffStrip.lastEvals["CLASS:BOK"].missingCount)

		-- Enter combat with Midnight secret auras (auraBlocked = true on all units)
		env:SetCombat(true)
		env.state.units["player"].auraBlocked = true
		env.state.units["raid2"].auraBlocked = true
		env.state.units["raid3"].auraBlocked = true

		-- 1) Cast Blessing of Kings on FarWarrior (raid2) in combat -> UNIT_SPELLCAST_SENT + UNIT_SPELLCAST_SUCCEEDED updates cache!
		LBB:OnEvent("UNIT_SPELLCAST_SENT", "player", "FarWarrior", "CAST-1", 20217)
		LBB:OnEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "CAST-1", 20217)
		assert.are.equal(1, LBB.BuffStrip.lastEvals["CLASS:BOK"].missingCount)

		-- 2) Cast Judgement (20271) in combat -> consumes Seal in cache even though player auras are secret!
		LBB:OnEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "CAST-2", 20271)
		assert.are.equal(1, LBB.BuffStrip.lastEvals["SELF:SEAL"].missingCount)

		-- 3) Re-cast Seal of Righteousness (21084) in combat -> Seal tile immediately returns to OK (0 missing)!
		LBB:OnEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "CAST-3", 21084)
		assert.are.equal(0, LBB.BuffStrip.lastEvals["SELF:SEAL"].missingCount)
	end)

	it("preserves party/raid roster when GROUP_ROSTER_UPDATE or BAG_UPDATE_DELAYED fires in combat with secret unit names", function()
		assert.are.equal(3, #LBB.Assignments.roster)

		-- Enter combat and simulate Midnight secret values on unit names
		env:SetCombat(true)
		local origName2 = env.state.units["raid2"].name
		local origName3 = env.state.units["raid3"].name
		env.state.units["raid2"].name = Mock.MakeSecret("FarWarrior")
		env.state.units["raid3"].name = Mock.MakeSecret("NearMage")

		LBB:OnEvent("GROUP_ROSTER_UPDATE")
		LBB:OnEvent("BAG_UPDATE_DELAYED")

		-- Roster MUST NOT collapse to 1 unit ("player"); raid2 and raid3 are preserved from pre-combat cache!
		assert.are.equal(3, #LBB.Assignments.roster)
		assert.are.equal(origName2, LBB.Assignments.rosterByUnit["raid2"].name)
		assert.are.equal(origName3, LBB.Assignments.rosterByUnit["raid3"].name)
	end)
end)
