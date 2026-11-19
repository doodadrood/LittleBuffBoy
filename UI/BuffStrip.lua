local addonName, LBB = ...
LBB = LBB or _G.LittleBuffBoy or {}
_G.LittleBuffBoy = LBB

local BuffStrip = {}
LBB.BuffStrip = BuffStrip

local ipairs = ipairs
local pairs = pairs
local tostring = tostring
local table_insert = table.insert
local table_concat = table.concat

BuffStrip.frame = nil
BuffStrip.tiles = {}
BuffStrip.lastEvals = {}

local TILE_W = 44
local TILE_H = 48
local HEADER_W = 24
local PAD = 4

local function savePosition(frame)
	if not frame or not LBB.CharDB then
		return
	end
	local point, _, relPoint, x, y = frame:GetPoint(1)
	if point then
		LBB.CharDB.stripPos = {
			point = point,
			relPoint = relPoint or point,
			x = x or 0,
			y = y or 0,
		}
	end
end

local function restorePosition(frame)
	if not frame then
		return
	end
	frame:ClearAllPoints()
	local pos = LBB.CharDB and LBB.CharDB.stripPos
	if pos and pos.point then
		frame:SetPoint(pos.point, _G.UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
	else
		frame:SetPoint("CENTER", _G.UIParent, "CENTER", 0, -140)
	end
end

local function formatDutyScope(duty)
	if duty.kind == "GROUP_BUFF" and duty.subgroups then
		local parts = {}
		for _, sg in ipairs(duty.subgroups) do
			table_insert(parts, "G" .. tostring(sg))
		end
		return table_concat(parts, ", ")
	elseif duty.kind == "CLASS_BUFF" and duty.classes then
		local parts = {}
		for _, cls in ipairs(duty.classes) do
			local info = LBB.Catalog.CLASS_INFO[cls]
			table_insert(parts, info and info.short or cls)
		end
		return table_concat(parts, ", ")
	elseif duty.kind == "TARGET_BUFF" and duty.targets then
		return table_concat(duty.targets, ", ")
	elseif duty.kind == "PALADIN_AURA" then
		return "Party Aura"
	elseif duty.kind == "SHAMAN_TOTEM" then
		return duty.element .. " Totem"
	end
	return ""
end

local function createTile(parent, index)
	local Theme = LBB.Theme
	local btn = _G.CreateFrame("Button", "LittleBuffBoyStripTile" .. index, parent, "SecureActionButtonTemplate")
	btn:SetSize(TILE_W, TILE_H)
	btn:RegisterForClicks("AnyUp", "AnyDown")
	Theme.ApplyPanel(btn, Theme.Colors.tile, Theme.Colors.border)

	local icon = btn:CreateTexture(nil, "ARTWORK")
	icon:SetSize(30, 30)
	icon:SetPoint("TOP", btn, "TOP", 0, -3)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	btn._icon = icon

	local statusBar = btn:CreateTexture(nil, "ARTWORK")
	statusBar:SetHeight(3)
	statusBar:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 1, 1)
	statusBar:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
	btn._statusBar = statusBar

	local badge = Theme.CreateFontString(btn, 11, "RIGHT", Theme.Colors.text)
	badge:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -3, -2)
	btn._badge = badge

	local reagent = Theme.CreateFontString(btn, 9, "LEFT", Theme.Colors.warn)
	reagent:SetPoint("TOPLEFT", btn, "TOPLEFT", 3, -2)
	btn._reagent = reagent

	local timer = Theme.CreateFontString(btn, 10, "CENTER", Theme.Colors.text)
	timer:SetPoint("BOTTOM", btn, "BOTTOM", 0, 5)
	btn._timer = timer

	local lockDot = btn:CreateTexture(nil, "OVERLAY")
	lockDot:SetSize(5, 5)
	lockDot:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 5)
	lockDot:SetColorTexture(Theme.Colors.locked[1], Theme.Colors.locked[2], Theme.Colors.locked[3], 1)
	lockDot:Hide()
	btn._lockDot = lockDot

	btn:SetScript("OnEnter", function(self)
		local eval = self._eval
		if not eval or not _G.GameTooltip then
			return
		end
		local duty = eval.duty
		local fam = duty.familyID and LBB.Catalog.GetFamily(duty.familyID)
		local title = eval.singleSpellName or (fam and fam.name) or duty.key

		_G.GameTooltip:SetOwner(self, "ANCHOR_TOP")
		_G.GameTooltip:ClearLines()
		_G.GameTooltip:AddLine(title, 0.22, 0.74, 0.97)
		_G.GameTooltip:AddDoubleLine("Assigned:", formatDutyScope(duty), 0.7, 0.75, 0.82, 1, 1, 1)
		_G.GameTooltip:AddDoubleLine("Coverage:", string.format("%d / %d buffed (%d missing)",
			eval.buffedCount, eval.totalEligible, eval.missingCount), 0.7, 0.75, 0.82, 1, 1, 1)
		if eval.nextTarget then
			_G.GameTooltip:AddDoubleLine("Next target:", eval.nextTarget.name, 0.7, 0.75, 0.82, 0.2, 0.9, 0.5)
		end
		if eval.reagentCount ~= nil then
			local rColor = eval.lowReagent and { 0.98, 0.35, 0.3 } or { 0.8, 0.85, 0.9 }
			_G.GameTooltip:AddDoubleLine("Reagents:", tostring(eval.reagentCount), 0.7, 0.75, 0.82, rColor[1], rColor[2], rColor[3])
		end
		_G.GameTooltip:AddLine(" ")
		_G.GameTooltip:AddLine("Left-Click: Cast on next target (keeps current target)", 0.65, 0.85, 1.0)
		if eval.hasGroup and eval.groupSpellName then
			local rec = eval.recommendGroup and " [Recommended]" or ""
			_G.GameTooltip:AddLine("Right-Click: " .. eval.groupSpellName .. rec, 0.5, 0.95, 0.6)
		end
		_G.GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function()
		if _G.GameTooltip then
			_G.GameTooltip:Hide()
		end
	end)

	return btn
end

function BuffStrip:Init()
	if self.frame then
		return self.frame
	end
	local Theme = LBB.Theme
	local f = _G.CreateFrame("Frame", "LittleBuffBoyStripFrame", _G.UIParent)
	f:SetSize(HEADER_W + PAD * 2 + TILE_W, TILE_H + PAD * 2)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	Theme.ApplyPanel(f, Theme.Colors.bg, Theme.Colors.border)

	f:SetScript("OnDragStart", function(self)
		if not (LBB.DB and LBB.DB.locked) then
			self:StartMoving()
		end
	end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		savePosition(self)
	end)

	-- Compact side control column (Matrix, Nudge, Lock)
	local ctrl = _G.CreateFrame("Frame", nil, f)
	ctrl:SetSize(HEADER_W, TILE_H)
	ctrl:SetPoint("LEFT", f, "LEFT", PAD, 0)
	Theme.ApplyPanel(ctrl, Theme.Colors.header, Theme.Colors.border)
	f._ctrl = ctrl

	local btnMatrix = Theme.CreateButton(ctrl, "M", 20, 14, function()
		if LBB.MatrixFrame then
			LBB.MatrixFrame:Toggle()
		end
	end)
	btnMatrix:SetPoint("TOP", ctrl, "TOP", 0, -2)
	btnMatrix._tooltipText = "Toggle Assignment Matrix (/lbb)"
	f._btnMatrix = btnMatrix

	local btnNudge = Theme.CreateButton(ctrl, "!", 20, 14, function()
		if LBB.ReminderPill then
			LBB.ReminderPill:ToggleNudgeBar()
		end
	end)
	btnNudge:SetPoint("CENTER", ctrl, "CENTER", 0, 0)
	btnNudge._tooltipText = "Ready Check & Smart Whisper Nudge (/lbb nudge)"
	f._btnNudge = btnNudge

	local btnLock = Theme.CreateButton(ctrl, "U", 20, 14, function()
		if LBB.ToggleLock then
			LBB:ToggleLock()
		end
	end)
	btnLock:SetPoint("BOTTOM", ctrl, "BOTTOM", 0, 2)
	btnLock._tooltipText = "Lock / Unlock Buff Strip (/lbb lock)"
	f._btnLock = btnLock

	-- Fallback compact label when character has no active duties (e.g. solo non-buffer)
	local idleText = Theme.CreateFontString(f, 10, "CENTER", Theme.Colors.muted)
	idleText:SetPoint("LEFT", ctrl, "RIGHT", 6, 0)
	idleText:SetText("LBB")
	idleText:Hide()
	f._idleText = idleText

	self.frame = f
	restorePosition(f)
	self:UpdateLockVisual()
	return f
end

function BuffStrip:UpdateLockVisual()
	if not self.frame or not self.frame._btnLock then
		return
	end
	local locked = LBB.DB and LBB.DB.locked
	self.frame._btnLock._label:SetText(locked and "L" or "U")
	local c = locked and LBB.Theme.Colors.locked or LBB.Theme.Colors.muted
	self.frame._btnLock._label:SetTextColor(c[1], c[2], c[3], 1)
end

function BuffStrip:Refresh()
	if not self.frame then
		self:Init()
	end
	local Compat = LBB.Compat
	local Theme = LBB.Theme
	local inCombat = Compat.InCombat()

	local vec = LBB.Capabilities:GetPlayerVector()
	local playerName = vec and vec.name or Compat.GetFullUnitName("player")
	local duties = LBB.Assignments:GetPlayerDuties(playerName)

	-- If PallyPower is loaded, do not render Paladin Blessing / Aura buttons on the Buff Strip
	local filtered = {}
	local ppYield = LBB.Comms and LBB.Comms:IsPallyPowerLoaded()
	for _, duty in ipairs(duties) do
		if not (ppYield and (duty.kind == "CLASS_BUFF" or duty.kind == "PALADIN_AURA")) then
			table_insert(filtered, duty)
		end
	end

	local vertical = LBB.DB and LBB.DB.stripOrientation == "VERTICAL"
	local scale = (LBB.DB and LBB.DB.stripScale) or 1.0
	if not inCombat and self.frame.SetScale then
		self.frame:SetScale(scale)
	end

	self.lastEvals = {}
	local count = #filtered

	for i, duty in ipairs(filtered) do
		local tile = self.tiles[i]
		if not tile then
			tile = createTile(self.frame, i)
			self.tiles[i] = tile
		end
		local eval = LBB.Scanner:EvaluateDuty(duty, LBB.Assignments.roster)
		self.lastEvals[duty.key] = eval
		tile._eval = eval

		-- Visual updates (safe in & out of combat)
		if eval.icon then
			tile._icon:SetTexture(eval.icon)
		end

		local statusColor
		if inCombat then
			-- Calm combat mode: suppress low-timer amber nagging; highlight only missing or critical drops
			if eval.missingCount > 0 then
				statusColor = Theme.Colors.danger
				tile._badge:SetText(tostring(eval.missingCount))
				tile._badge:SetTextColor(Theme.Colors.danger[1], Theme.Colors.danger[2], Theme.Colors.danger[3], 1)
				tile._timer:SetText("MISS")
			else
				statusColor = Theme.Colors.good
				tile._badge:SetText("OK")
				tile._badge:SetTextColor(Theme.Colors.good[1], Theme.Colors.good[2], Theme.Colors.good[3], 1)
				tile._timer:SetText(Theme.FormatTimer(eval.shortestRemaining))
			end
		else
			if eval.missingCount > 0 then
				statusColor = Theme.Colors.danger
				tile._badge:SetText(tostring(eval.missingCount))
				tile._badge:SetTextColor(Theme.Colors.danger[1], Theme.Colors.danger[2], Theme.Colors.danger[3], 1)
				tile._timer:SetText(eval.shortestRemaining and eval.shortestRemaining > 0 and Theme.FormatTimer(eval.shortestRemaining) or "MISS")
			elseif eval.expiringCount > 0 then
				statusColor = Theme.Colors.warn
				tile._badge:SetText(tostring(eval.expiringCount))
				tile._badge:SetTextColor(Theme.Colors.warn[1], Theme.Colors.warn[2], Theme.Colors.warn[3], 1)
				tile._timer:SetText(Theme.FormatTimer(eval.shortestRemaining))
			else
				statusColor = Theme.Colors.good
				tile._badge:SetText("OK")
				tile._badge:SetTextColor(Theme.Colors.good[1], Theme.Colors.good[2], Theme.Colors.good[3], 1)
				tile._timer:SetText(Theme.FormatTimer(eval.shortestRemaining))
			end
		end

		tile._statusBar:SetColorTexture(statusColor[1], statusColor[2], statusColor[3], 1)
		Theme.SetBorderColor(tile, eval.missingCount > 0 and Theme.Colors.danger or (eval.recommendGroup and Theme.Colors.accent or Theme.Colors.border))
		tile._icon:SetDesaturated(eval.missingCount == 0 and eval.expiringCount == 0)

		if eval.lowReagent and eval.reagentCount ~= nil then
			tile._reagent:SetText(tostring(eval.reagentCount))
			tile._reagent:Show()
		else
			tile._reagent:Hide()
		end

		if duty.locked then
			tile._lockDot:Show()
		else
			tile._lockDot:Hide()
		end

		-- SecureActionButton attributes (ALWAYS routed through Combat Lockdown Queue!)
		local targetUnit = (eval.nextTarget and eval.nextTarget.unit) or "player"
		local singleSpell = eval.singleSpellName or ""
		local groupSpell = (eval.hasGroup and eval.groupSpellName) or singleSpell

		Compat.SetSecureAttribute(tile, "type1", "spell")
		Compat.SetSecureAttribute(tile, "spell1", singleSpell)
		Compat.SetSecureAttribute(tile, "type2", "spell")
		Compat.SetSecureAttribute(tile, "spell2", groupSpell)

		if duty.kind == "PALADIN_AURA" or duty.kind == "SHAMAN_TOTEM" or duty.familyID == "BATTLE_SHOUT" then
			Compat.SetSecureAttribute(tile, "unit1", "player")
			Compat.SetSecureAttribute(tile, "unit2", "player")
		else
			Compat.SetSecureAttribute(tile, "unit1", targetUnit)
			Compat.SetSecureAttribute(tile, "unit2", targetUnit)
		end

		-- Layout updates must also wait until out of combat for secure buttons
		local idx = i
		Compat.RunOutOfCombat("strip_layout_" .. idx, function()
			tile:ClearAllPoints()
			if vertical then
				tile:SetPoint("TOP", self.frame, "TOP", 0, -(PAD + HEADER_W + 4 + (idx - 1) * (TILE_H + PAD)))
			else
				tile:SetPoint("LEFT", self.frame, "LEFT", PAD + HEADER_W + PAD + (idx - 1) * (TILE_W + PAD), 0)
			end
			tile:Show()
		end)
	end

	-- Hide unused tiles out of combat
	for i = count + 1, #self.tiles do
		local tile = self.tiles[i]
		Compat.RunOutOfCombat("strip_hide_" .. i, function()
			tile:Hide()
		end)
	end

	-- Resize container frame out of combat
	Compat.RunOutOfCombat("strip_frame_size", function()
		if count == 0 then
			self.frame._idleText:Show()
			self.frame:SetSize(HEADER_W + 42, TILE_H + PAD * 2)
		else
			self.frame._idleText:Hide()
			if vertical then
				self.frame:SetSize(TILE_W + PAD * 2, HEADER_W + PAD * 2 + count * (TILE_H + PAD) + 4)
			else
				self.frame:SetSize(HEADER_W + PAD * 2 + count * (TILE_W + PAD) + PAD, TILE_H + PAD * 2)
			end
		end
	end)
end
