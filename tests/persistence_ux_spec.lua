local Mock = require("tests.wow_mock")

describe("Persistence, Smart Raid Re-Negotiation, Presets, Auto-Buff, Apply-All & Minimap Icon", function()
	local env, LBB

	local function bootPaladin(preserveDB)
		env.state.preserveSavedVars = preserveDB and true or false
		env:Install()
		env:SetTime(1000)
		env:SetUnit("player", { name = "Uther Light", class = "PALADIN", subgroup = 1, role = "TANK", auras = {} })
		env:SetGroup("SOLO", {})
		env:SetKnownSpell(20217, "Blessing of Kings", 135995)
		env:SetKnownSpell(25290, "Blessing of Wisdom", 135970)
		env:SetKnownSpell(25291, "Blessing of Might", 135906)
		env:SetKnownSpell(1038, "Blessing of Salvation", 135967)
		env:SetKnownSpell(465, "Devotion Aura", 135893)
		env:SetKnownSpell(7294, "Retribution Aura", 135873)
		env:SetKnownSpell(19746, "Concentration Aura", 135933)
		env:SetKnownSpell(25780, "Righteous Fury", 135962)
		env:SetKnownSpell(21084, "Seal of Righteousness", 132325)
		env:SetKnownSpell(1311656, "Seal of Fury", 135962)

		LBB = env:LoadFullAddon()
		LBB:OnEvent("ADDON_LOADED", "LittleBuffBoy")
		LBB:OnEvent("PLAYER_LOGIN")
		LBB:OnEvent("PLAYER_ENTERING_WORLD")
		env:AdvanceTime(2.0)
		LBB.Comms:ProcessQueue(env.state.time)
		return LBB
	end

	before_each(function()
		env = Mock.New()
		bootPaladin(false)
	end)

	it("persists Paladin blessings, aura, and per-player overrides across /reload without reverting to defaults", function()
		-- Customize setup while solo (non-default: Might on Paladins, Wisdom on Mages, Kings on Warriors, Concentration Aura)
		LBB.Assignments:SetClassBuff("Uther Light", "PALADIN", "BOM", true)
		LBB.Assignments:SetClassBuff("Uther Light", "WARRIOR", "BOK", true)
		LBB.Assignments:SetClassBuff("Uther Light", "MAGE", "BOW", true)
		LBB.Assignments:SetPaladinAura("Uther Light", 3, true)
		LBB.Assignments:SetPaladinNormalOverride("Uther Light", "Holy Pal", "PALADIN", "BOW", true)
		LBB.Assignments:SaveToCharDB()

		-- Solo BuffStrip should NOT show empty 0-target Warrior/Mage tiles while solo
		LBB.BuffStrip:Refresh()
		assert.is_not_nil(LBB.BuffStrip.lastEvals["CLASS:BOM"])
		assert.is_nil(LBB.BuffStrip.lastEvals["CLASS:BOK"])
		assert.is_nil(LBB.BuffStrip.lastEvals["CLASS:BOW"])

		-- Simulate full /reload (fresh LBB instance reading saved LittleBuffBoyCharDB)
		bootPaladin(true)

		assert.are.equal("BOM", LBB.Assignments:GetClassBuff("Uther Light", "PALADIN").familyID)
		assert.are.equal("BOK", LBB.Assignments:GetClassBuff("Uther Light", "WARRIOR").familyID)
		assert.are.equal("BOW", LBB.Assignments:GetClassBuff("Uther Light", "MAGE").familyID)
		assert.are.equal(3, LBB.Assignments:GetPaladinAura("Uther Light").auraID)
		assert.are.equal("BOW", LBB.Assignments:GetPaladinNormalOverride("Uther Light", "Holy Pal").familyID)
	end)

	it("auto-negotiates fresh when joining a new multi-caster raid, then preserves setup on reload in the SAME raid", function()
		-- Solo Paladin locks Might on Warriors & Retribution Aura
		LBB.Assignments:SetClassBuff("Uther Light", "WARRIOR", "BOM", true)
		LBB.Assignments:SetPaladinAura("Uther Light", 2, true)
		LBB.Assignments:SaveToCharDB()

		-- Join a NEW multi-caster raid with a higher-Imp-Might Paladin (Tirion)
		env:SetUnit("raid1", env.state.units["player"])
		env:SetUnit("raid2", { name = "Tirion Fordring", class = "PALADIN", subgroup = 1, role = "DAMAGER" })
		env:SetUnit("raid3", { name = "Tank Warrior", class = "WARRIOR", subgroup = 1, role = "TANK" })
		env:SetGroup("RAID", { "raid1", "raid2", "raid3" })
		LBB.Capabilities:SetPeerVector("Tirion Fordring", {
			name = "Tirion Fordring",
			class = "PALADIN",
			buffs = {
				BOM = { known = true, bestSingleRank = 7, talentRank = 5, hasGroup = true, priorityScore = 135 },
				BOW = { known = true, bestSingleRank = 6, talentRank = 0, hasGroup = true, priorityScore = 75 },
			},
			auras = { [1] = { auraID = 1 }, [3] = { auraID = 3 } },
		})

		-- Roster update detects NEW multi-caster raid -> negotiates fresh!
		LBB:OnEvent("GROUP_ROSTER_UPDATE")
		assert.are.equal("RAID:PALADIN:Tirion Fordring,Uther Light", LBB.Assignments.lastMultiCasterRaidSig)
		-- Uther (who has Kings) takes BOK on Warriors, Tirion (5/5 Imp Might) takes BOM on Warriors!
		assert.are.equal("BOK", LBB.Assignments:GetClassBuff("Uther Light", "WARRIOR").familyID)
		assert.are.equal("BOM", LBB.Assignments:GetClassBuff("Tirion Fordring", "WARRIOR").familyID)

		-- Now customize Uther's Warrior blessing to Salvation in THIS raid & simulate /reload in SAME raid
		LBB.Assignments:SetClassBuff("Uther Light", "WARRIOR", "BOSALV", true)
		LBB.Assignments:SaveToCharDB()

		-- Reload in same raid
		env.state.preserveSavedVars = true
		env:Install()
		env:SetUnit("player", { name = "Uther Light", class = "PALADIN", subgroup = 1, role = "TANK", auras = {} })
		env:SetUnit("raid1", env.state.units["player"])
		env:SetUnit("raid2", { name = "Tirion Fordring", class = "PALADIN", subgroup = 1, role = "DAMAGER" })
		env:SetUnit("raid3", { name = "Tank Warrior", class = "WARRIOR", subgroup = 1, role = "TANK" })
		env:SetGroup("RAID", { "raid1", "raid2", "raid3" })
		env:SetKnownSpell(20217, "Blessing of Kings", 135995)
		env:SetKnownSpell(1038, "Blessing of Salvation", 135967)
		LBB = env:LoadFullAddon()
		LBB:OnEvent("ADDON_LOADED", "LittleBuffBoy")
		LBB.Capabilities:SetPeerVector("Tirion Fordring", {
			name = "Tirion Fordring",
			class = "PALADIN",
			buffs = { BOM = { known = true, bestSingleRank = 7, talentRank = 5, hasGroup = true, priorityScore = 135 } },
			auras = { [1] = { auraID = 1 } },
		})
		LBB:OnEvent("PLAYER_ENTERING_WORLD")

		-- Same raid signature -> customized Salvation stays intact!
		assert.are.equal("BOSALV", LBB.Assignments:GetClassBuff("Uther Light", "WARRIOR").familyID)
	end)

	it("saves, loads, and deletes named Presets (including blessings, aura, RF, and Seal)", function()
		-- Configure Solo preset
		LBB.Assignments:SetClassBuff("Uther Light", "PALADIN", "BOM", true)
		LBB.Assignments:SetPaladinAura("Uther Light", 2, true)
		LBB.Assignments:SetRighteousFuryEnabled(false)
		LBB.Assignments:SetSelectedSeal(LBB.Capabilities:GetPlayerVector().seals.SEAL_OF_RIGHTEOUSNESS)
		LBB:HandleSlashCommand("preset save Solo")

		-- Configure Raid Tank preset
		LBB.Assignments:SetClassBuff("Uther Light", "PALADIN", "BOK", true)
		LBB.Assignments:SetPaladinAura("Uther Light", 1, true)
		LBB.Assignments:SetRighteousFuryEnabled(true)
		LBB.Assignments:SetSelectedSeal(LBB.Capabilities:GetPlayerVector().seals.SEAL_OF_FURY)
		LBB:HandleSlashCommand("preset save Raid")

		-- Switch back to Solo preset in 1 command
		LBB:HandleSlashCommand("preset load Solo")
		assert.are.equal("BOM", LBB.Assignments:GetClassBuff("Uther Light", "PALADIN").familyID)
		assert.are.equal(2, LBB.Assignments:GetPaladinAura("Uther Light").auraID)
		assert.is_false(LBB.Assignments:GetPaladinSelfConfig().trackRF)
		assert.are.equal("SEAL_OF_RIGHTEOUSNESS", LBB.Assignments:GetPaladinSelfConfig().sealID)

		-- Switch to Raid preset
		LBB:LoadPreset("Raid")
		assert.are.equal("BOK", LBB.Assignments:GetClassBuff("Uther Light", "PALADIN").familyID)
		assert.are.equal(1, LBB.Assignments:GetPaladinAura("Uther Light").auraID)
		assert.is_true(LBB.Assignments:GetPaladinSelfConfig().trackRF)
		assert.are.equal("SEAL_OF_FURY", LBB.Assignments:GetPaladinSelfConfig().sealID)

		-- Delete Solo preset
		LBB:HandleSlashCommand("preset delete Solo")
		assert.are.same({ "Raid" }, LBB.Assignments:ListPresets())
	end)

	it("supports 1-click Apply to ALL Classes (broadcasting PLPWR MASSIGN) and Apply to ALL Groups", function()
		env:SetUnit("raid1", env.state.units["player"])
		env:SetGroup("RAID", { "raid1" })
		env.state.sentAddonMessages = {}

		local menu = LBB.MatrixFrame:BuildPaladinClassMenu("Uther Light", "PALADIN", function() end)
		local allSub
		for _, item in ipairs(menu) do
			if item.text == "Apply to ALL Classes" then
				allSub = item.submenu
				break
			end
		end
		assert.is_not_nil(allSub)

		-- Click "Blessing of Kings" in Apply to ALL Classes submenu
		for _, subItem in ipairs(allSub) do
			if subItem.text == "Blessing of Kings" then
				subItem.onClick()
				break
			end
		end

		-- All 9 classes now locked to BOK
		for _, cls in ipairs(LBB.Catalog.CLASS_ORDER) do
			local e = LBB.Assignments:GetClassBuff("Uther Light", cls)
			assert.are.equal("BOK", e.familyID)
			assert.is_true(e.locked)
		end

		-- Broadcasted BOTH LBB1 CLASS_ALL and native PLPWR MASSIGN
		local sawMass, sawLbb = false, false
		for _, m in ipairs(env.state.sentAddonMessages) do
			if m.prefix == "PLPWR" and m.msg == "MASSIGN Uther Light 3" then sawMass = true end
			if m.prefix == "LBB1" and m.msg:find("LOCK|CLASS_ALL|Uther Light|BOK|Uther Light|1", 1, true) then sawLbb = true end
		end
		assert.is_true(sawMass)
		assert.is_true(sawLbb)

		-- Also verify Apply to ALL Groups (G1-G8)
		LBB.Assignments:SetAllGroupBuffs("FORTITUDE", "PriestOne", true)
		for sg = 1, 8 do
			assert.are.equal("PriestOne", LBB.Assignments:GetGroupBuff("FORTITUDE", sg).caster)
			assert.is_true(LBB.Assignments:GetGroupBuff("FORTITUDE", sg).locked)
		end
	end)

	it("drives the bindable Smart Auto-Buff tile (LittleBuffBoyAutoBuffBtn), strip scale, and healthy fade/hide modes", function()
		LBB.Assignments:SetClassBuff("Uther Light", "PALADIN", "BOK", true)
		LBB.Assignments:SetPaladinAura("Uther Light", 1, true)
		LBB.Assignments:SetRighteousFuryEnabled(true)
		LBB.BuffStrip:Refresh()

		local autoBtn = _G.LittleBuffBoyAutoBuffBtn
		assert.is_not_nil(autoBtn)
		assert.is_true(autoBtn:IsShown())
		-- Priority #1 is missing Devotion Aura / Righteous Fury before Blessings
		assert.are.equal("spell", autoBtn:GetAttribute("type1"))
		assert.are.equal("Devotion Aura", autoBtn:GetAttribute("spell1"))
		assert.are.equal("player", autoBtn:GetAttribute("unit1"))

		-- Buff Devotion Aura + Righteous Fury -> next priority becomes Blessing of Kings
		env.state.units["player"].auras = {
			{ name = "Devotion Aura", spellId = 465, duration = 0, expirationTime = 0 },
			{ name = "Righteous Fury", spellId = 25780, duration = 1800, expirationTime = 2800 },
		}
		LBB.BuffStrip:Refresh()
		assert.are.equal("Blessing of Kings", autoBtn:GetAttribute("spell1"))

		-- Buff Blessing of Kings too -> all healthy! Test FADE and HIDE modes + scale
		env.state.units["player"].auras = {
			{ name = "Devotion Aura", spellId = 465, duration = 0, expirationTime = 0 },
			{ name = "Righteous Fury", spellId = 25780, duration = 1800, expirationTime = 2800 },
			{ name = "Blessing of Kings", spellId = 20217, duration = 3600, expirationTime = 4600 },
		}
		LBB.DB.stripHealthyMode = "FADE"
		LBB:HandleSlashCommand("scale 1.2")
		assert.are.equal(1.2, LBB.BuffStrip.frame._scale)
		assert.are.equal(0.35, LBB.BuffStrip.frame._alpha)

		LBB.DB.stripHealthyMode = "HIDE"
		LBB.BuffStrip:Refresh()
		assert.is_false(LBB.BuffStrip.frame:IsShown())

		-- Drop Blessing of Kings -> strip pops right back up!
		env.state.units["player"].auras = {
			{ name = "Devotion Aura", spellId = 465, duration = 0, expirationTime = 0 },
			{ name = "Righteous Fury", spellId = 25780, duration = 1800, expirationTime = 2800 },
		}
		LBB.BuffStrip:Refresh()
		assert.is_true(LBB.BuffStrip.frame:IsShown())
	end)

	it("registers minimap icon cleanly with LibDBIcon/OneForAll when present and respects reparenting when standalone", function()
		-- Standalone path (bootPaladin ran without LibStub)
		local btn = LBB.MinimapButton.button
		assert.is_not_nil(btn)
		assert.are.equal("LibDBIcon10_LittleBuffBoy", btn:GetName())
		assert.are.equal("Interface\\AddOns\\LittleBuffBoy\\Media\\MinimapIcon", btn.icon._texture)
		assert.are.equal(_G.Minimap, btn:GetParent())

		-- Simulate OneForAll collecting/reparenting the button into its collapsible drawer
		local oneForAllDrawer = env:CreateMockFrame("Frame", "OneForAllDrawer", _G.UIParent)
		btn:SetParent(oneForAllDrawer)
		btn._points = { { "CENTER", oneForAllDrawer, "CENTER", 10, 10 } }
		LBB.MinimapButton:UpdatePosition()
		-- MUST NOT rip the button back to Minimap!
		assert.are.equal(oneForAllDrawer, btn:GetParent())
		assert.are.equal(oneForAllDrawer, btn._points[1][2])

		-- Now test LibDataBroker-1.1 + LibDBIcon-1.0 path (native OneForAll / MBB / HidingBar registry)
		local registeredIcon = nil
		local ldbObj = nil
		local mockLDB = {
			GetDataObjectByName = function() return ldbObj end,
			NewDataObject = function(_, name, obj) ldbObj = obj; return obj end,
		}
		local mockLDBIcon = {
			IsRegistered = function() return registeredIcon ~= nil end,
			Register = function(_, name, obj, db) registeredIcon = { name = name, obj = obj, db = db } end,
			GetMinimapButton = function() return env:CreateMockFrame("Button", "LibDBIcon10_LittleBuffBoy", _G.Minimap) end,
			Show = function() end,
			Hide = function() end,
		}
		_G.LibStub = function(libName)
			if libName == "LibDataBroker-1.1" then return mockLDB end
			if libName == "LibDBIcon-1.0" then return mockLDBIcon end
			return nil
		end

		LBB.MinimapButton.button = nil
		LBB.MinimapButton.usingLibDBIcon = false
		LBB.MinimapButton:Init()

		assert.is_true(LBB.MinimapButton.usingLibDBIcon)
		assert.is_not_nil(registeredIcon)
		assert.are.equal("LittleBuffBoy", registeredIcon.name)
		assert.are.equal("Interface\\AddOns\\LittleBuffBoy\\Media\\MinimapIcon", registeredIcon.obj.icon)
	end)
end)
