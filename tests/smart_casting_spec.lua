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
end)
