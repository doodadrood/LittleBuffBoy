local addonName, LBB = ...
LBB = LBB or _G.LittleBuffBoy or {}
_G.LittleBuffBoy = LBB

local pairs = pairs
local ipairs = ipairs
local tostring = tostring
local string_lower = string.lower
local string_trim = function(s)
	return tostring(s or ""):match("^%s*(.-)%s*$")
end

local DEFAULTS = {
	locked = false,
	stripOrientation = "HORIZONTAL",
	stripScale = 1.0,
	refreshThreshold = 180, -- 3 minutes
	groupThreshold = 2,
	showRaidIndicators = true,
	autoNegotiate = true,
	autoRememberTracking = true,
	freeAssign = false,
}

function LBB:Print(msg)
	local text = "|cff38bdf8[LittleBuffBoy]|r " .. tostring(msg or "")
	if _G.DEFAULT_CHAT_FRAME and _G.DEFAULT_CHAT_FRAME.AddMessage then
		_G.DEFAULT_CHAT_FRAME:AddMessage(text)
	elseif _G.print then
		_G.print(text)
	end
end

function LBB:InitDB()
	_G.LittleBuffBoyDB = _G.LittleBuffBoyDB or {}
	for k, v in pairs(DEFAULTS) do
		if _G.LittleBuffBoyDB[k] == nil then
			_G.LittleBuffBoyDB[k] = v
		end
	end
	_G.LittleBuffBoyCharDB = _G.LittleBuffBoyCharDB or {}
	self.DB = _G.LittleBuffBoyDB
	self.CharDB = _G.LittleBuffBoyCharDB
end

function LBB:RefreshUI()
	if self.BuffStrip then
		self.BuffStrip:Refresh()
	end
	if self.MatrixFrame and self.MatrixFrame.frame and self.MatrixFrame.frame:IsShown() then
		self.MatrixFrame:Refresh()
	end
	if self.RaidIndicators then
		self.RaidIndicators:RefreshAll()
	end
	if self.Options and self.Options.frame and self.Options.frame:IsShown() then
		self.Options:Refresh()
	end
end

function LBB:RunNegotiator(broadcastReneg)
	self.Assignments:RefreshRosterFromGame()
	self.Capabilities:ScanPlayer()

	-- Prune departed peers cleanly
	local activeNames = {}
	for _, m in ipairs(self.Assignments.roster) do
		if m.name then
			activeNames[m.name] = true
		end
	end
	self.Capabilities:RemoveMissingPeers(activeNames)

	local ppYield = self.Comms:IsPallyPowerLoaded()
	self.Negotiator.Solve(
		self.Assignments.roster,
		self.Capabilities:GetAllVectors(),
		self.Assignments,
		{ pallyPowerYield = ppYield }
	)

	if broadcastReneg then
		self.Comms:BroadcastRenegotiate()
		if not ppYield then
			self.Comms:SendPLPWRSelf()
		end
	end
	self:RefreshUI()
end

function LBB:ResetAssignments()
	local ppYield = self.Comms:IsPallyPowerLoaded()
	self.Assignments:ClearAll(false, ppYield)
	self:RunNegotiator(true)
	self:Print("Manual assignment locks cleared and re-negotiated.")
end

function LBB:SyncGroup()
	self.Capabilities:ScanPlayer()
	self.Comms:BroadcastCapabilities()
	self.Comms:SendRequest()
	if not self.Comms:IsPallyPowerLoaded() then
		self.Comms:SendPLPWRSelf()
	end
	self:Print("Requested buff sync from group/raid peers.")
end

function LBB:ToggleLock()
	if not self.DB then
		self:InitDB()
	end
	self.DB.locked = not self.DB.locked
	if self.BuffStrip then
		self.BuffStrip:UpdateLockVisual()
	end
	self:Print(self.DB.locked and "Buff Strip locked." or "Buff Strip unlocked (drag to move).")
end

function LBB:PrintStatus()
	local vec = self.Capabilities:GetPlayerVector()
	local ppYield = self.Comms:IsPallyPowerLoaded()
	local track = self.Tracking:GetStatus()
	local duties = vec and self.Assignments:GetPlayerDuties(vec.name) or {}

	local knownList = {}
	if vec then
		for famID, b in pairs(vec.buffs or {}) do
			if b.known then
				table.insert(knownList, string.format("%s(R%d/T%d/S%d)", famID, b.bestSingleRank or 1, b.talentRank or 0, b.priorityScore or 0))
			end
		end
	end
	table.sort(knownList)

	local peerCount = 0
	for _ in pairs(self.Capabilities:GetAllVectors()) do
		peerCount = peerCount + 1
	end

	local ver = self.Compat.GetAddOnMetadata("LittleBuffBoy", "Version") or "dev"
	self:Print(string.format("v%s | %s (%s) | Roster: %d | Synced Peers: %d",
		ver, vec and vec.name or "?", vec and vec.class or "?", #self.Assignments.roster, peerCount))
	self:Print("Known Buffs: " .. (#knownList > 0 and table.concat(knownList, ", ") or "none"))
	self:Print("Active Duties: " .. tostring(#duties) .. " | Pending Combat Queue: " .. tostring(self.Compat.GetPendingCombatQueueCount()))
	self:Print("PLPWR Bridge: " .. (ppYield and "Yielded to PallyPower" or "Active"))
	self:Print("Tracking: " .. (track.hasPreferred
		and (tostring(track.name) .. (track.isActive and " (active)" or " (MISSING)"))
		or (track.active and (tostring(track.active.name) .. " (active)") or "none")))
end

function LBB:HandleSlashCommand(rawMsg)
	local cmd = string_lower(string_trim(rawMsg))
	if cmd == "" or cmd == "ui" or cmd == "matrix" then
		if self.MatrixFrame then
			self.MatrixFrame:Toggle()
		end
	elseif cmd == "lock" then
		self:ToggleLock()
	elseif cmd == "auto" then
		self:RunNegotiator(true)
		self:Print("Auto-negotiated buff assignments.")
	elseif cmd == "reset" then
		self:ResetAssignments()
	elseif cmd == "status" then
		self:PrintStatus()
	elseif cmd == "nudge" then
		if self.ReminderPill then
			self.ReminderPill:ToggleNudgeBar()
		end
	elseif cmd == "options" or cmd == "opt" or cmd == "config" then
		if self.Options then
			self.Options:Toggle()
		end
	elseif cmd == "sync" then
		self:SyncGroup()
	elseif cmd == "rf" then
		local cfg = self.Assignments:GetPaladinSelfConfig()
		self.Assignments:SetRighteousFuryEnabled(not cfg.trackRF)
		self:RefreshUI()
		self:Print("Righteous Fury tracking: " .. (cfg.trackRF and "ON" or "OFF"))
	elseif cmd == "seal" then
		local vec = self.Capabilities:GetPlayerVector()
		local seals = (vec and vec.sealsList) or {}
		if #seals == 0 then
			self:Print("No Paladin Seals discovered on this character.")
		else
			local cfg = self.Assignments:GetPaladinSelfConfig()
			local nextIdx = 1
			for i, s in ipairs(seals) do
				if cfg.trackSeal and cfg.sealID == s.id then
					nextIdx = i + 1
					break
				end
			end
			if nextIdx > #seals then
				self.Assignments:SetSelectedSeal(nil)
				self:Print("Paladin Seal tracking: OFF")
			else
				self.Assignments:SetSelectedSeal(seals[nextIdx])
				self:Print("Paladin Seal set to: " .. seals[nextIdx].name)
			end
			self:RefreshUI()
		end
	else
		self:Print("Commands: /lbb [ui | lock | auto | reset | status | nudge | sync | rf | seal | options]")
	end
end

function LBB:OnEvent(event, ...)
	if event == "ADDON_LOADED" then
		local loadedName = ...
		if loadedName == "LittleBuffBoy" then
			self:InitDB()
			self.Comms:Init()
			self.Comms:OnChange(function(reason)
				if reason == "CAP" or reason == "RENEG" or reason == "PLPWR_SELF" then
					if self.DB.autoNegotiate ~= false then
						self:RunNegotiator(false)
					else
						self:RefreshUI()
					end
				else
					self:RefreshUI()
				end
			end)
			if self.BuffStrip then self.BuffStrip:Init() end
			if self.MatrixFrame then self.MatrixFrame:Init() end
			if self.RaidIndicators then self.RaidIndicators:Init() end
			if self.ReminderPill then self.ReminderPill:Init() end
		end
		return
	end

	if event == "PLAYER_ENTERING_WORLD" then
		self.Assignments:RefreshRosterFromGame()
		self.Capabilities:ScanPlayer()
		self.Tracking:Refresh({ clearDismiss = true })
		if self.DB and self.DB.autoNegotiate ~= false then
			self:RunNegotiator(false)
		end
		if self.ReminderPill then
			self.ReminderPill:UpdateProtPrompt()
		end
		self.Comms:BroadcastCapabilities()
		self.Comms:SendRequest()
		if not self.Comms:IsPallyPowerLoaded() then
			self.Comms:SendPLPWRSelf()
		end
		self:RefreshUI()
		return
	end

	if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED" then
		self.Assignments:RefreshRosterFromGame()
		if self.DB and self.DB.autoNegotiate ~= false then
			self:RunNegotiator(false)
		end
		if self.ReminderPill then
			self.ReminderPill:UpdateProtPrompt()
		end
		self.Comms:BroadcastCapabilities()
		self:RefreshUI()
		return
	end

	if event == "SPELLS_CHANGED" then
		self.Capabilities:ScanPlayer()
		if self.DB and self.DB.autoNegotiate ~= false then
			self:RunNegotiator(false)
		end
		self.Comms:BroadcastCapabilities()
		if not self.Comms:IsPallyPowerLoaded() then
			self.Comms:SendPLPWRSelf()
		end
		self:RefreshUI()
		return
	end

	if event == "SPELL_DATA_LOAD_RESULT" then
		local spellID, success = ...
		if self.Capabilities:OnSpellDataLoaded(spellID, success) then
			self:RefreshUI()
		end
		return
	end

	if event == "UNIT_AURA" then
		local unit = ...
		if unit and (unit == "player" or self.Assignments.rosterByUnit[unit]) then
			self:RefreshUI()
		end
		return
	end

	if event == "BAG_UPDATE_DELAYED" then
		self.Capabilities:ScanPlayer()
		self:RefreshUI()
		return
	end

	if event == "MINIMAP_UPDATE_TRACKING" then
		self.Tracking:Refresh()
		return
	end

	if event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
		self.Tracking:Refresh({ clearDismiss = true })
		self:RefreshUI()
		return
	end

	if event == "READY_CHECK" then
		self.Tracking:Refresh({ clearDismiss = true })
		if self.ReminderPill then
			self.ReminderPill:ShowNudgeBar(true)
		end
		return
	end

	if event == "PLAYER_REGEN_DISABLED" then
		-- Enter calm combat mode
		self:RefreshUI()
		return
	end

	if event == "PLAYER_REGEN_ENABLED" then
		-- Immediately flush any queued SecureActionButton attribute or layout updates
		self.Compat.FlushCombatQueue()
		self:RefreshUI()
		return
	end

	if event == "CHAT_MSG_ADDON" then
		local prefix, message, distribution, sender = ...
		self.Comms:OnAddonMessage(prefix, message, distribution, sender)
		return
	end
end

function LBB:Bootstrap()
	if self.eventFrame then
		return self.eventFrame
	end
	local f = _G.CreateFrame("Frame", "LittleBuffBoyEventFrame", _G.UIParent)
	-- Register ONLY WoW: Forever safe events (NEVER COMBAT_LOG_EVENT_UNFILTERED!)
	local events = {
		"ADDON_LOADED",
		"PLAYER_ENTERING_WORLD",
		"UNIT_AURA",
		"GROUP_ROSTER_UPDATE",
		"PLAYER_ROLES_ASSIGNED",
		"READY_CHECK",
		"PLAYER_REGEN_ENABLED",
		"PLAYER_REGEN_DISABLED",
		"SPELLS_CHANGED",
		"SPELL_DATA_LOAD_RESULT",
		"MINIMAP_UPDATE_TRACKING",
		"PLAYER_ALIVE",
		"PLAYER_UNGHOST",
		"BAG_UPDATE_DELAYED",
		"CHAT_MSG_ADDON",
	}
	for _, ev in ipairs(events) do
		f:RegisterEvent(ev)
	end
	f:SetScript("OnEvent", function(_, event, ...)
		self:OnEvent(event, ...)
	end)

	-- Lightweight periodic ticker for outbound comms queue & Buff Strip countdown timers
	local commAccum = 0
	local uiAccum = 0
	f:SetScript("OnUpdate", function(_, elapsed)
		elapsed = elapsed or 0
		commAccum = commAccum + elapsed
		uiAccum = uiAccum + elapsed
		if commAccum >= 0.25 then
			commAccum = 0
			if self.Comms and #self.Comms.sendQueue > 0 then
				self.Comms:ProcessQueue(self.Compat.GetTime())
			end
		end
		if uiAccum >= 1.0 then
			uiAccum = 0
			if self.BuffStrip and self.BuffStrip.frame and self.BuffStrip.frame:IsShown() then
				self.BuffStrip:Refresh()
			end
		end
	end)

	_G.SLASH_LITTLEBUFFBOY1 = "/lbb"
	_G.SLASH_LITTLEBUFFBOY2 = "/littlebuffboy"
	_G.SlashCmdList["LITTLEBUFFBOY"] = function(msg)
		self:HandleSlashCommand(msg)
	end

	self.eventFrame = f
	return f
end

-- Auto-bootstrap when loaded inside WoW (and harmless inside tests)
if _G.CreateFrame then
	LBB:Bootstrap()
end
