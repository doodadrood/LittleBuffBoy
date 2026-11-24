local Mock = require("tests.wow_mock")

describe("Full Addon Integration (UI, RaidIndicators, ReminderPill, Init & Slash Commands)", function()
	local env, LBB

	before_each(function()
		env = Mock.New()
		env:Install()
		env:SetTime(1000)
		env:SetUnit("player", {
			name = "Aeloria Light",
			class = "PRIEST",
			subgroup = 1,
			role = "HEALER",
			auras = {},
		})
		env:SetUnit("raid1", env.state.units["player"])
		env:SetUnit("raid2", {
			name = "Bulwark Tank",
			class = "WARRIOR",
			subgroup = 1,
			role = "TANK",
			auras = {},
		})
		env:SetUnit("raid3", {
			name = "Frost Mage",
			class = "MAGE",
			subgroup = 1,
			role = "DAMAGER",
			auras = {},
		})
		env:SetGroup("RAID", { "raid1", "raid2", "raid3" })
		env:SetKnownSpell(10938, "Power Word: Fortitude", 135987)
		env:SetKnownSpell(21564, "Prayer of Fortitude", 135941)
		env:SetItemCount(17029, 40)
		env:SetTrackingList({
			{ name = "Find Herbs", texture = 133939, active = true, spellID = 2383 },
		}, true)

		LBB = env:LoadFullAddon()
		LBB:OnEvent("ADDON_LOADED", "LittleBuffBoy")
		LBB:OnEvent("PLAYER_ENTERING_WORLD")
	end)

	it("never registers forbidden COMBAT_LOG_EVENT_UNFILTERED and wires all Forever events", function()
		assert.is_not_nil(LBB.eventFrame)
		assert.is_nil(LBB.eventFrame._events["COMBAT_LOG_EVENT_UNFILTERED"])
		assert.is_true(LBB.eventFrame._events["UNIT_AURA"])
		assert.is_true(LBB.eventFrame._events["GROUP_ROSTER_UPDATE"])
		assert.is_true(LBB.eventFrame._events["READY_CHECK"])
		assert.is_true(LBB.eventFrame._events["PLAYER_REGEN_ENABLED"])
		assert.is_true(LBB.eventFrame._events["PLAYER_REGEN_DISABLED"])
		assert.is_true(LBB.eventFrame._events["SPELLS_CHANGED"])
		assert.is_true(LBB.eventFrame._events["MINIMAP_UPDATE_TRACKING"])
	end)

	it("populates BuffStrip SecureActionButton attributes out of combat and queues updates safely during combat", function()
		local tile = LBB.BuffStrip.tiles[1]
		assert.is_not_nil(tile)
		assert.is_true(tile._isSecure)
		assert.are.equal("spell", tile:GetAttribute("type1"))
		assert.are.equal("Power Word: Fortitude", tile:GetAttribute("spell1"))
		assert.are.equal("Prayer of Fortitude", tile:GetAttribute("spell2"))
		-- Bulwark Tank (raid2) is prioritized first because Tank > Healer > DPS
		assert.are.equal("raid2", tile:GetAttribute("unit1"))

		-- Enter combat & buff raid2 -> BuffStrip refresh queues new unit1 without throwing!
		env:SetCombat(true)
		env.state.units["raid2"].auras = {
			{ name = "Power Word: Fortitude", spellId = 10938, duration = 1800, expirationTime = 2800 },
		}
		assert.has_no.errors(function()
			LBB:OnEvent("UNIT_AURA", "raid2")
		end)
		-- Still raid2 during combat lockdown; queued for PLAYER_REGEN_ENABLED
		assert.are.equal("raid2", tile:GetAttribute("unit1"))
		assert.is_true(LBB.Compat.GetPendingCombatQueueCount() > 0)

		-- Leave combat -> flushes immediately to next missing target (raid1 = player, Healer > DPS)
		env:SetCombat(false)
		LBB:OnEvent("PLAYER_REGEN_ENABLED")
		assert.are.equal("raid1", tile:GetAttribute("unit1"))
		assert.are.equal(0, LBB.Compat.GetPendingCombatQueueCount())
	end)

	it("renders 6x6px RaidIndicators out of combat and stays calm during combat lockdown", function()
		assert.is_true(LBB.RaidIndicators.hooked)
		local raidFrame = env:CreateMockFrame("Button", "CompactRaidFrame2", _G.UIParent)
		raidFrame.unit = "raid2"
		raidFrame.displayedUnit = "raid2"

		-- Out of combat: missing Fortitude -> shows red pip
		LBB.RaidIndicators:UpdateFrame(raidFrame)
		assert.is_not_nil(raidFrame._lbbPips)
		assert.is_true(raidFrame._lbbPips[1]:IsShown())

		-- Expiring (<3m) out of combat -> shows amber pip
		env.state.units["raid2"].auras = {
			{ name = "Power Word: Fortitude", spellId = 10938, duration = 1800, expirationTime = 1090 },
		}
		LBB.RaidIndicators:UpdateFrame(raidFrame)
		assert.is_true(raidFrame._lbbPips[1]:IsShown())

		-- Enter combat with expiring buff -> calm combat mode suppresses amber nagging!
		env:SetCombat(true)
		LBB.RaidIndicators:UpdateFrame(raidFrame)
		assert.is_false(raidFrame._lbbPips[1]:IsShown())

		-- Tank dies and is battle-rezzed mid-combat (secret auras) -> critical red pip appears!
		env.state.units["raid2"].dead = true
		env.state.units["raid2"].auraBlocked = true
		LBB.RaidIndicators:UpdateFrame(raidFrame)
		env.state.units["raid2"].dead = false
		LBB.RaidIndicators:UpdateFrame(raidFrame)
		assert.is_true(raidFrame._lbbPips[1]:IsShown())
	end)

	it("shows Tracking Pill on drop and sends Smart Whispers only to other casters on Ready Check", function()
		-- Tracking drop triggers ReminderPill tracking pill
		env.state.tracking[1].active = false
		LBB:OnEvent("MINIMAP_UPDATE_TRACKING")
		assert.is_true(LBB.ReminderPill.trackPill:IsShown())

		-- One-click restore hides pill
		LBB.Tracking:RestorePreferred()
		assert.is_false(LBB.ReminderPill.trackPill:IsShown())

		-- Assign Frost Mage to cast Arcane Intellect on Group 1 (currently missing on all 3)
		LBB.Assignments:SetGroupBuff("INTELLECT", 1, "Frost Mage", true)
		LBB:OnEvent("READY_CHECK")
		assert.is_true(LBB.ReminderPill.nudgeFrame:IsShown())

		env.state.sentChatMessages = {}
		local sent = LBB.ReminderPill:SendSmartWhispers()
		-- Should whisper ONLY Frost Mage (not self Aeloria Light, and NEVER /raid!)
		assert.are.equal(1, sent)
		assert.are.equal("WHISPER", env.state.sentChatMessages[1].chatType)
		assert.are.equal("Frost Mage", env.state.sentChatMessages[1].target)
		assert.is_truthy(env.state.sentChatMessages[1].msg:find("Arcane Intellect"))
	end)

	it("executes all /lbb slash commands cleanly and pools MatrixFrame widgets across tabs", function()
		assert.has_no.errors(function()
			LBB:HandleSlashCommand("ui")
			assert.is_true(LBB.MatrixFrame.frame:IsShown())
			LBB.MatrixFrame.activeTab = "TOTEMS"
			LBB.MatrixFrame:Refresh()
			LBB.MatrixFrame.activeTab = "CONSUMABLES"
			LBB.MatrixFrame:Refresh()
			LBB.MatrixFrame.activeTab = "BUFFS"
			LBB.MatrixFrame:Refresh()

			LBB:HandleSlashCommand("lock")
			assert.is_true(LBB.DB.locked)
			LBB:HandleSlashCommand("lock")
			assert.is_false(LBB.DB.locked)

			LBB:HandleSlashCommand("auto")
			LBB:HandleSlashCommand("reset")
			LBB:HandleSlashCommand("status")
			LBB:HandleSlashCommand("nudge")
			LBB:HandleSlashCommand("options")
			assert.is_true(LBB.Options.frame:IsShown())
		end)
	end)

	it("layers Matrix, Nudge, Options, and Dropdown frames cleanly with opaque backgrounds and no z-fighting", function()
		LBB:HandleSlashCommand("ui")
		LBB:HandleSlashCommand("nudge")
		LBB:HandleSlashCommand("options")
		LBB.Theme.ShowDropdownMenu(LBB.Options.frame, { { text = "Test Item" } })

		-- Strict strata hierarchy: Matrix (DIALOG) < Nudge & Options (FULLSCREEN_DIALOG, Options higher level) < Dropdown (TOOLTIP)
		assert.are.equal("DIALOG", LBB.MatrixFrame.frame:GetFrameStrata())
		assert.are.equal("FULLSCREEN_DIALOG", LBB.ReminderPill.nudgeFrame:GetFrameStrata())
		assert.are.equal("FULLSCREEN_DIALOG", LBB.Options.frame:GetFrameStrata())
		assert.is_true(LBB.Options.frame:GetFrameLevel() > LBB.ReminderPill.nudgeFrame:GetFrameLevel())
		assert.are.equal("TOOLTIP", LBB.Theme._menuCatcher:GetFrameStrata())
		assert.are.equal("TOOLTIP", LBB.Theme._menuMain:GetFrameStrata())
		assert.is_true(LBB.Theme._menuMain:GetFrameLevel() > LBB.Theme._menuCatcher:GetFrameLevel())

		-- Solid 1.0 alpha opaque backgrounds & drop shadows prevent underlying Matrix rows from bleeding through
		assert.are.equal(1.0, LBB.Options.frame._lbbBg._color[4])
		assert.are.equal(1.0, LBB.MatrixFrame.frame._lbbBg._color[4])
		assert.are.equal(1.0, LBB.MatrixFrame.frame._content._lbbBg._color[4])
		assert.is_not_nil(LBB.Options.frame._lbbShadow)

		-- Priest sees the Class Self Buffs shortcut instead of Paladin-only rows, and dragging saves optionsPos
		assert.is_false(LBB.Options.frame._paladinRFRow:IsShown())
		assert.is_false(LBB.Options.frame._paladinSealRow:IsShown())
		assert.is_true(LBB.Options.frame._selfShortcutRow:IsShown())

		LBB.Options.frame:ClearAllPoints()
		LBB.Options.frame:SetPoint("TOPLEFT", _G.UIParent, "TOPLEFT", 180, -120)
		LBB.Options.frame:GetScript("OnDragStop")(LBB.Options.frame)
		assert.is_not_nil(LBB.CharDB.optionsPos)
		assert.are.equal(180, LBB.CharDB.optionsPos.x)
		assert.are.equal(-120, LBB.CharDB.optionsPos.y)
	end)
end)
