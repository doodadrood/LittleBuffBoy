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

-- Human-readable labels for WoW Keybindings UI (Bindings.xml)
_G.BINDING_HEADER_LITTLEBUFFBOY = "LittleBuffBoy"
_G["BINDING_NAME_CLICK LittleBuffBoyAutoBuffBtn:LeftButton"] = "Smart Buff Next Missing (Single)"
_G["BINDING_NAME_CLICK LittleBuffBoyAutoBuffBtn:RightButton"] = "Smart Buff Next Missing (Group/Greater)"
_G.BINDING_NAME_LITTLEBUFFBOY_MATRIX = "Toggle Assignment Matrix"

BuffStrip.frame = nil
BuffStrip.autoTile = nil
BuffStrip.tiles = {}
BuffStrip.lastEvals = {}
BuffStrip.lastAutoAction = nil
BuffStrip.isHovered = false

local TILE_W = 44
local TILE_H = 48
local HEADER_W = 24
local PAD = 4

-- Blizzard Restricted Environment OnClick pre-script:
-- Allows SecureActionButtonTemplate to rotate across eligible alive party/raid members (and @mouseover)
-- DURING combat lockdown (where normal Lua SetAttribute is blocked)!
-- Strictly zero table constructors (`{}`), zero `function` definitions, and RestrictedEnvironment globals only.
local COMBAT_CLICK_PRE_SNIPPET = [[
	if down then
		self:SetAttribute("combat_had_down", true)
	else
		if self:GetAttribute("combat_had_down") then
			self:SetAttribute("combat_had_down", false)
			return
		end
	end
	if not PlayerInCombat() then
		self:SetAttribute("combat_idx", 0)
		return
	end
	local list = self:GetAttribute("combat_units")
	if not list or list == "" then
		return
	end
	if list == "player" then
		self:SetAttribute("unit1", "player")
		self:SetAttribute("unit2", "player")
		return
	end
	local mo = SecureCmdOptionParse("[@mouseover,help,nodead] mouseover")
	if mo and mo ~= "" then
		if button == "RightButton" then
			self:SetAttribute("unit2", mo)
		else
			self:SetAttribute("unit1", mo)
		end
		return
	end
	local count = 0
	local firstValid = nil
	local pos = 1
	local len = strlen(list)
	while pos <= len do
		local comma = strfind(list, ",", pos, true)
		local u
		if comma then
			u = strsub(list, pos, comma - 1)
			pos = comma + 1
		else
			u = strsub(list, pos)
			pos = len + 1
		end
		if u ~= "" then
			local parsed = SecureCmdOptionParse("[@" .. u .. ",help,nodead] " .. u)
			if parsed and parsed ~= "" then
				count = count + 1
				if not firstValid then
					firstValid = u
				end
			end
		end
	end
	if count > 0 then
		if button == "RightButton" then
			self:SetAttribute("unit2", firstValid)
			return
		end
		local idx = (self:GetAttribute("combat_idx") or 0) + 1
		if idx > count then
			idx = 1
		end
		local chosen = firstValid
		local seen = 0
		pos = 1
		while pos <= len do
			local comma = strfind(list, ",", pos, true)
			local u
			if comma then
				u = strsub(list, pos, comma - 1)
				pos = comma + 1
			else
				u = strsub(list, pos)
				pos = len + 1
			end
			if u ~= "" then
				local parsed = SecureCmdOptionParse("[@" .. u .. ",help,nodead] " .. u)
				if parsed and parsed ~= "" then
					seen = seen + 1
					if seen == idx then
						chosen = u
						break
					end
				end
			end
		end
		self:SetAttribute("combat_idx", idx)
		self:SetAttribute("unit1", chosen)
		self:SetAttribute("unit2", firstValid)
	end
]]

function BuffStrip:WrapSecureButton(btn)
	if not btn or btn._lbbWrapped then
		return
	end
	LBB.Compat.RunOutOfCombat("wrap_secure_" .. tostring(btn:GetName() or btn), function()
		if btn._lbbWrapped then
			return
		end
		if not self.secureHeader and _G.CreateFrame then
			local ok, hdr = pcall(_G.CreateFrame, "Frame", "LittleBuffBoySecureHeader", _G.UIParent, "SecureHandlerBaseTemplate")
			if ok and hdr then
				self.secureHeader = hdr
			end
		end
		if self.secureHeader and _G.SecureHandlerWrapScript then
			local ok = pcall(_G.SecureHandlerWrapScript, btn, "OnClick", self.secureHeader, COMBAT_CLICK_PRE_SNIPPET)
			if ok then
				btn._lbbWrapped = true
			end
		end
	end)
end

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
	elseif duty.kind == "CLASS_BUFF" then
		local parts = {}
		for _, cls in ipairs(duty.classes or {}) do
			local info = LBB.Catalog.CLASS_INFO[cls]
			table_insert(parts, info and info.short or cls)
		end
		if duty.overrideTargets and #duty.overrideTargets > 0 then
			table_insert(parts, "+" .. table_concat(duty.overrideTargets, ", "))
		end
		return table_concat(parts, ", ")
	elseif duty.kind == "TARGET_BUFF" and duty.targets then
		return table_concat(duty.targets, ", ")
	elseif duty.kind == "PALADIN_AURA" then
		return "Party Aura"
	elseif duty.kind == "RIGHTEOUS_FURY" then
		return "Self (Prot Tank)"
	elseif duty.kind == "PALADIN_SEAL" then
		return "Self (Active Seal)"
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
			local rangeTag = (eval.nextTarget.inRange == false) and " (Out of Range)" or ""
			local tColor = (eval.nextTarget.inRange == false) and { 0.98, 0.72, 0.18 } or { 0.2, 0.9, 0.5 }
			_G.GameTooltip:AddDoubleLine("Next target:", eval.nextTarget.name .. rangeTag, 0.7, 0.75, 0.82, tColor[1], tColor[2], tColor[3])
		elseif eval.effectiveTarget and eval.effectiveTarget.name then
			_G.GameTooltip:AddDoubleLine("Pre-staged target:", eval.effectiveTarget.name, 0.7, 0.75, 0.82, 0.5, 0.85, 1.0)
		end
		if eval.reagentCount ~= nil then
			local rColor = eval.lowReagent and { 0.98, 0.35, 0.3 } or { 0.8, 0.85, 0.9 }
			_G.GameTooltip:AddDoubleLine("Reagents:", tostring(eval.reagentCount), 0.7, 0.75, 0.82, rColor[1], rColor[2], rColor[3])
		end
		_G.GameTooltip:AddLine(" ")
		if duty.kind == "RIGHTEOUS_FURY" or duty.kind == "PALADIN_SEAL" then
			_G.GameTooltip:AddLine("Left-Click: Cast on self", 0.65, 0.85, 1.0)
			if LBB.NativeAuras and LBB.NativeAuras:IsBound(self._timer) then
				_G.GameTooltip:AddLine("Combat timer: Native Blizzard AuraContainer active", 0.5, 0.95, 0.6)
			end
		else
			_G.GameTooltip:AddLine("Left-Click: Cast on next target (keeps current target)", 0.65, 0.85, 1.0)
			if eval.hasGroup and eval.groupSpellName then
				local rec = eval.recommendGroup and " [Recommended]" or ""
				_G.GameTooltip:AddLine("Right-Click: " .. eval.groupSpellName .. rec, 0.5, 0.95, 0.6)
				if eval.hasClassOverride then
					_G.GameTooltip:AddLine("Override active: Cast Greater first, then single override.", 0.98, 0.72, 0.18)
				end
			end
		end
		_G.GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function()
		if _G.GameTooltip then
			_G.GameTooltip:Hide()
		end
	end)
	btn:SetScript("PostClick", function(selfBtn)
		local eval = selfBtn._eval
		local et = eval and (eval.effectiveTarget or eval.nextTarget)
		if eval and et and eval.duty and LBB.Scanner then
			local actualUnit = (selfBtn.GetAttribute and selfBtn:GetAttribute("unit1")) or et.unit
			local member = LBB.Assignments and LBB.Assignments.rosterByUnit and LBB.Assignments.rosterByUnit[actualUnit]
			local actualName = (member and member.name) or (actualUnit == et.unit and et.name) or actualUnit
			local rotated = LBB.Scanner:RecordCastAttempt(actualUnit, actualName, eval.duty.key)
			if rotated then
				BuffStrip:Refresh()
			end
		end
	end)

	BuffStrip:WrapSecureButton(btn)
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
	f:SetScript("OnEnter", function()
		self.isHovered = true
		if self.frame and self.frame.SetAlpha then
			self.frame:SetAlpha(1.0)
		end
	end)
	f:SetScript("OnLeave", function()
		self.isHovered = false
		self:ApplyHealthyVisibility()
	end)

	-- Dedicated One-Click Smart Auto-Buff tile (also bound via Bindings.xml -> LittleBuffBoyAutoBuffBtn)
	local autoTile = _G.CreateFrame("Button", "LittleBuffBoyAutoBuffBtn", f, "SecureActionButtonTemplate")
	autoTile:SetSize(TILE_W, TILE_H)
	autoTile:RegisterForClicks("AnyUp", "AnyDown")
	Theme.ApplyPanel(autoTile, Theme.Colors.header, Theme.Colors.accent)

	local aIcon = autoTile:CreateTexture(nil, "ARTWORK")
	aIcon:SetSize(30, 30)
	aIcon:SetPoint("TOP", autoTile, "TOP", 0, -3)
	aIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	aIcon:SetTexture("Interface\\AddOns\\LittleBuffBoy\\Media\\MinimapIcon")
	autoTile._icon = aIcon

	local aBar = autoTile:CreateTexture(nil, "ARTWORK")
	aBar:SetHeight(3)
	aBar:SetPoint("BOTTOMLEFT", autoTile, "BOTTOMLEFT", 1, 1)
	aBar:SetPoint("BOTTOMRIGHT", autoTile, "BOTTOMRIGHT", -1, 1)
	autoTile._statusBar = aBar

	local aBadge = Theme.CreateFontString(autoTile, 11, "RIGHT", Theme.Colors.accent)
	aBadge:SetPoint("TOPRIGHT", autoTile, "TOPRIGHT", -3, -2)
	autoTile._badge = aBadge

	local aTimer = Theme.CreateFontString(autoTile, 9, "CENTER", Theme.Colors.accent)
	aTimer:SetPoint("BOTTOM", autoTile, "BOTTOM", 0, 5)
	aTimer:SetText("AUTO")
	autoTile._timer = aTimer

	autoTile:SetScript("OnEnter", function(selfBtn)
		self.isHovered = true
		if self.frame and self.frame.SetAlpha then
			self.frame:SetAlpha(1.0)
		end
		if not _G.GameTooltip then return end
		local act = self.lastAutoAction
		_G.GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
		_G.GameTooltip:ClearLines()
		_G.GameTooltip:AddLine("Smart Auto-Buff (Bindable Hotkey)", 0.22, 0.74, 0.97)
		if act and act.hasAction then
			_G.GameTooltip:AddDoubleLine("Next Spell:", tostring(act.singleSpell), 0.7, 0.75, 0.82, 0.2, 0.9, 0.5)
			_G.GameTooltip:AddDoubleLine("Next Unit:", tostring(act.unit), 0.7, 0.75, 0.82, 1, 1, 1)
			_G.GameTooltip:AddDoubleLine("Remaining:", string.format("%d missing, %d expiring", act.totalMissing, act.totalExpiring), 0.7, 0.75, 0.82, 0.98, 0.72, 0.18)
		else
			_G.GameTooltip:AddLine("All assigned buffs are active and healthy!", 0.2, 0.85, 0.45)
		end
		_G.GameTooltip:AddLine(" ")
		_G.GameTooltip:AddLine("Left-Click / Hotkey: Cast single target on next priority unit", 0.65, 0.85, 1.0)
		_G.GameTooltip:AddLine("Right-Click / Hotkey: Cast group/greater spell", 0.5, 0.95, 0.6)
		_G.GameTooltip:Show()
	end)
	autoTile:SetScript("OnLeave", function()
		self.isHovered = false
		self:ApplyHealthyVisibility()
		if _G.GameTooltip then _G.GameTooltip:Hide() end
	end)
	autoTile:SetScript("PostClick", function(selfBtn)
		local act = self.lastAutoAction
		if act and act.nextDuty and LBB.Scanner then
			local actualUnit = (selfBtn and selfBtn.GetAttribute and selfBtn:GetAttribute("unit1")) or act.unit
			local member = LBB.Assignments and LBB.Assignments.rosterByUnit and LBB.Assignments.rosterByUnit[actualUnit]
			local actualName = (member and member.name) or (actualUnit == act.unit and act.targetName) or actualUnit
			local rotated = LBB.Scanner:RecordCastAttempt(actualUnit, actualName, act.nextDuty.key)
			if rotated then
				self:Refresh()
			end
		end
	end)
	self:WrapSecureButton(autoTile)
	autoTile:Hide()
	self.autoTile = autoTile

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

function BuffStrip:ApplyHealthyVisibility()
	if not self.frame then
		return
	end
	local mode = (LBB.DB and LBB.DB.stripHealthyMode) or "SHOW"
	local act = self.lastAutoAction
	local allHealthy = (act ~= nil and act.allHealthy == true)

	if mode == "HIDE" and allHealthy and not self.isHovered then
		LBB.Compat.RunOutOfCombat("strip_healthy_vis", function()
			if self.frame then
				self.frame:Hide()
			end
		end)
		return
	end

	LBB.Compat.RunOutOfCombat("strip_healthy_vis", function()
		if self.frame then
			self.frame:Show()
		end
	end)

	if mode == "FADE" and allHealthy and not self.isHovered then
		if self.frame.SetAlpha then
			self.frame:SetAlpha(0.35)
		end
	else
		if self.frame.SetAlpha then
			self.frame:SetAlpha(1.0)
		end
	end
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

	-- Filter yielded Paladin duties AND duties with 0 eligible units in the current roster
	-- (so a solo Paladin's saved 9-class setup stays saved in the Matrix without showing empty 0/0 tiles while solo!)
	local filtered = {}
	local evalsByIdx = {}
	local ppYield = LBB.Comms and LBB.Comms:IsPallyPowerLoaded()
	for _, duty in ipairs(duties) do
		local isPaladinDuty = (duty.kind == "CLASS_BUFF" or duty.kind == "PALADIN_AURA" or duty.kind == "RIGHTEOUS_FURY" or duty.kind == "PALADIN_SEAL")
		if not (ppYield and isPaladinDuty) then
			local eval = LBB.Scanner:EvaluateDuty(duty, LBB.Assignments.roster)
			local isSelfDuty = (duty.kind == "PALADIN_AURA" or duty.kind == "RIGHTEOUS_FURY" or duty.kind == "PALADIN_SEAL" or duty.kind == "SHAMAN_TOTEM")
			if isSelfDuty or eval.totalEligible > 0 then
				table_insert(filtered, duty)
				evalsByIdx[#filtered] = eval
			end
		end
	end

	local vertical = LBB.DB and LBB.DB.stripOrientation == "VERTICAL"
	local scale = (LBB.DB and LBB.DB.stripScale) or 1.0
	if not inCombat and self.frame.SetScale then
		self.frame:SetScale(scale)
	end

	-- Update dedicated Smart Auto-Buff tile & keybinding target
	local autoAction = LBB.Scanner:GetBestAutoBuffAction(filtered, LBB.Assignments.roster)
	self.lastAutoAction = autoAction
	local showAuto = (LBB.DB == nil or LBB.DB.showAutoBuffTile ~= false) and (#filtered > 0)
	local slotOffset = 0

	if self.autoTile then
		if showAuto then
			slotOffset = 1
			if autoAction.icon then
				self.autoTile._icon:SetTexture(autoAction.icon)
			end
			self.autoTile._icon:SetDesaturated(autoAction.allHealthy)
			if autoAction.allOutOfRange then
				local needTotal = (autoAction.totalMissing or 0) + (autoAction.totalExpiring or 0)
				self.autoTile._badge:SetText(tostring(needTotal))
				self.autoTile._badge:SetTextColor(Theme.Colors.warn[1], Theme.Colors.warn[2], Theme.Colors.warn[3], 1)
				self.autoTile._statusBar:SetColorTexture(Theme.Colors.warn[1], Theme.Colors.warn[2], Theme.Colors.warn[3], 1)
				Theme.SetBorderColor(self.autoTile, Theme.Colors.border)
				self.autoTile._timer:SetText("OOR")
			elseif autoAction.totalMissing > 0 then
				self.autoTile._badge:SetText(tostring(autoAction.totalMissing))
				self.autoTile._badge:SetTextColor(Theme.Colors.danger[1], Theme.Colors.danger[2], Theme.Colors.danger[3], 1)
				self.autoTile._statusBar:SetColorTexture(Theme.Colors.danger[1], Theme.Colors.danger[2], Theme.Colors.danger[3], 1)
				Theme.SetBorderColor(self.autoTile, Theme.Colors.danger)
				self.autoTile._timer:SetText("BUFF")
			elseif autoAction.totalExpiring > 0 then
				self.autoTile._badge:SetText(tostring(autoAction.totalExpiring))
				self.autoTile._badge:SetTextColor(Theme.Colors.warn[1], Theme.Colors.warn[2], Theme.Colors.warn[3], 1)
				self.autoTile._statusBar:SetColorTexture(Theme.Colors.warn[1], Theme.Colors.warn[2], Theme.Colors.warn[3], 1)
				Theme.SetBorderColor(self.autoTile, Theme.Colors.warn)
				self.autoTile._timer:SetText("SOON")
			else
				self.autoTile._badge:SetText("OK")
				self.autoTile._badge:SetTextColor(Theme.Colors.good[1], Theme.Colors.good[2], Theme.Colors.good[3], 1)
				self.autoTile._statusBar:SetColorTexture(Theme.Colors.good[1], Theme.Colors.good[2], Theme.Colors.good[3], 1)
				Theme.SetBorderColor(self.autoTile, Theme.Colors.accent)
				self.autoTile._timer:SetText("AUTO")
			end
			Compat.SetSecureAttribute(self.autoTile, "type1", "spell")
			Compat.SetSecureAttribute(self.autoTile, "unit1", autoAction.unit or "player")
			Compat.SetSecureAttribute(self.autoTile, "spell1", autoAction.singleSpell or "")
			Compat.SetSecureAttribute(self.autoTile, "type2", "spell")
			Compat.SetSecureAttribute(self.autoTile, "unit2", autoAction.groupUnit or autoAction.unit or "player")
			Compat.SetSecureAttribute(self.autoTile, "spell2", autoAction.groupSpell or "")
			Compat.SetSecureAttribute(self.autoTile, "combat_units", autoAction.combatUnits or autoAction.unit or "player")
			Compat.SetSecureAttribute(self.autoTile, "combat_idx", 0)

			Compat.RunOutOfCombat("strip_auto_layout", function()
				self.autoTile:ClearAllPoints()
				if vertical then
					self.autoTile:SetPoint("TOP", self.frame, "TOP", 0, -(PAD + HEADER_W + 4))
				else
					self.autoTile:SetPoint("LEFT", self.frame, "LEFT", PAD + HEADER_W + PAD, 0)
				end
				self.autoTile:Show()
			end)
		else
			Compat.RunOutOfCombat("strip_auto_layout", function()
				self.autoTile:Hide()
			end)
		end
	end

	self.lastEvals = {}
	local count = #filtered

	for i, duty in ipairs(filtered) do
		local tile = self.tiles[i]
		if not tile then
			tile = createTile(self.frame, i)
			self.tiles[i] = tile
		end
		local eval = evalsByIdx[i]
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
			if eval.allOutOfRange then
				statusColor = Theme.Colors.warn
				tile._badge:SetText(tostring(eval.needCount))
				tile._badge:SetTextColor(Theme.Colors.warn[1], Theme.Colors.warn[2], Theme.Colors.warn[3], 1)
				tile._timer:SetText("OOR")
			elseif eval.missingCount > 0 then
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

		-- Bind native Blizzard CustomAuraContainerTemplate combat timer overlay for Righteous Fury & Seals
		if LBB.NativeAuras then
			if (duty.kind == "RIGHTEOUS_FURY" or duty.kind == "PALADIN_SEAL") and eval.nativeSpellIDs then
				if LBB.NativeAuras:BindTimer(tile, tile._timer, "player", eval.nativeSpellIDs) then
					-- Base bar sits in red behind Blizzard's green active bar so combat drops show cleanly
					tile._statusBar:SetColorTexture(Theme.Colors.danger[1], Theme.Colors.danger[2], Theme.Colors.danger[3], 1)
				end
			else
				LBB.NativeAuras:UnbindTimer(tile._timer)
			end
		end

		-- SecureActionButton attributes (ALWAYS routed through Combat Lockdown Queue!)
		-- Uses `eval.effectiveTarget` so that even when all in-range members are healthy before combat starts,
		-- `unit1` stays pre-staged to the in-range duty member whose buff will expire FIRST (or Tank) instead of resetting to "player"!
		local et = eval.effectiveTarget or eval.nextTarget or eval.combatTarget
		local targetUnit = (et and et.unit) or "player"
		local groupUnit = eval.groupAnchorUnit or targetUnit
		local singleSpell = eval.singleSpellName or ""
		local groupSpell = (eval.hasGroup and eval.groupSpellName) or singleSpell

		Compat.SetSecureAttribute(tile, "type1", "spell")
		Compat.SetSecureAttribute(tile, "spell1", singleSpell)
		Compat.SetSecureAttribute(tile, "type2", "spell")
		Compat.SetSecureAttribute(tile, "spell2", groupSpell)

		if duty.kind == "PALADIN_AURA" or duty.kind == "SHAMAN_TOTEM" or duty.kind == "RIGHTEOUS_FURY" or duty.kind == "PALADIN_SEAL" or duty.familyID == "BATTLE_SHOUT" then
			Compat.SetSecureAttribute(tile, "unit1", "player")
			Compat.SetSecureAttribute(tile, "unit2", "player")
			Compat.SetSecureAttribute(tile, "combat_units", "player")
			Compat.SetSecureAttribute(tile, "combat_idx", 0)
		else
			Compat.SetSecureAttribute(tile, "unit1", targetUnit)
			Compat.SetSecureAttribute(tile, "unit2", groupUnit)
			Compat.SetSecureAttribute(tile, "combat_units", eval.combatUnits or targetUnit)
			Compat.SetSecureAttribute(tile, "combat_idx", 0)
		end

		-- Layout updates must also wait until out of combat for secure buttons
		local slotIdx = i + slotOffset
		Compat.RunOutOfCombat("strip_layout_" .. i, function()
			tile:ClearAllPoints()
			if vertical then
				tile:SetPoint("TOP", self.frame, "TOP", 0, -(PAD + HEADER_W + 4 + (slotIdx - 1) * (TILE_H + PAD)))
			else
				tile:SetPoint("LEFT", self.frame, "LEFT", PAD + HEADER_W + PAD + (slotIdx - 1) * (TILE_W + PAD), 0)
			end
			tile:Show()
		end)
	end

	-- Hide unused tiles out of combat
	for i = count + 1, #self.tiles do
		local tile = self.tiles[i]
		if LBB.NativeAuras and tile._timer then
			LBB.NativeAuras:UnbindTimer(tile._timer)
		end
		Compat.RunOutOfCombat("strip_hide_" .. i, function()
			tile:Hide()
		end)
	end

	-- Resize container frame out of combat
	local totalSlots = count + slotOffset
	Compat.RunOutOfCombat("strip_frame_size", function()
		if totalSlots == 0 then
			self.frame._idleText:Show()
			self.frame:SetSize(HEADER_W + 42, TILE_H + PAD * 2)
		else
			self.frame._idleText:Hide()
			if vertical then
				self.frame:SetSize(TILE_W + PAD * 2, HEADER_W + PAD * 2 + totalSlots * (TILE_H + PAD) + 4)
			else
				self.frame:SetSize(HEADER_W + PAD * 2 + totalSlots * (TILE_W + PAD) + PAD, TILE_H + PAD * 2)
			end
		end
	end)

	self:ApplyHealthyVisibility()
end
