local Mock = require("tests.wow_mock")

describe("All-Class Personal Self-Buffs & Role-Based Target Buffs", function()
	it("tracks Priest Inner Fire, Shadowform, and Priest Guard without toggling off active Shadowform in combat", function()
		local env = Mock.New()
		env:EnableNativeAuraMock(true)
		env:SetUnit("player", { name = "Aeliana", class = "PRIEST", subgroup = 1, role = "DAMAGER" })
		env:SetUnit("party1", { name = "Tankadin", class = "PALADIN", subgroup = 1, role = "TANK" })
		env:SetGroup("PARTY", { "player", "party1" })

		env:SetKnownSpell(10938, "Power Word: Fortitude", 135987)
		env:SetKnownSpell(10952, "Inner Fire", 135926)
		env:SetKnownSpell(15473, "Shadowform", 136200)
		env:SetKnownSpell(18137, "Shadowguard", 136170)

		env:Install()
		local LBB = env:LoadFullAddon()
		LBB:Bootstrap()
		LBB:OnEvent("ADDON_LOADED", "LittleBuffBoy")
		LBB:OnEvent("PLAYER_LOGIN")
		LBB:OnEvent("PLAYER_ENTERING_WORLD")

		local vec = LBB.Capabilities:GetPlayerVector()
		assert.is_not_nil(vec.personal.PRIEST_INNER_FIRE.byID.INNER_FIRE)
		assert.is_not_nil(vec.personal.PRIEST_SHADOWFORM.byID.SHADOWFORM)
		assert.is_not_nil(vec.personal.PRIEST_GUARD.byID.SHADOWGUARD)

		-- Opt into Inner Fire + Shadowform
		LBB.Assignments:SetPersonalToggle("PRIEST_INNER_FIRE", true, vec.personal.PRIEST_INNER_FIRE.list[1])
		LBB.Assignments:SetPersonalToggle("PRIEST_SHADOWFORM", true, vec.personal.PRIEST_SHADOWFORM.list[1])
		LBB:RefreshUI()

		-- Both Inner Fire & Shadowform are missing initially -> Smart Auto-Buff prioritizes personal self-buffs first
		local autoBtn = _G.LittleBuffBoyAutoBuffBtn
		assert.is_true(autoBtn:IsShown())
		local firstSpell = autoBtn:GetAttribute("spell1")
		assert.is_true(firstSpell == "Inner Fire" or firstSpell == "Shadowform")
		assert.are.equal("player", autoBtn:GetAttribute("unit1"))

		-- Verify NativeAuras bound to personal buff tiles on BuffStrip
		local boundNative = false
		for _, tile in ipairs(LBB.BuffStrip.tiles) do
			if tile:IsShown() and tile._eval and tile._eval.duty.kind == "PERSONAL_BUFF" then
				if LBB.NativeAuras:IsBound(tile._timer) then
					boundNative = true
				end
			end
		end
		assert.is_true(boundNative)

		-- Now Shadowform is ACTIVE on the Priest, while Inner Fire and Fortitude on party1 are missing!
		env:SetUnit("player", {
			name = "Aeliana",
			class = "PRIEST",
			subgroup = 1,
			role = "DAMAGER",
			auras = {
				{ name = "Shadowform", spellId = 15473, duration = 0, expirationTime = 0 },
				{ name = "Power Word: Fortitude", spellId = 10938, duration = 1800, expirationTime = 2800 },
			},
		})
		LBB:RefreshUI()

		-- Next spell out of combat is Inner Fire on self, and combat_queue MUST NOT include active Shadowform!
		assert.are.equal("Inner Fire", autoBtn:GetAttribute("spell1"))
		local cq = autoBtn:GetAttribute("combat_queue") or ""
		local cgq = autoBtn:GetAttribute("combat_group_queue") or ""
		assert.is_truthy(cq:find("Inner Fire|player|1", 1, true))
		assert.is_truthy(cq:find("Power Word: Fortitude|party1|0", 1, true))
		assert.is_nil(cq:find("Shadowform", 1, true))
		assert.is_nil(cgq:find("Shadowform", 1, true))

		-- Enter combat with secret auras: Click 1 casts Inner Fire on player, Click 2 casts Power Word: Fortitude on party1!
		env:SetCombat(true)
		env.state.units["player"].auraBlocked = true
		env.state.units["party1"].auraBlocked = true
		LBB:OnEvent("PLAYER_REGEN_DISABLED")

		autoBtn:Click("LeftButton", true)
		autoBtn:Click("LeftButton", false)
		assert.are.equal("Inner Fire", autoBtn:GetAttribute("spell1"))
		assert.are.equal("player", autoBtn:GetAttribute("unit1"))
		LBB:OnEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-if", Mock.MakeSecret("sec_if"))

		autoBtn:Click("LeftButton", true)
		autoBtn:Click("LeftButton", false)
		assert.are.equal("Power Word: Fortitude", autoBtn:GetAttribute("spell1"))
		assert.are.equal("party1", autoBtn:GetAttribute("unit1"))
	end)

	it("tracks Shaman MH/OH Weapon Imbues via GetWeaponEnchantInfo, auto-hides OH imbue with a shield, and tracks Shields", function()
		local env = Mock.New()
		env:SetUnit("player", { name = "Thrallia", class = "SHAMAN", subgroup = 1, role = "DAMAGER" })
		env:SetGroup("SOLO", {})
		-- Main-hand mace + Off-hand SHIELD (Armor classID = 4)
		env:SetEquippedItem(16, 17103, 2)
		env:SetEquippedItem(17, 17066, 4)

		env:SetKnownSpell(16362, "Windfury Weapon", 136018)
		env:SetKnownSpell(16342, "Flametongue Weapon", 135814)
		env:SetKnownSpell(10432, "Lightning Shield", 136051)
		env:SetKnownSpell(24398, "Water Shield", 132315)

		env:Install()
		local LBB = env:LoadFullAddon()
		LBB:Bootstrap()
		LBB:OnEvent("ADDON_LOADED", "LittleBuffBoy")
		LBB:OnEvent("PLAYER_LOGIN")
		LBB:OnEvent("PLAYER_ENTERING_WORLD")

		local vec = LBB.Capabilities:GetPlayerVector()
		LBB.Assignments:SetPersonalChoice("SHAMAN_IMBUE_MH", vec.personal.SHAMAN_IMBUE_MH.byID.WINDFURY_WEAPON)
		LBB.Assignments:SetPersonalChoice("SHAMAN_IMBUE_OH", vec.personal.SHAMAN_IMBUE_OH.byID.FLAMETONGUE_WEAPON)
		LBB.Assignments:SetPersonalChoice("SHAMAN_SHIELD", vec.personal.SHAMAN_SHIELD.byID.WATER_SHIELD)
		LBB:RefreshUI()

		-- Wearing a Shield in slot 17 -> OH weapon imbue has 0 eligible targets and auto-hides from BuffStrip!
		assert.is_not_nil(LBB.BuffStrip.lastEvals["SELF:SHAMAN_IMBUE_MH"])
		assert.is_nil(LBB.BuffStrip.lastEvals["SELF:SHAMAN_IMBUE_OH"])
		assert.is_not_nil(LBB.BuffStrip.lastEvals["SELF:SHAMAN_SHIELD"])
		assert.are.equal(1, LBB.BuffStrip.lastEvals["SELF:SHAMAN_IMBUE_MH"].missingCount)

		-- Apply MH weapon enchant via GetWeaponEnchantInfo (25 minutes remaining in ms)
		env:SetWeaponEnchant(true, 1500 * 1000, false, 0)
		LBB:RefreshUI()
		assert.are.equal(0, LBB.BuffStrip.lastEvals["SELF:SHAMAN_IMBUE_MH"].missingCount)
		assert.are.equal("Water Shield", _G.LittleBuffBoyAutoBuffBtn:GetAttribute("spell1"))

		-- Swap shield for a dual-wield off-hand axe (Weapon classID = 2) -> UNIT_INVENTORY_CHANGED shows OH imbue tile!
		env:SetEquippedItem(17, 17075, 2)
		LBB:OnEvent("UNIT_INVENTORY_CHANGED", "player")
		assert.is_not_nil(LBB.BuffStrip.lastEvals["SELF:SHAMAN_IMBUE_OH"])
		assert.are.equal(1, LBB.BuffStrip.lastEvals["SELF:SHAMAN_IMBUE_OH"].missingCount)

		-- Optimistic cast of Flametongue Weapon marks OH weapon imbue active immediately
		LBB:OnEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-oh", 16342)
		assert.are.equal(0, LBB.BuffStrip.lastEvals["SELF:SHAMAN_IMBUE_OH"].missingCount)
	end)

	it("supports Mage Armors, Warlock Soul Link pet-gating, Hunter dynamic Aspects, and Warrior Shout deduplication", function()
		-- 1. Warlock: Demon Armor / Fel Armor + Soul Link (gated on active demon pet)
		local env = Mock.New()
		env:SetUnit("player", { name = "Guldan", class = "WARLOCK", subgroup = 1, role = "DAMAGER" })
		env:SetGroup("SOLO", {})
		env:SetKnownSpell(11735, "Demon Armor", 136185)
		env:SetKnownSpell(28189, "Fel Armor", 136156)
		env:SetKnownSpell(19028, "Soul Link", 136160)

		env:Install()
		local LBB = env:LoadFullAddon()
		LBB:Bootstrap()
		LBB:OnEvent("ADDON_LOADED", "LittleBuffBoy")
		LBB:OnEvent("PLAYER_LOGIN")
		LBB:OnEvent("PLAYER_ENTERING_WORLD")

		local vec = LBB.Capabilities:GetPlayerVector()
		LBB.Assignments:SetPersonalChoice("WARLOCK_ARMOR", vec.personal.WARLOCK_ARMOR.byID.FEL_ARMOR)
		LBB.Assignments:SetPersonalToggle("WARLOCK_SOUL_LINK", true, vec.personal.WARLOCK_SOUL_LINK.list[1])
		LBB:RefreshUI()

		-- No pet summoned yet -> Fel Armor shows on BuffStrip, Soul Link stays hidden!
		assert.is_not_nil(LBB.BuffStrip.lastEvals["SELF:WARLOCK_ARMOR"])
		assert.is_nil(LBB.BuffStrip.lastEvals["SELF:WARLOCK_SOUL_LINK"])

		-- Summon Felhunter -> UNIT_PET activates Soul Link tracking!
		env:SetUnit("pet", { name = "Zhaag", class = "WARRIOR" })
		LBB:OnEvent("UNIT_PET", "player")
		assert.is_not_nil(LBB.BuffStrip.lastEvals["SELF:WARLOCK_SOUL_LINK"])
		assert.are.equal(1, LBB.BuffStrip.lastEvals["SELF:WARLOCK_SOUL_LINK"].missingCount)

		-- 2. Hunter: Catalog + Dynamic Forever Aspects (ignoring passive Improved Aspect talents)
		local envH = Mock.New()
		envH:SetUnit("player", { name = "Rexxar", class = "HUNTER", subgroup = 1, role = "DAMAGER" })
		envH:SetGroup("SOLO", {})
		envH:SetKnownSpell(25296, "Aspect of the Hawk", 136076)
		envH:SetKnownSpell(34074, "Aspect of the Viper", 132160)
		envH:SetSpellBookExtra(99001, "Aspect of the Falcon", 132159) -- Forever custom Aspect
		envH:SetSpellBookExtra(19552, "Improved Aspect of the Hawk", 136076) -- passive talent name guard!

		envH:Install()
		local LBBH = envH:LoadFullAddon()
		LBBH:Bootstrap()
		LBBH:OnEvent("ADDON_LOADED", "LittleBuffBoy")
		LBBH:OnEvent("PLAYER_LOGIN")
		LBBH:OnEvent("PLAYER_ENTERING_WORLD")

		local hVec = LBBH.Capabilities:GetPlayerVector()
		local aspectBucket = hVec.personal.HUNTER_ASPECT
		assert.is_not_nil(aspectBucket.byName["Aspect of the Hawk"])
		assert.is_not_nil(aspectBucket.byName["Aspect of the Viper"])
		assert.is_not_nil(aspectBucket.byName["Aspect of the Falcon"])
		assert.is_nil(aspectBucket.byName["Improved Aspect of the Hawk"])

		-- 3. Warrior: Personal Battle Shout auto-dedupes when Group Battle Shout is assigned, while Commanding Shout stays separate
		local envW = Mock.New()
		envW:SetUnit("player", { name = "Garrosh", class = "WARRIOR", subgroup = 1, role = "TANK" })
		envW:SetGroup("SOLO", {})
		envW:SetKnownSpell(25289, "Battle Shout", 132333)
		envW:SetKnownSpell(469, "Commanding Shout", 132351)

		envW:Install()
		local LBBW = envW:LoadFullAddon()
		LBBW:Bootstrap()
		LBBW:OnEvent("ADDON_LOADED", "LittleBuffBoy")
		LBBW:OnEvent("PLAYER_LOGIN")
		LBBW:OnEvent("PLAYER_ENTERING_WORLD")

		local wVec = LBBW.Capabilities:GetPlayerVector()
		LBBW.Assignments:SetPersonalChoice("WARRIOR_SHOUT", wVec.personal.WARRIOR_SHOUT.byID.SELF_BATTLE_SHOUT)
		LBBW:RefreshUI()
		-- Group Battle Shout is already assigned for Group 1 -> no duplicate SELF:WARRIOR_SHOUT tile!
		assert.is_not_nil(LBBW.BuffStrip.lastEvals["GROUP:BATTLE_SHOUT"])
		assert.is_nil(LBBW.BuffStrip.lastEvals["SELF:WARRIOR_SHOUT"])

		-- Switching Personal Shout to Commanding Shout adds the separate tile alongside Battle Shout (or when unassigned)
		LBBW.Assignments:SetPersonalChoice("WARRIOR_SHOUT", wVec.personal.WARRIOR_SHOUT.byID.COMMANDING_SHOUT)
		LBBW:RefreshUI()
		assert.is_not_nil(LBBW.BuffStrip.lastEvals["SELF:WARRIOR_SHOUT"])
		assert.are.equal("Commanding Shout", LBBW.BuffStrip.lastEvals["SELF:WARRIOR_SHOUT"].singleSpellName)
	end)

	it("assigns and tracks Role-scoped buffs (Thorns -> Tanks) across LFG Tanks, Raid Main Tanks, RaidIndicators, Comms, and Presets", function()
		local env = Mock.New()
		env:SetUnit("raid1", { name = "Bramble", class = "DRUID", subgroup = 1, role = "HEALER" })
		env:SetUnit("raid2", { name = "Shieldwall", class = "WARRIOR", subgroup = 1, role = "TANK" }) -- LFG role TANK
		env:SetUnit("raid3", { name = "Aegis", class = "PALADIN", subgroup = 2, role = "NONE", raidRole = "MAINTANK" }) -- Raid UI Main Tank!
		env:SetUnit("raid4", { name = "Pyroblast", class = "MAGE", subgroup = 2, role = "DAMAGER" })
		env:SetUnit("raid5", { name = "Bearclaw", class = "DRUID", subgroup = 3, role = "DAMAGER" })
		-- Alias "player" to Bramble
		env.state.units["player"] = env.state.units["raid1"]
		env:SetGroup("RAID", { "raid1", "raid2", "raid3", "raid4", "raid5" })

		env:SetKnownSpell(9885, "Mark of the Wild", 136078)
		env:SetKnownSpell(21850, "Gift of the Wild", 136038)
		env:SetKnownSpell(9910, "Thorns", 136104)

		env:Install()
		local LBB = env:LoadFullAddon()
		LBB:Bootstrap()
		LBB:OnEvent("ADDON_LOADED", "LittleBuffBoy")
		LBB:OnEvent("PLAYER_LOGIN")
		LBB:OnEvent("PLAYER_ENTERING_WORLD")

		-- Assign Thorns specifically to the TANK role
		LBB.Assignments:ClearAll(false, false)
		LBB.Assignments:SetRoleBuff("THORNS", "TANK", "Bramble", true)
		LBB.Assignments:SaveToCharDB()
		LBB:RefreshUI()

		local thornsEval = LBB.BuffStrip.lastEvals["TARGET:THORNS"]
		assert.is_not_nil(thornsEval)
		-- Both Shieldwall (LFG TANK) AND Aegis (Raid MAINTANK) are automatically tracked (2 eligible, 2 missing), ignoring Mage & DPS Druid!
		assert.are.equal(2, thornsEval.totalEligible)
		assert.are.equal(2, thornsEval.missingCount)

		-- RaidIndicators tracks missing role-assigned Thorns on both tanks, and NOT on the Mage
		local tankFams = LBB.Assignments:GetAssignedFamiliesForUnit("Bramble", LBB.Assignments.rosterByName["Aegis"])
		local mageFams = LBB.Assignments:GetAssignedFamiliesForUnit("Bramble", LBB.Assignments.rosterByName["Pyroblast"])
		assert.are.equal(1, #tankFams)
		assert.are.equal("THORNS", tankFams[1])
		assert.are.equal(0, #mageFams)

		-- Raid Leader promotes Bearclaw to MAINTANK mid-raid -> Thorns automatically includes Bearclaw (3 tanks)!
		env.state.units["raid5"].raidRole = "MAINTANK"
		LBB:OnEvent("GROUP_ROSTER_UPDATE")
		thornsEval = LBB.BuffStrip.lastEvals["TARGET:THORNS"]
		assert.are.equal(3, thornsEval.totalEligible)

		-- Save & reload Preset preserves roleBuffs + personalBuffs
		LBB.Assignments:SetPersonalToggle("DRUID_SELF_THORNS", true, LBB.Capabilities:GetPlayerVector().personal.DRUID_SELF_THORNS.list[1])
		LBB.Assignments:SavePreset("TankThorns")
		LBB.Assignments:ClearAll(false, false)
		LBB.Assignments:SetPersonalToggle("DRUID_SELF_THORNS", false, nil)
		assert.is_nil(LBB.Assignments:GetRoleBuff("THORNS", "TANK"))

		LBB:LoadPreset("TankThorns")
		local restoredRole = LBB.Assignments:GetRoleBuff("THORNS", "TANK")
		assert.is_not_nil(restoredRole)
		assert.are.equal("Bramble", restoredRole.caster)
		assert.is_true(LBB.Assignments:GetPersonalSlot("DRUID_SELF_THORNS").enabled)

		-- LBB1 LOCK|ROLE sync applies incoming peer role assignments cleanly
		local wireFrame = LBB.Comms:ChunkPayload("LOCK|ROLE|HEALER|FEAR_WARD|PriestPeer|1|")[1]
		LBB:OnEvent("CHAT_MSG_ADDON", "LBB1", wireFrame, "RAID", "PriestPeer")
		local fwRole = LBB.Assignments:GetRoleBuff("FEAR_WARD", "HEALER")
		assert.is_not_nil(fwRole)
		assert.are.equal("PriestPeer", fwRole.caster)
		assert.is_true(fwRole.locked)
	end)

	it("renders ROLES and SELF Matrix tabs, inline Self Buffs bar, dropdown menus, and /lbb self & /lbb roles cleanly", function()
		local env = Mock.New()
		env:SetUnit("player", { name = "Jaina", class = "MAGE", subgroup = 1, role = "DAMAGER" })
		env:SetUnit("party1", { name = "Muradin", class = "WARRIOR", subgroup = 1, role = "TANK" })
		env:SetGroup("PARTY", { "player", "party1" })

		env:SetKnownSpell(10157, "Arcane Intellect", 135932)
		env:SetKnownSpell(23028, "Arcane Brilliance", 135869)
		env:SetKnownSpell(22783, "Mage Armor", 135991)
		env:SetKnownSpell(10220, "Ice Armor", 135843)
		env:SetKnownSpell(13033, "Ice Barrier", 135988)
		env:SetKnownSpell(10174, "Dampen Magic", 136006)
		env:SetKnownSpell(10170, "Amplify Magic", 135907)

		env:Install()
		local LBB = env:LoadFullAddon()
		LBB:Bootstrap()
		LBB:OnEvent("ADDON_LOADED", "LittleBuffBoy")
		LBB:OnEvent("PLAYER_LOGIN")
		LBB:OnEvent("PLAYER_ENTERING_WORLD")

		-- Main tab renders inline My Self Buffs quick-bar
		LBB:HandleSlashCommand("ui")
		assert.is_true(LBB.MatrixFrame.frame:IsShown())
		assert.are.equal("BUFFS", LBB.MatrixFrame.activeTab)

		-- /lbb self opens SELF tab cleanly and builds personal slot menu
		LBB:HandleSlashCommand("self")
		assert.are.equal("SELF", LBB.MatrixFrame.activeTab)
		local mageArmorSlot = LBB.Catalog.PERSONAL_SLOT_BY_ID["MAGE_ARMOR"]
		local pMenu = LBB.MatrixFrame:BuildPersonalSlotMenu(mageArmorSlot)
		assert.is_true(#pMenu >= 4)

		-- /lbb roles opens ROLES tab cleanly and builds role + specific player menus
		LBB:HandleSlashCommand("roles")
		assert.are.equal("ROLES", LBB.MatrixFrame.activeTab)
		local rMenu = LBB.MatrixFrame:BuildRoleBuffMenu("AMPLIFY_MAGIC", "TANK", { "Jaina" }, function() end)
		assert.is_true(#rMenu >= 3)
		local tpMenu = LBB.MatrixFrame:BuildTargetPlayersMenu("AMPLIFY_MAGIC", { "Jaina" })
		assert.is_true(#tpMenu >= 3)
	end)
end)
