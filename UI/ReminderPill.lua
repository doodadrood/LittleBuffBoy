local addonName, LBB = ...
LBB = LBB or _G.LittleBuffBoy or {}
_G.LittleBuffBoy = LBB

local ReminderPill = {}
LBB.ReminderPill = ReminderPill

local pairs = pairs
local ipairs = ipairs
local tostring = tostring
local table_insert = table.insert
local table_sort = table.sort
local table_concat = table.concat

ReminderPill.trackPill = nil
ReminderPill.protPill = nil
ReminderPill.nudgeFrame = nil
ReminderPill.nudgeLines = {}
ReminderPill.lastReport = nil

-- =========================================================================
-- 1. Minimap Tracking One-Click Restore Pill
-- =========================================================================

local function saveFramePos(frame, key)
	if not frame or not LBB.CharDB then return end
	local point, _, relPoint, x, y = frame:GetPoint(1)
	if point then
		LBB.CharDB[key] = { point = point, relPoint = relPoint or point, x = x or 0, y = y or 0 }
	end
end

local function restoreFramePos(frame, key, defPoint, defX, defY)
	if not frame then return end
	frame:ClearAllPoints()
	local pos = LBB.CharDB and LBB.CharDB[key]
	if pos and pos.point then
		frame:SetPoint(pos.point, _G.UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
	else
		frame:SetPoint(defPoint, _G.UIParent, defPoint, defX or 0, defY or 0)
	end
end

function ReminderPill:InitTrackPill()
	if self.trackPill then
		return self.trackPill
	end
	local Theme = LBB.Theme
	local pill = _G.CreateFrame("Button", "LittleBuffBoyTrackingPill", _G.UIParent)
	pill:SetSize(230, 30)
	restoreFramePos(pill, "trackPillPos", "TOP", 0, -90)
	pill:SetMovable(true)
	pill:SetClampedToScreen(true)
	pill:EnableMouse(true)
	pill:RegisterForDrag("LeftButton")
	pill:RegisterForClicks("LeftButtonUp")
	Theme.ApplyPanel(pill, Theme.Colors.panel, Theme.Colors.warn)

	pill:SetScript("OnDragStart", function(self)
		if _G.IsShiftKeyDown and _G.IsShiftKeyDown() then
			self:StartMoving()
		end
	end)
	pill:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		saveFramePos(self, "trackPillPos")
	end)

	local icon = pill:CreateTexture(nil, "ARTWORK")
	icon:SetSize(20, 20)
	icon:SetPoint("LEFT", pill, "LEFT", 6, 0)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	pill._icon = icon

	local label = Theme.CreateFontString(pill, 11, "LEFT", Theme.Colors.text)
	label:SetPoint("LEFT", icon, "RIGHT", 6, 0)
	label:SetPoint("RIGHT", pill, "RIGHT", -24, 0)
	label:SetText("Restore Tracking")
	pill._label = label

	local closeBtn = Theme.CreateButton(pill, "x", 18, 18, function()
		LBB.Tracking:Dismiss()
		pill:Hide()
	end)
	closeBtn:SetPoint("RIGHT", pill, "RIGHT", -5, 0)
	closeBtn._tooltipText = "Dismiss until next login, revive, or Ready Check"

	pill:SetScript("OnClick", function()
		LBB.Tracking:RestorePreferred()
	end)
	pill:SetScript("OnEnter", function(self)
		Theme.SetBorderColor(self, Theme.Colors.accent)
		if _G.GameTooltip then
			_G.GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
			_G.GameTooltip:ClearLines()
			_G.GameTooltip:AddLine("Click to restore minimap tracking immediately.", 0.22, 0.74, 0.97)
			_G.GameTooltip:AddLine("Shift+Drag to move this reminder pill.", 0.7, 0.75, 0.82)
			_G.GameTooltip:Show()
		end
	end)
	pill:SetScript("OnLeave", function(self)
		Theme.SetBorderColor(self, Theme.Colors.warn)
		if _G.GameTooltip then _G.GameTooltip:Hide() end
	end)

	pill:Hide()
	self.trackPill = pill
	return pill
end

function ReminderPill:UpdateTrackingPill(status)
	if not self.trackPill then
		self:InitTrackPill()
	end
	status = status or LBB.Tracking:GetStatus()
	if status and status.needsRestore then
		if status.texture then
			self.trackPill._icon:SetTexture(status.texture)
		end
		self.trackPill._label:SetText("Restore Tracking: " .. tostring(status.name or ""))
		self.trackPill:Show()
	else
		self.trackPill:Hide()
	end
end

-- =========================================================================
-- 1b. Prot Paladin Opt-In Prompt Pill (auto-prompt when Tank role detected)
-- =========================================================================

function ReminderPill:InitProtPill()
	if self.protPill then
		return self.protPill
	end
	local Theme = LBB.Theme
	local pill = _G.CreateFrame("Frame", "LittleBuffBoyProtPromptPill", _G.UIParent)
	pill:SetSize(320, 32)
	pill:SetPoint("TOP", _G.UIParent, "TOP", 0, -126)
	pill:SetFrameStrata("DIALOG")
	Theme.ApplyPanel(pill, Theme.Colors.panel, Theme.Colors.accent)

	local lbl = Theme.CreateFontString(pill, 11, "LEFT", Theme.Colors.text)
	lbl:SetPoint("LEFT", pill, "LEFT", 10, 0)
	lbl:SetText("Tank Paladin: Enable Righteous Fury & Seal?")

	local btnYes = Theme.CreateButton(pill, "Enable", 52, 20, function()
		LBB.Assignments:EnableProtSelfDefaults()
		pill:Hide()
		LBB:RefreshUI()
	end)
	btnYes:SetPoint("RIGHT", pill, "RIGHT", -38, 0)

	local btnNo = Theme.CreateButton(pill, "No", 28, 20, function()
		LBB.Assignments:DismissProtRFPrompt()
		pill:Hide()
	end)
	btnNo:SetPoint("RIGHT", pill, "RIGHT", -6, 0)

	pill:Hide()
	self.protPill = pill
	return pill
end

function ReminderPill:UpdateProtPrompt()
	if not self.protPill then
		self:InitProtPill()
	end
	if LBB.Assignments and LBB.Assignments:ShouldPromptProtRF() then
		self.protPill:Show()
	else
		self.protPill:Hide()
	end
end

-- =========================================================================
-- 2. Ready Check & Manual "Nudge" Bar (with Smart Whisper)
-- =========================================================================

function ReminderPill:BuildSmartWhispers(report)
	report = report or self.lastReport
	local whispers = {}
	if not report or not report.missingByCaster then
		return whispers
	end
	local playerName = LBB.Capabilities.playerVector and LBB.Capabilities.playerVector.name or LBB.Compat.GetFullUnitName("player")
	local casters = {}
	for casterName in pairs(report.missingByCaster) do
		if casterName ~= playerName then
			table_insert(casters, casterName)
		end
	end
	table_sort(casters)

	for _, casterName in ipairs(casters) do
		local duties = report.missingByCaster[casterName]
		if duties and #duties > 0 then
			local parts = {}
			for _, d in ipairs(duties) do
				table_insert(parts, string.format("%s (%d missing)", d.fullName or d.familyName, d.missingCount))
			end
			local msg = "[LittleBuffBoy] Friendly buff reminder: " .. table_concat(parts, ", ") .. "."
			table_insert(whispers, {
				target = casterName,
				message = msg,
			})
		end
	end
	return whispers
end

function ReminderPill:SendSmartWhispers(report)
	local whispers = self:BuildSmartWhispers(report)
	local sent = 0
	for _, w in ipairs(whispers) do
		-- Sends concise individual whispers ONLY (never spams /raid or /party!)
		if LBB.Compat.SendChatMessage(w.message, "WHISPER", nil, w.target) then
			sent = sent + 1
		end
	end
	return sent, whispers
end

function ReminderPill:InitNudgeBar()
	if self.nudgeFrame then
		return self.nudgeFrame
	end
	local Theme = LBB.Theme
	local f = _G.CreateFrame("Frame", "LittleBuffBoyNudgeFrame", _G.UIParent)
	f:SetSize(340, 220)
	restoreFramePos(f, "nudgePos", "TOP", 0, -135)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetFrameStrata("FULLSCREEN_DIALOG")
	if f.SetFrameLevel then f:SetFrameLevel(20) end
	if f.SetToplevel then f:SetToplevel(true) end
	Theme.ApplyDropShadow(f)
	Theme.ApplyPanel(f, Theme.Colors.windowBg, Theme.Colors.accent)

	f:SetScript("OnDragStart", function(self) self:StartMoving() end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		saveFramePos(self, "nudgePos")
	end)

	local header = _G.CreateFrame("Frame", nil, f)
	header:SetHeight(26)
	header:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
	header:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
	Theme.ApplyPanel(header, Theme.Colors.header, Theme.Colors.border)

	local title = Theme.CreateFontString(header, 12, "LEFT", Theme.Colors.accent)
	title:SetPoint("LEFT", header, "LEFT", 8, 0)
	title:SetText("LittleBuffBoy  |cff94a3b8Readiness & Nudge|r")

	local closeBtn = Theme.CreateButton(header, "X", 22, 18, function() f:Hide() end)
	closeBtn:SetPoint("RIGHT", header, "RIGHT", -5, 0)

	local body = _G.CreateFrame("Frame", nil, f)
	body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 8, -6)
	body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 36)
	f._body = body

	-- Footer buttons
	local btnWhisper = Theme.CreateButton(f, "Smart Whisper", 116, 24, function()
		local sent = self:SendSmartWhispers(self.lastReport)
		if LBB.Print then
			if sent > 0 then
				LBB:Print("Sent concise buff reminders to " .. tostring(sent) .. " caster(s).")
			else
				LBB:Print("No other casters currently have missing assigned buffs.")
			end
		end
	end)
	btnWhisper:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 6)
	btnWhisper._tooltipText = "Sends one polite whisper ONLY to casters with uncast assigned buffs (never spams /raid)."
	f._btnWhisper = btnWhisper

	local btnRestoreTrack = Theme.CreateButton(f, "Restore Tracking", 112, 24, function()
		LBB.Tracking:RestorePreferred()
		self:RefreshNudgeBar()
	end)
	btnRestoreTrack:SetPoint("LEFT", btnWhisper, "RIGHT", 6, 0)
	f._btnRestoreTrack = btnRestoreTrack

	local btnRefresh = Theme.CreateButton(f, "Refresh", 64, 24, function()
		self:RefreshNudgeBar()
	end)
	btnRefresh:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 6)

	f:Hide()
	self.nudgeFrame = f
	return f
end

function ReminderPill:RefreshNudgeBar()
	if not self.nudgeFrame then
		self:InitNudgeBar()
	end
	local Theme = LBB.Theme
	for _, line in ipairs(self.nudgeLines) do
		line:Hide()
	end
	self.nudgeLines = {}

	local report = LBB.Scanner:BuildReadinessReport(LBB.Assignments.roster, LBB.Assignments)
	self.lastReport = report
	local trackStatus = LBB.Tracking:GetStatus()

	local lines = {}

	-- 1. Self Tracking
	if trackStatus.hasPreferred and not trackStatus.isActive then
		table_insert(lines, "|cfffbbf24Tracking Missing:|r " .. tostring(trackStatus.name))
		self.nudgeFrame._btnRestoreTrack:Show()
	else
		self.nudgeFrame._btnRestoreTrack:Hide()
	end

	-- 2. Self Consumables
	local pc = report.playerConsumables or {}
	local missingCons = {}
	if not pc.WELL_FED then table_insert(missingCons, "Well Fed") end
	if not pc.FLASK_ELIXIR then table_insert(missingCons, "Flask/Elixir") end
	if not pc.WEAPON_OIL then table_insert(missingCons, "Weapon Oil/Stone") end
	if #missingCons > 0 then
		table_insert(lines, "|cfffbbf24Your Consumables:|r " .. table_concat(missingCons, ", "))
	else
		table_insert(lines, "|cff34d399Your Consumables:|r All active")
	end

	-- 3. Missing Raid Buffs grouped by caster
	local casterNames = {}
	for cName in pairs(report.missingByCaster) do
		table_insert(casterNames, cName)
	end
	table_sort(casterNames)

	if #casterNames == 0 then
		table_insert(lines, "|cff34d399Raid Buffs:|r All assigned buffs covered!")
	else
		table_insert(lines, "|cff38bdf8Missing Duties By Caster:|r")
		for _, cName in ipairs(casterNames) do
			local parts = {}
			for _, d in ipairs(report.missingByCaster[cName]) do
				table_insert(parts, string.format("%s (%d)", d.familyName, d.missingCount))
			end
			local m = LBB.Assignments.rosterByName[cName]
			local colored = Theme.ColorizeName(cName, m and m.class or nil)
			table_insert(lines, "  " .. colored .. ": " .. table_concat(parts, ", "))
		end
	end

	local y = 2
	for _, txt in ipairs(lines) do
		local fs = Theme.CreateFontString(self.nudgeFrame._body, 11, "LEFT", Theme.Colors.text)
		fs:SetPoint("TOPLEFT", self.nudgeFrame._body, "TOPLEFT", 2, -y)
		fs:SetPoint("RIGHT", self.nudgeFrame._body, "RIGHT", -2, 0)
		fs:SetText(txt)
		table_insert(self.nudgeLines, fs)
		y = y + 18
	end

	local targetH = math.max(130, y + 76)
	self.nudgeFrame:SetHeight(targetH)
	return report
end

function ReminderPill:ShowNudgeBar(onlyIfMissing)
	local report = self:RefreshNudgeBar()
	local trackStatus = LBB.Tracking:GetStatus()
	local pc = report.playerConsumables or {}
	local hasIssue = (report.totalMissingBuffs > 0)
		or (trackStatus.hasPreferred and not trackStatus.isActive)
		or (not pc.WELL_FED or not pc.FLASK_ELIXIR or not pc.WEAPON_OIL)

	if onlyIfMissing and not hasIssue then
		return false
	end
	self.nudgeFrame:Show()
	if self.nudgeFrame.Raise then
		self.nudgeFrame:Raise()
	end
	return true
end

function ReminderPill:ToggleNudgeBar()
	if not self.nudgeFrame then
		self:InitNudgeBar()
	end
	if self.nudgeFrame:IsShown() then
		self.nudgeFrame:Hide()
	else
		self:ShowNudgeBar(false)
	end
end

function ReminderPill:Init()
	self:InitTrackPill()
	self:InitProtPill()
	self:InitNudgeBar()
	LBB.Tracking:OnStatusChanged(function(status)
		self:UpdateTrackingPill(status)
	end)
end
