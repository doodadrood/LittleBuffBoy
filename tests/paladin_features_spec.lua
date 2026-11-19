local Mock = require("tests.wow_mock")

describe("Paladin Enhancements (Aura Column, Per-Player Overrides, Dropdowns, RF & Seals)", function()
	local env, LBB

	before_each(function()
		env = Mock.New()
		env:Install()
		env:SetTime(1000)

		env:SetUnit("player", {
			name = "Prot Pally",
			class = "PALADIN",
			subgroup = 1,
			role = "TANK",
			auras = {},
		})
		env:SetUnit("raid1", env.state.units["player"])
		env:SetUnit("raid2", {
			name = "Holy Pally",
			class = "PALADIN",
			subgroup = 1,
			role = "HEALER",
			auras = {},
		})
		env:SetUnit("raid3", {
			name = "Ret Pally",
			class = "PALADIN",
			subgroup = 1,
			role = "DAMAGER",
			auras = {},
		})
		env:SetGroup("RAID", { "raid1", "raid2", "raid3" })

		env:SetKnownSpell(20217, "Blessing of Kings", 135995)
		env:SetKnownSpell(25290, "Blessing of Wisdom", 135970)
		env:SetKnownSpell(25291, "Blessing of Might", 135906)
		env:SetKnownSpell(465, "Devotion Aura", 135893)
		env:SetKnownSpell(19746, "Concentration Aura", 135933)
		env:SetKnownSpell(25780, "Righteous Fury", 135962)
		env:SetKnownSpell(21084, "Seal of Righteousness", 132325)
		env:SetKnownSpell(1311656, "Seal of Fury", 135962)
		-- Also verify dynamic C_SpellBook discovery picks up a custom Forever seal
		env:SetSpellBookExtra(1399999, "Seal of the Forever", 135962)

		LBB = env:LoadFullAddon()
		LBB:OnEvent("ADDON_LOADED", "LittleBuffBoy")
		LBB:OnEvent("PLAYER_ENTERING_WORLD")
		-- Advance clock past initial login burst so throttle bucket is refilled
		env:AdvanceTime(2.0)
		LBB.Comms:ProcessQueue(env.state.time)
	end)

	it("discovers Righteous Fury, catalog Seals, Forever Seal of Fury, and dynamic spellbook Seals", function()
		local vec = LBB.Capabilities:GetPlayerVector()
		assert.is_not_nil(vec.righteousFury)
		assert.is_true(vec.righteousFury.known)
		assert.are.equal(25780, vec.righteousFury.spellID)

		assert.is_not_nil(vec.seals.SEAL_OF_RIGHTEOUSNESS)
		assert.is_not_nil(vec.seals.SEAL_OF_FURY)
		assert.are.equal("Seal of Fury", vec.seals.SEAL_OF_FURY.name)
		assert.is_not_nil(vec.seals.SEAL_SEAL_OF_THE_FOREVER)
		assert.are.equal("Seal of the Forever", vec.seals.SEAL_SEAL_OF_THE_FOREVER.name)
	end)

	it("supports Paladin per-player override (Kings on Paladins, Wisdom override on Holy Pally) across duties, Scanner, RaidIndicators, and PLPWR NASSIGN", function()
		LBB.Assignments:SetClassBuff("Prot Pally", "PALADIN", "BOK", true)

		-- Use the Matrix inline Per-Player Overrides dropdown menu to set Holy Pally -> Blessing of Wisdom
		local menu = LBB.MatrixFrame:BuildPaladinClassMenu("Prot Pally", "PALADIN", function(fam, lock)
			LBB.Assignments:SetClassBuff("Prot Pally", "PALADIN", fam, lock)
		end)

		local holySubmenu = nil
		for _, item in ipairs(menu) do
			if item.submenu and item.text and item.text:find("Holy Pally", 1, true) then
				holySubmenu = item.submenu
				break
			end
		end
		assert.is_not_nil(holySubmenu)

		env.state.sentAddonMessages = {}
		local clicked = false
		for _, subItem in ipairs(holySubmenu) do
			if subItem.text == "Blessing of Wisdom" then
				subItem.onClick()
				clicked = true
				break
			end
		end
		assert.is_true(clicked)

		-- Verify override saved and broadcast on BOTH LBB1 (LOCK|NORMAL) and PLPWR (NASSIGN with Forever "_")
		local ov = LBB.Assignments:GetPaladinNormalOverride("Prot Pally", "Holy Pally")
		assert.is_not_nil(ov)
		assert.are.equal("BOW", ov.familyID)

		local sawLBB, sawPLPWR = false, false
		for _, sent in ipairs(env.state.sentAddonMessages) do
			if sent.prefix == "LBB1" and sent.msg:find("LOCK|NORMAL|Holy Pally|BOW|Prot Pally|1|PALADIN", 1, true) then
				sawLBB = true
			end
			if sent.prefix == "PLPWR" and sent.msg == "NASSIGN Prot_Pally 5 Holy_Pally 1" then
				sawPLPWR = true
			end
		end
		assert.is_true(sawLBB)
		assert.is_true(sawPLPWR)

		-- Verify duties split cleanly: BOK excludes Holy Pally (2 targets: Prot + Ret), BOW targets ONLY Holy Pally (1 target)
		local duties = LBB.Assignments:GetPlayerDuties("Prot Pally")
		local bokDuty, bowDuty
		for _, d in ipairs(duties) do
			if d.kind == "CLASS_BUFF" and d.familyID == "BOK" then bokDuty = d end
			if d.kind == "CLASS_BUFF" and d.familyID == "BOW" then bowDuty = d end
		end
		assert.is_not_nil(bokDuty)
		assert.is_not_nil(bowDuty)

		local bokEval = LBB.Scanner:EvaluateDuty(bokDuty, LBB.Assignments.roster)
		local bowEval = LBB.Scanner:EvaluateDuty(bowDuty, LBB.Assignments.roster)
		assert.are.equal(2, bokEval.totalEligible)
		assert.are.equal(1, bowEval.totalEligible)
		assert.are.equal("Holy Pally", bowEval.nextTarget.name)

		-- Verify RaidIndicators expects Wisdom on Holy Pally (buffing Kings on Holy Pally still shows missing pip until Wisdom is cast!)
		local holyFrame = env:CreateMockFrame("Button", "CompactRaidFrameHoly", _G.UIParent)
		holyFrame.unit = "raid2"
		holyFrame.displayedUnit = "raid2"
		env.state.units["raid2"].auras = {
			{ name = "Blessing of Kings", spellId = 20217, duration = 3600, expirationTime = 4600 },
		}
		LBB.RaidIndicators:UpdateFrame(holyFrame)
		assert.is_true(holyFrame._lbbPips[1]:IsShown())

		env.state.units["raid2"].auras = {
			{ name = "Blessing of Wisdom", spellId = 25290, duration = 3600, expirationTime = 4600 },
		}
		LBB.RaidIndicators:UpdateFrame(holyFrame)
		assert.is_false(holyFrame._lbbPips[1]:IsShown())

		-- Verify SendPLPWRSelf also emits NASSIGN for overrides
		env.state.sentAddonMessages = {}
		LBB.Comms:SendPLPWRSelf("SomePeer")
		local sawSelfNassign = false
		for _, sent in ipairs(env.state.sentAddonMessages) do
			if sent.prefix == "PLPWR" and sent.msg == "NASSIGN Prot_Pally 5 Holy_Pally 1" then
				sawSelfNassign = true
			end
		end
		assert.is_true(sawSelfNassign)
	end)

	it("lets a Paladin change and lock their assigned Aura via the Matrix Aura dropdown and syncs PLPWR AASSIGN", function()
		env.state.sentAddonMessages = {}
		local appliedAura = nil
		local auraMenu = LBB.MatrixFrame:BuildPaladinAuraMenu("Prot Pally", function(aid, lock)
			appliedAura = aid
			LBB.Assignments:SetPaladinAura("Prot Pally", aid, lock)
			LBB.Comms:BroadcastLock("AURA", "Prot Pally", tostring(aid), "Prot Pally", lock)
		end)

		local foundConc = false
		for _, item in ipairs(auraMenu) do
			if item.text == "Concentration Aura" then
				item.onClick()
				foundConc = true
				break
			end
		end
		assert.is_true(foundConc)
		assert.are.equal(3, appliedAura)
		assert.are.equal(3, LBB.Assignments:GetPaladinAura("Prot Pally").auraID)
		assert.is_true(LBB.Assignments:GetPaladinAura("Prot Pally").locked)

		local sawAassign = false
		for _, sent in ipairs(env.state.sentAddonMessages) do
			if sent.prefix == "PLPWR" and sent.msg == "AASSIGN Prot Pally 3" then
				sawAassign = true
			end
		end
		assert.is_true(sawAassign)
	end)

	it("auto-prompts Prot Tank Paladins for opt-in Righteous Fury & Seal, renders BuffStrip tiles, and binds NativeAuras when available", function()
		-- Opt-in: RF & Seal start disabled by default even for a Tank Paladin until enabled
		local cfg = LBB.Assignments:GetPaladinSelfConfig()
		assert.is_false(cfg.trackRF)
		assert.is_false(cfg.trackSeal)

		-- Tank role + RF known triggers the non-intrusive Prot prompt pill
		assert.is_true(LBB.Assignments:ShouldPromptProtRF())
		assert.is_true(LBB.ReminderPill.protPill:IsShown())

		-- Enable Blizzard_AuraContainer native overlay mock and opt into Prot defaults
		env:EnableNativeAuraMock(true)
		LBB.NativeAuras:Reset()
		LBB.Assignments:EnableProtSelfDefaults()
		LBB.ReminderPill:UpdateProtPrompt()
		LBB:RefreshUI()

		assert.is_false(LBB.ReminderPill.protPill:IsShown())
		assert.is_true(cfg.trackRF)
		assert.is_true(cfg.trackSeal)
		assert.are.equal("SEAL_OF_FURY", cfg.sealID)

		-- Verify BuffStrip rendered dedicated SecureActionButton tiles for RF & Seal of Fury and bound NativeAuras
		local rfTile, sealTile
		for _, tile in ipairs(LBB.BuffStrip.tiles) do
			if tile._eval and tile._eval.duty then
				if tile._eval.duty.kind == "RIGHTEOUS_FURY" then rfTile = tile end
				if tile._eval.duty.kind == "PALADIN_SEAL" then sealTile = tile end
			end
		end
		assert.is_not_nil(rfTile)
		assert.is_not_nil(sealTile)
		assert.are.equal("Righteous Fury", rfTile:GetAttribute("spell1"))
		assert.are.equal("player", rfTile:GetAttribute("unit1"))
		assert.are.equal("Seal of Fury", sealTile:GetAttribute("spell1"))
		assert.are.equal("player", sealTile:GetAttribute("unit1"))
		assert.is_true(LBB.NativeAuras:IsBound(rfTile._timer))
		assert.is_true(LBB.NativeAuras:IsBound(sealTile._timer))
	end)

	it("yields Paladin Blessings, Auras, Righteous Fury, Seals, and Prot prompt when standalone PallyPower is loaded", function()
		LBB.Assignments:EnableProtSelfDefaults()
		LBB.Assignments:GetPaladinSelfConfig().tankPrompted = false
		env:SetAddonLoaded("PallyPower", true)

		assert.is_false(LBB.Assignments:ShouldPromptProtRF())
		LBB.ReminderPill:UpdateProtPrompt()
		assert.is_false(LBB.ReminderPill.protPill:IsShown())

		LBB.BuffStrip:Refresh()
		-- Zero Paladin duties rendered on BuffStrip when yielded to PallyPower
		assert.is_nil(LBB.BuffStrip.lastEvals["SELF:RIGHTEOUS_FURY"])
		assert.is_nil(LBB.BuffStrip.lastEvals["SELF:SEAL"])
		assert.is_nil(LBB.BuffStrip.lastEvals["CLASS:BOK"])
	end)

	it("opens and closes Theme.ShowDropdownMenu cleanly with inline submenus", function()
		local anchor = env:CreateMockFrame("Button", "TestAnchor", _G.UIParent)
		local picked = nil
		local menu = LBB.Theme.ShowDropdownMenu(anchor, {
			{ isTitle = true, text = "Test Menu" },
			{
				text = "Sub Parent",
				submenu = {
					{ text = "Nested Option", onClick = function() picked = "nested" end },
				},
			},
		})
		assert.is_not_nil(menu)
		assert.is_true(menu:IsShown())

		-- Click parent row to open submenu, then click nested item
		local parentRow = menu._rows[2]
		parentRow:GetScript("OnClick")(parentRow)
		assert.is_true(LBB.Theme._menuSub:IsShown())
		local nestedRow = LBB.Theme._menuSub._rows[1]
		nestedRow:GetScript("OnClick")(nestedRow)

		assert.are.equal("nested", picked)
		assert.is_false(menu:IsShown())
		assert.is_false(LBB.Theme._menuSub:IsShown())
	end)
end)
