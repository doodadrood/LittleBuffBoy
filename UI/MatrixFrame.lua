local addonName, LBB = ...
LBB = LBB or _G.LittleBuffBoy or {}
_G.LittleBuffBoy = LBB

local MatrixFrame = {}
LBB.MatrixFrame = MatrixFrame

local pairs = pairs
local ipairs = ipairs
local tostring = tostring
local table_insert = table.insert
local table_sort = table.sort
local table_concat = table.concat

MatrixFrame.frame = nil
MatrixFrame.activeTab = "BUFFS" -- "BUFFS", "ROLES", "SELF", "TOTEMS", "CONSUMABLES"
MatrixFrame.cells = {}
MatrixFrame.btnPool = {}
MatrixFrame.btnUsed = 0
MatrixFrame.fsPool = {}
MatrixFrame.fsUsed = 0

local FRAME_W = 736
local FRAME_H = 472

local function collectCastersForFamily(familyID)
	local fam = LBB.Catalog.GetFamily(familyID)
	if not fam then
		return {}
	end
	local list = {}
	local seen = {}
	for _, m in ipairs(LBB.Assignments.roster) do
		if m.class == fam.class and m.name and not seen[m.name] then
			seen[m.name] = true
			table_insert(list, m.name)
		end
	end
	local pVec = LBB.Capabilities and LBB.Capabilities:GetPlayerVector()
	if pVec and pVec.class == fam.class and pVec.name and not seen[pVec.name] then
		seen[pVec.name] = true
		table_insert(list, pVec.name)
	end
	table_sort(list)
	return list
end

local function collectMembersByClass(classToken)
	local list = {}
	for _, m in ipairs(LBB.Assignments.roster) do
		if m.class == classToken then
			table_insert(list, m)
		end
	end
	table_sort(list, function(a, b)
		return (a.name or "") < (b.name or "")
	end)
	return list
end

local function cycleList(list, current, delta)
	local options = { "" }
	for _, v in ipairs(list) do
		table_insert(options, v)
	end
	local idx = 1
	for i, v in ipairs(options) do
		if v == (current or "") then
			idx = i
			break
		end
	end
	local nextIdx = ((idx - 1 + delta) % #options) + 1
	local chosen = options[nextIdx]
	return chosen ~= "" and chosen or nil
end

local function shortDisplayName(name)
	if not name or name == "" then
		return "--"
	end
	local first = name:match("^(%S+)") or name
	if #first > 8 then
		return first:sub(1, 7) .. "."
	end
	return first
end

local function saveMatrixPos(frame)
	if not frame or not LBB.CharDB then return end
	local point, _, relPoint, x, y = frame:GetPoint(1)
	if point then
		LBB.CharDB.matrixPos = { point = point, relPoint = relPoint or point, x = x or 0, y = y or 0 }
	end
end

local function restoreMatrixPos(frame)
	if not frame then return end
	frame:ClearAllPoints()
	local pos = LBB.CharDB and LBB.CharDB.matrixPos
	if pos and pos.point then
		frame:SetPoint(pos.point, _G.UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
	else
		frame:SetPoint("CENTER", _G.UIParent, "CENTER", 0, 30)
	end
end

function MatrixFrame:Init()
	if self.frame then
		return self.frame
	end
	local Theme = LBB.Theme
	local f = _G.CreateFrame("Frame", "LittleBuffBoyMatrixFrame", _G.UIParent)
	f:SetSize(FRAME_W, FRAME_H)
	restoreMatrixPos(f)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetFrameStrata("DIALOG")
	if f.SetFrameLevel then f:SetFrameLevel(10) end
	if f.SetToplevel then f:SetToplevel(true) end
	Theme.ApplyDropShadow(f)
	Theme.ApplyPanel(f, Theme.Colors.windowBg, Theme.Colors.borderLight)

	f:SetScript("OnDragStart", function(self) self:StartMoving() end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		saveMatrixPos(self)
	end)
	f:SetScript("OnHide", function()
		if Theme.HideDropdownMenu then
			Theme.HideDropdownMenu()
		end
	end)

	if _G.UISpecialFrames then
		table_insert(_G.UISpecialFrames, "LittleBuffBoyMatrixFrame")
	end

	-- Header bar
	local header = _G.CreateFrame("Frame", nil, f)
	header:SetHeight(30)
	header:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
	header:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
	Theme.ApplyPanel(header, Theme.Colors.header, Theme.Colors.border)

	local title = Theme.CreateFontString(header, 13, "LEFT", Theme.Colors.accent)
	title:SetPoint("LEFT", header, "LEFT", 10, 0)
	title:SetText("LittleBuffBoy  |cff94a3b8Assignment Matrix|r")

	local closeBtn = Theme.CreateButton(header, "X", 24, 20, function() f:Hide() end)
	closeBtn:SetPoint("RIGHT", header, "RIGHT", -6, 0)

	-- Tab strip
	local tabBar = _G.CreateFrame("Frame", nil, f)
	tabBar:SetHeight(26)
	tabBar:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 8, -6)
	tabBar:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -8, -6)

	local tabs = {
		{ id = "BUFFS",       label = "Raid & Blessings",    w = 132 },
		{ id = "ROLES",       label = "Role & Target Buffs", w = 146 },
		{ id = "SELF",        label = "My Self Buffs",       w = 114 },
		{ id = "TOTEMS",      label = "Shaman Totems",       w = 116 },
		{ id = "CONSUMABLES", label = "Consumables",         w = 104 },
	}
	f._tabBtns = {}
	local xOff = 0
	for _, t in ipairs(tabs) do
		local tabID = t.id
		local btn = Theme.CreateButton(tabBar, t.label, t.w, 22, function()
			self.activeTab = tabID
			Theme.HideDropdownMenu()
			self:Refresh()
		end)
		btn:SetPoint("LEFT", tabBar, "LEFT", xOff, 0)
		f._tabBtns[tabID] = btn
		xOff = xOff + t.w + 6
	end

	-- Content container
	local content = _G.CreateFrame("Frame", nil, f)
	content:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, -6)
	content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 38)
	Theme.ApplyPanel(content, Theme.Colors.panelSolid, Theme.Colors.border)
	f._content = content

	-- Hint text
	local hint = Theme.CreateFontString(content, 10, "LEFT", Theme.Colors.muted)
	hint:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 8, 6)
	hint:SetText("Left-Click: Select from Dropdown  |  Scroll: Cycle  |  Right-Click: Clear  |  Shift+Click: Toggle Lock")
	f._hint = hint

	-- Footer action bar
	local footer = _G.CreateFrame("Frame", nil, f)
	footer:SetHeight(30)
	footer:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 4)
	footer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 4)

	local btnAuto = Theme.CreateButton(footer, "Auto-Assign", 86, 22, function()
		if _G.IsShiftKeyDown and _G.IsShiftKeyDown() then
			LBB:ResetAssignments()
		else
			LBB:RunNegotiator(true, { forceFresh = true })
		end
	end)
	btnAuto:SetPoint("LEFT", footer, "LEFT", 0, 0)
	btnAuto._tooltipText = "Re-run deterministic auto-negotiation (preserves locked cells). Shift+Click unlocks all."

	local btnReset = Theme.CreateButton(footer, "Reset Locks", 80, 22, function()
		LBB:ResetAssignments()
	end)
	btnReset:SetPoint("LEFT", btnAuto, "RIGHT", 5, 0)
	btnReset._tooltipText = "Clear all manual overrides and re-negotiate"

	local btnPresets = Theme.CreateButton(footer, "Presets v", 74, 22, function(selfBtn)
		Theme.ShowDropdownMenu(selfBtn, MatrixFrame:BuildPresetsMenu())
	end)
	btnPresets:SetPoint("LEFT", btnReset, "RIGHT", 5, 0)
	btnPresets._tooltipText = "Save or load named buff/aura/totem presets (Solo, Dungeon, Raid, or custom)"
	f._btnPresets = btnPresets

	local btnSync = Theme.CreateButton(footer, "Sync", 52, 22, function()
		LBB:SyncGroup()
	end)
	btnSync:SetPoint("LEFT", btnPresets, "RIGHT", 5, 0)
	btnSync._tooltipText = "Broadcast capabilities and request updates from LBB1 & PLPWR peers"

	local btnNudge = Theme.CreateButton(footer, "Nudge", 56, 22, function()
		if LBB.ReminderPill then
			LBB.ReminderPill:ShowNudgeBar()
		end
	end)
	btnNudge:SetPoint("LEFT", btnSync, "RIGHT", 5, 0)
	btnNudge._tooltipText = "Open Ready Check & Smart Whisper Nudge Bar"

	local btnOpt = Theme.CreateButton(footer, "Options", 60, 22, function()
		if LBB.Options then
			LBB.Options:Toggle()
		end
	end)
	btnOpt:SetPoint("LEFT", btnNudge, "RIGHT", 5, 0)

	local ppStatus = Theme.CreateFontString(footer, 10, "RIGHT", Theme.Colors.good)
	ppStatus:SetPoint("RIGHT", footer, "RIGHT", -4, 0)
	f._ppStatus = ppStatus

	f:Hide()
	self.frame = f
	return f
end

function MatrixFrame:Toggle()
	if not self.frame then
		self:Init()
	end
	if self.frame:IsShown() then
		self.frame:Hide()
	else
		self:Refresh()
		self.frame:Show()
	end
end

function MatrixFrame:OpenTab(tabID)
	if not self.frame then
		self:Init()
	end
	if tabID then
		self.activeTab = tabID
	end
	self:Refresh()
	self.frame:Show()
end

function MatrixFrame:ClearContentWidgets()
	for i = 1, #self.btnPool do
		self.btnPool[i]:Hide()
	end
	for i = 1, #self.fsPool do
		self.fsPool[i]:Hide()
	end
	self.btnUsed = 0
	self.fsUsed = 0
	self.cells = {}
end

function MatrixFrame:AcquireLabel(parent, size, justifyH, color)
	local Theme = LBB.Theme
	self.fsUsed = self.fsUsed + 1
	local fs = self.fsPool[self.fsUsed]
	if not fs then
		fs = Theme.CreateFontString(parent, size, justifyH, color)
		self.fsPool[self.fsUsed] = fs
	else
		fs:ClearAllPoints()
		fs:SetJustifyH(justifyH or "CENTER")
		if _G.STANDARD_TEXT_FONT then
			fs:SetFont(_G.STANDARD_TEXT_FONT, size or 11, "OUTLINE")
		else
			fs:SetFont("Fonts\\FRIZQT__.TTF", size or 11, "OUTLINE")
		end
		local c = color or Theme.Colors.text
		fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
		fs:Show()
	end
	return fs
end

local function makeCell(parent, x, y, w, h, text, locked, bgColor, onClick, onWheel, tooltip)
	local Theme = LBB.Theme
	MatrixFrame.btnUsed = MatrixFrame.btnUsed + 1
	local btn = MatrixFrame.btnPool[MatrixFrame.btnUsed]
	if not btn then
		btn = _G.CreateFrame("Button", nil, parent)
		btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		btn._fs = Theme.CreateFontString(btn, 10, "CENTER", Theme.Colors.text)
		btn._fs:SetAllPoints(btn)
		btn._dot = btn:CreateTexture(nil, "OVERLAY")
		btn._dot:SetSize(5, 5)
		btn._dot:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -2, -2)
		btn._dot:SetColorTexture(Theme.Colors.locked[1], Theme.Colors.locked[2], Theme.Colors.locked[3], 1)
		MatrixFrame.btnPool[MatrixFrame.btnUsed] = btn
	end
	btn:ClearAllPoints()
	btn:SetSize(w, h)
	btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
	btn:EnableMouseWheel(onWheel ~= nil)
	Theme.ApplyPanel(btn, bgColor or Theme.Colors.tile, locked and Theme.Colors.locked or Theme.Colors.border)

	btn._fs:SetText(text or "--")
	if locked then
		btn._dot:Show()
	else
		btn._dot:Hide()
	end

	btn:SetScript("OnClick", onClick)
	btn:SetScript("OnMouseWheel", onWheel)
	if tooltip then
		btn:SetScript("OnEnter", function(self)
			if _G.GameTooltip then
				_G.GameTooltip:SetOwner(self, "ANCHOR_TOP")
				_G.GameTooltip:ClearLines()
				_G.GameTooltip:AddLine(tooltip, 0.93, 0.95, 0.98, true)
				_G.GameTooltip:Show()
			end
		end)
		btn:SetScript("OnLeave", function()
			if _G.GameTooltip then _G.GameTooltip:Hide() end
		end)
	else
		btn:SetScript("OnEnter", nil)
		btn:SetScript("OnLeave", nil)
	end
	btn:Show()
	return btn
end

-- =========================================================================
-- Dropdown Builders (Left-Click selection menus with Per-Player Overrides)
-- =========================================================================

function MatrixFrame:BuildPresetsMenu()
	local Theme = LBB.Theme
	local Assignments = LBB.Assignments
	local savedNames = Assignments:ListPresets()
	local activeName = LBB.CharDB and LBB.CharDB.activePresetName

	local items = {
		{ isTitle = true, text = "Saved Character Presets" },
	}

	if #savedNames == 0 then
		table_insert(items, { isTitle = true, text = "No presets saved yet", color = Theme.Colors.muted })
	else
		for _, pName in ipairs(savedNames) do
			local nameRef = pName
			table_insert(items, {
				text = pName,
				checked = (activeName == pName),
				rightText = "Actions >",
				rightColor = Theme.Colors.accent,
				submenu = {
					{ isTitle = true, text = "Preset: " .. pName },
					{
						text = "Load Preset",
						color = Theme.Colors.good,
						onClick = function()
							if LBB.LoadPreset then
								LBB:LoadPreset(nameRef)
							else
								Assignments:LoadPreset(nameRef, LBB.Comms:IsPallyPowerLoaded())
								LBB:RefreshUI()
							end
						end,
					},
					{
						text = "Overwrite With Current",
						color = Theme.Colors.warn,
						onClick = function()
							Assignments:SavePreset(nameRef)
							if LBB.Print then LBB:Print("Saved preset '" .. nameRef .. "'.") end
							LBB:RefreshUI()
						end,
					},
					{
						text = "Delete Preset",
						color = Theme.Colors.danger,
						onClick = function()
							Assignments:DeletePreset(nameRef)
							if LBB.Print then LBB:Print("Deleted preset '" .. nameRef .. "'.") end
							LBB:RefreshUI()
						end,
					},
				},
			})
		end
	end

	table_insert(items, { isSeparator = true })
	table_insert(items, { isTitle = true, text = "Quick Save Current Setup As" })
	for _, quickName in ipairs({ "Solo", "Dungeon", "Raid" }) do
		local qRef = quickName
		table_insert(items, {
			text = "Save as \"" .. quickName .. "\"",
			color = Theme.Colors.accent,
			onClick = function()
				Assignments:SavePreset(qRef)
				if LBB.Print then LBB:Print("Saved preset '" .. qRef .. "'.") end
				LBB:RefreshUI()
			end,
		})
	end
	table_insert(items, { isTitle = true, text = "Tip: /lbb preset save <name>", color = Theme.Colors.muted })
	return items
end

function MatrixFrame:BuildGroupBuffMenu(famID, sg, casters, applyFn)
	local fam = LBB.Catalog.GetFamily(famID)
	local cur = LBB.Assignments:GetGroupBuff(famID, sg)
	local curCaster = cur and cur.caster or nil
	local curLocked = cur and cur.locked or false

	local items = {
		{ isTitle = true, text = string.format("%s - Group %d", fam and fam.shortName or famID, sg) },
	}
	if #casters == 0 then
		table_insert(items, { isTitle = true, text = "No eligible casters in roster", color = LBB.Theme.Colors.muted })
	else
		for _, cName in ipairs(casters) do
			local vec = LBB.Capabilities:GetPeerVector(cName)
			local b = vec and vec.buffs and vec.buffs[famID]
			local tag = b and b.talentRank and b.talentRank > 0 and ("T" .. tostring(b.talentRank)) or ""
			local casterRef = cName
			table_insert(items, {
				text = LBB.Theme.ColorizeName(cName, fam.class),
				rightText = tag,
				checked = (curCaster == cName),
				onClick = function()
					applyFn(casterRef, true)
				end,
			})
		end
	end

	-- 1-Click Apply to ALL Groups (G1-G8)
	local allGroupSub = {
		{ isTitle = true, text = (fam and fam.shortName or famID) .. " -> ALL Groups (G1-G8)" },
	}
	for _, cName in ipairs(casters) do
		local casterRef = cName
		table_insert(allGroupSub, {
			text = LBB.Theme.ColorizeName(cName, fam.class),
			onClick = function()
				LBB.Assignments:SetAllGroupBuffs(famID, casterRef, true)
				LBB.Comms:BroadcastGroupAll(famID, casterRef, true)
				LBB:RefreshUI()
			end,
		})
	end
	table_insert(allGroupSub, { isSeparator = true })
	table_insert(allGroupSub, {
		text = "Clear ALL Groups",
		color = LBB.Theme.Colors.danger,
		onClick = function()
			LBB.Assignments:SetAllGroupBuffs(famID, nil, true)
			LBB.Comms:BroadcastGroupAll(famID, nil, true)
			LBB:RefreshUI()
		end,
	})

	table_insert(items, { isSeparator = true })
	table_insert(items, {
		text = "Apply to ALL Groups (G1-G8)",
		rightText = "All >",
		rightColor = LBB.Theme.Colors.accent,
		submenu = allGroupSub,
	})
	table_insert(items, {
		text = "Clear (Unassigned)",
		color = LBB.Theme.Colors.danger,
		checked = (curCaster == nil),
		onClick = function()
			applyFn(nil, true)
		end,
	})
	table_insert(items, {
		text = curLocked and "Unlock Cell" or "Lock Cell",
		color = LBB.Theme.Colors.locked,
		onClick = function()
			applyFn(curCaster, not curLocked)
		end,
	})
	return items
end

function MatrixFrame:BuildPaladinClassMenu(pallyName, classToken, applyClassFn)
	local Catalog = LBB.Catalog
	local Theme = LBB.Theme
	local Assignments = LBB.Assignments
	local cur = Assignments:GetClassBuff(pallyName, classToken)
	local curFam = cur and cur.familyID or nil
	local curLocked = cur and cur.locked or false
	local pVec = LBB.Capabilities:GetPeerVector(pallyName)
	local blessingList = { "BOW", "BOM", "BOK", "BOSALV", "BOL", "BOSANC" }

	local clsInfo = Catalog.CLASS_INFO[classToken]
	local items = {
		{ isTitle = true, text = shortDisplayName(pallyName) .. " -> " .. (clsInfo and clsInfo.name or classToken) },
	}

	for _, famID in ipairs(blessingList) do
		local fam = Catalog.GetFamily(famID)
		local known = pVec and pVec.buffs and pVec.buffs[famID] and pVec.buffs[famID].known
		local tal = known and pVec.buffs[famID].talentRank or 0
		local tag = tal > 0 and ("T" .. tostring(tal)) or (pVec and not known and "n/a" or "")
		local fRef = famID
		table_insert(items, {
			text = fam and fam.name or famID,
			rightText = tag,
			color = (pVec and not known) and Theme.Colors.muted or Theme.Colors.text,
			checked = (curFam == famID),
			onClick = function()
				applyClassFn(fRef, true)
			end,
		})
	end

	-- 1-Click Apply to ALL Classes (uses native PLPWR MASSIGN)
	local allClassSub = {
		{ isTitle = true, text = shortDisplayName(pallyName) .. " -> ALL 9 Classes" },
	}
	for _, famID in ipairs(blessingList) do
		local fam = Catalog.GetFamily(famID)
		local fRef = famID
		table_insert(allClassSub, {
			text = fam and fam.name or famID,
			onClick = function()
				Assignments:SetAllClassBuffs(pallyName, fRef, true)
				LBB.Comms:BroadcastClassAll(pallyName, fRef, true)
				LBB:RefreshUI()
			end,
		})
	end
	table_insert(allClassSub, { isSeparator = true })
	table_insert(allClassSub, {
		text = "Clear ALL Classes",
		color = Theme.Colors.danger,
		onClick = function()
			Assignments:SetAllClassBuffs(pallyName, nil, true)
			LBB.Comms:BroadcastClassAll(pallyName, nil, true)
			LBB:RefreshUI()
		end,
	})

	table_insert(items, { isSeparator = true })
	table_insert(items, {
		text = "Apply to ALL Classes",
		rightText = "MASSIGN >",
		rightColor = Theme.Colors.accent,
		submenu = allClassSub,
	})
	table_insert(items, {
		text = "Clear Class Blessing",
		color = Theme.Colors.danger,
		checked = (curFam == nil),
		onClick = function()
			applyClassFn(nil, true)
		end,
	})
	table_insert(items, {
		text = curLocked and "Unlock Cell" or "Lock Cell",
		color = Theme.Colors.locked,
		onClick = function()
			applyClassFn(curFam, not curLocked)
		end,
	})

	-- Inline Per-Player Overrides submenu section
	local classMembers = collectMembersByClass(classToken)
	if #classMembers > 0 then
		table_insert(items, { isSeparator = true })
		table_insert(items, { isTitle = true, text = "Per-Player Overrides" })

		local anyOverride = false
		for _, member in ipairs(classMembers) do
			local targetName = member.name
			local ov = Assignments:GetPaladinNormalOverride(pallyName, targetName)
			local ovFam = ov and ov.familyID and Catalog.GetFamily(ov.familyID) or nil
			if ovFam then
				anyOverride = true
			end

			local sub = {
				{ isTitle = true, text = targetName .. " Override" },
				{
					text = "Use Class Default",
					color = Theme.Colors.muted,
					checked = (ovFam == nil),
					onClick = function()
						Assignments:SetPaladinNormalOverride(pallyName, targetName, classToken, nil, false)
						Assignments:SaveToCharDB()
						LBB.Comms:BroadcastLock("NORMAL", targetName, nil, pallyName, false, classToken)
						LBB:RefreshUI()
					end,
				},
				{ isSeparator = true },
			}
			for _, famID in ipairs(blessingList) do
				local fam = Catalog.GetFamily(famID)
				local fRef = famID
				table_insert(sub, {
					text = fam and fam.name or famID,
					checked = (ov and ov.familyID == famID),
					onClick = function()
						Assignments:SetPaladinNormalOverride(pallyName, targetName, classToken, fRef, true)
						Assignments:SaveToCharDB()
						LBB.Comms:BroadcastLock("NORMAL", targetName, fRef, pallyName, true, classToken)
						LBB:RefreshUI()
					end,
				})
			end

			table_insert(items, {
				text = Theme.ColorizeName(targetName, classToken),
				rightText = ovFam and (ovFam.shortName .. " >") or "Default >",
				rightColor = ovFam and Theme.Colors.accent or Theme.Colors.muted,
				submenu = sub,
			})
		end

		if anyOverride then
			table_insert(items, {
				text = "Clear All " .. (clsInfo and clsInfo.name or classToken) .. " Overrides",
				color = Theme.Colors.warn,
				onClick = function()
					local activeOvs = Assignments:GetPaladinNormalOverridesForClass(pallyName, classToken)
					for _, entry in ipairs(activeOvs) do
						Assignments:SetPaladinNormalOverride(pallyName, entry.target, classToken, nil, false)
						LBB.Comms:BroadcastLock("NORMAL", entry.target, nil, pallyName, false, classToken)
					end
					LBB:RefreshUI()
				end,
			})
		end
	end

	return items
end

function MatrixFrame:BuildPaladinAuraMenu(pallyName, applyAuraFn)
	local Catalog = LBB.Catalog
	local Theme = LBB.Theme
	local cur = LBB.Assignments:GetPaladinAura(pallyName)
	local curAuraID = cur and cur.auraID or 0
	local curLocked = cur and cur.locked or false
	local pVec = LBB.Capabilities:GetPeerVector(pallyName)

	local items = {
		{ isTitle = true, text = shortDisplayName(pallyName) .. " - Aura" },
	}
	for auraID, def in ipairs(Catalog.PALADIN_AURAS) do
		local known = pVec and pVec.auras and pVec.auras[auraID] ~= nil
		local aidRef = auraID
		table_insert(items, {
			text = def.name,
			rightText = (pVec and not known) and "n/a" or "",
			color = (pVec and not known) and Theme.Colors.muted or Theme.Colors.text,
			checked = (curAuraID == auraID),
			onClick = function()
				applyAuraFn(aidRef, true)
			end,
		})
	end
	table_insert(items, { isSeparator = true })
	table_insert(items, {
		text = "Clear Aura",
		color = Theme.Colors.danger,
		checked = (curAuraID == 0),
		onClick = function()
			applyAuraFn(0, true)
		end,
	})
	table_insert(items, {
		text = curLocked and "Unlock Aura" or "Lock Aura",
		color = Theme.Colors.locked,
		onClick = function()
			applyAuraFn(curAuraID, not curLocked)
		end,
	})
	return items
end

function MatrixFrame:BuildPaladinSealMenu()
	local vec = LBB.Capabilities:GetPlayerVector()
	local selfCfg = LBB.Assignments:GetPaladinSelfConfig()
	local Theme = LBB.Theme

	local items = {
		{ isTitle = true, text = "Select Active Seal (Self)" },
		{
			text = "Off (Do Not Track Seal)",
			color = Theme.Colors.danger,
			checked = (not selfCfg.trackSeal),
			onClick = function()
				LBB.Assignments:SetSelectedSeal(nil)
				LBB:RefreshUI()
			end,
		},
		{ isSeparator = true },
	}

	local seals = (vec and vec.sealsList) or {}
	if #seals == 0 then
		table_insert(items, { isTitle = true, text = "No Seals learned yet", color = Theme.Colors.muted })
	else
		for _, sealEntry in ipairs(seals) do
			local sRef = sealEntry
			table_insert(items, {
				text = sealEntry.name,
				rightText = sealEntry.shortName or "",
				checked = (selfCfg.trackSeal and selfCfg.sealID == sealEntry.id),
				onClick = function()
					LBB.Assignments:SetSelectedSeal(sRef)
					LBB.Assignments:SaveToCharDB()
					LBB:RefreshUI()
				end,
			})
		end
	end
	return items
end

function MatrixFrame:BuildPersonalSlotMenu(slotDef)
	local vec = LBB.Capabilities and LBB.Capabilities:GetPlayerVector()
	local slotBucket = vec and vec.personal and vec.personal[slotDef.slotID] or nil
	local slotCfg = LBB.Assignments:GetPersonalSlot(slotDef.slotID)
	local Theme = LBB.Theme

	local items = {
		{ isTitle = true, text = "Select " .. (slotDef.label or slotDef.slotID) .. " (Self)" },
		{
			text = "Off (Do Not Track)",
			color = Theme.Colors.danger,
			checked = not (slotCfg and slotCfg.enabled),
			onClick = function()
				LBB.Assignments:SetPersonalChoice(slotDef.slotID, nil)
				LBB.Assignments:SaveToCharDB()
				LBB:RefreshUI()
			end,
		},
		{ isSeparator = true },
	}

	local opts = (slotBucket and slotBucket.list) or {}
	if #opts == 0 then
		table_insert(items, { isTitle = true, text = "No spells learned yet", color = Theme.Colors.muted })
	else
		for _, optEntry in ipairs(opts) do
			local oRef = optEntry
			table_insert(items, {
				text = optEntry.name,
				rightText = optEntry.shortName or "",
				checked = (slotCfg and slotCfg.enabled and (slotCfg.optionID == optEntry.id or slotCfg.optionName == optEntry.name)),
				onClick = function()
					LBB.Assignments:SetPersonalChoice(slotDef.slotID, oRef)
					LBB.Assignments:SaveToCharDB()
					LBB:RefreshUI()
				end,
			})
		end
	end
	return items
end

function MatrixFrame:BuildRoleBuffMenu(famID, roleKey, casters, applyFn)
	local Catalog = LBB.Catalog
	local Theme = LBB.Theme
	local fam = Catalog.GetFamily(famID)
	local rInfo = Catalog.ROLE_INFO[roleKey]
	local cur = LBB.Assignments:GetRoleBuff(famID, roleKey)
	local curCaster = cur and cur.caster or nil
	local curLocked = cur and cur.locked or false
	local pVec = LBB.Capabilities and LBB.Capabilities:GetPlayerVector()

	local items = {
		{ isTitle = true, text = string.format("%s -> %s", fam and fam.name or famID, rInfo and rInfo.name or roleKey) },
	}
	if #casters == 0 then
		table_insert(items, { isTitle = true, text = "No " .. (fam and fam.class or "") .. " in roster", color = Theme.Colors.muted })
	else
		for _, cName in ipairs(casters) do
			local vec = LBB.Capabilities:GetPeerVector(cName)
			local b = vec and vec.buffs and vec.buffs[famID]
			local tags = {}
			if pVec and pVec.name == cName then
				table_insert(tags, "You")
			end
			if b and b.talentRank and b.talentRank > 0 then
				table_insert(tags, "T" .. tostring(b.talentRank))
			end
			local casterRef = cName
			table_insert(items, {
				text = Theme.ColorizeName(cName, fam.class),
				rightText = table_concat(tags, " "),
				rightColor = Theme.Colors.accent,
				checked = (curCaster == cName),
				onClick = function()
					applyFn(casterRef, true)
				end,
			})
		end
	end

	table_insert(items, { isSeparator = true })
	table_insert(items, {
		text = "Clear Role Assignment",
		color = Theme.Colors.danger,
		checked = (curCaster == nil),
		onClick = function()
			applyFn(nil, true)
		end,
	})
	table_insert(items, {
		text = curLocked and "Unlock Cell" or "Lock Cell",
		color = Theme.Colors.locked,
		onClick = function()
			applyFn(curCaster, not curLocked)
		end,
	})
	return items
end

function MatrixFrame:BuildTargetPlayersMenu(famID, casters)
	local Catalog = LBB.Catalog
	local Theme = LBB.Theme
	local Assignments = LBB.Assignments
	local fam = Catalog.GetFamily(famID)

	local items = {
		{ isTitle = true, text = (fam and fam.name or famID) .. " - Specific Players" },
	}

	local sortedMembers = {}
	for _, m in ipairs(Assignments.roster) do
		table_insert(sortedMembers, m)
	end
	table_sort(sortedMembers, function(a, b)
		local aTank = Catalog.MatchesRoleFilter("TANK", a)
		local bTank = Catalog.MatchesRoleFilter("TANK", b)
		if aTank ~= bTank then
			return aTank and not bTank
		end
		local aHeal = Catalog.MatchesRoleFilter("HEALER", a)
		local bHeal = Catalog.MatchesRoleFilter("HEALER", b)
		if aHeal ~= bHeal then
			return aHeal and not bHeal
		end
		return (a.name or "") < (b.name or "")
	end)

	if #sortedMembers == 0 then
		table_insert(items, { isTitle = true, text = "No players in roster", color = Theme.Colors.muted })
		return items
	end

	local anyAssigned = false
	local maxShow = math.min(#sortedMembers, 18)
	for i = 1, maxShow do
		local m = sortedMembers[i]
		local targetName = m.name
		local cur = Assignments:GetTargetBuff(famID, targetName)
		local curCaster = cur and cur.caster or nil
		if curCaster then
			anyAssigned = true
		end

		local roleBadge = ""
		if Catalog.MatchesRoleFilter("TANK", m) then
			roleBadge = "[Tank] "
		elseif Catalog.MatchesRoleFilter("HEALER", m) then
			roleBadge = "[Heal] "
		end

		local sub = {
			{ isTitle = true, text = (fam and fam.shortName or famID) .. " -> " .. targetName },
			{
				text = "Unassigned (Use Role Rule)",
				color = Theme.Colors.muted,
				checked = (curCaster == nil),
				onClick = function()
					Assignments:SetTargetBuff(famID, targetName, nil, false)
					Assignments:SaveToCharDB()
					LBB.Comms:BroadcastLock("TARGET", targetName, famID, nil, false)
					LBB:RefreshUI()
				end,
			},
			{ isSeparator = true },
		}

		if #casters == 0 then
			table_insert(sub, { isTitle = true, text = "No " .. (fam and fam.class or "") .. " available", color = Theme.Colors.muted })
		else
			for _, cName in ipairs(casters) do
				local cRef = cName
				table_insert(sub, {
					text = Theme.ColorizeName(cName, fam.class),
					checked = (curCaster == cName),
					onClick = function()
						Assignments:SetTargetBuff(famID, targetName, cRef, true)
						Assignments:SaveToCharDB()
						LBB.Comms:BroadcastLock("TARGET", targetName, famID, cRef, true)
						LBB:RefreshUI()
					end,
				})
			end
		end

		table_insert(items, {
			text = roleBadge .. Theme.ColorizeName(targetName, m.class),
			rightText = curCaster and (shortDisplayName(curCaster) .. " >") or "-- >",
			rightColor = curCaster and Theme.Colors.accent or Theme.Colors.muted,
			submenu = sub,
		})
	end

	if anyAssigned then
		table_insert(items, { isSeparator = true })
		table_insert(items, {
			text = "Clear All Specific Players",
			color = Theme.Colors.danger,
			onClick = function()
				local tMap = Assignments.targetBuffs[famID] or {}
				local names = {}
				for tName in pairs(tMap) do
					table_insert(names, tName)
				end
				for _, tName in ipairs(names) do
					Assignments:SetTargetBuff(famID, tName, nil, false)
					LBB.Comms:BroadcastLock("TARGET", tName, famID, nil, false)
				end
				Assignments:SaveToCharDB()
				LBB:RefreshUI()
			end,
		})
	end

	return items
end

function MatrixFrame:BuildTotemMenu(shamanName, subgroup, element, applyTotemFn)
	local Catalog = LBB.Catalog
	local Theme = LBB.Theme
	local cur = LBB.Assignments:GetShamanTotems(subgroup, shamanName) or { locked = {} }
	local curTotem = cur[element]
	local curLocked = cur.locked and cur.locked[element] or false

	local items = {
		{ isTitle = true, text = string.format("%s - %s Totem", shortDisplayName(shamanName), element) },
	}
	for _, tDef in ipairs(Catalog.SHAMAN_TOTEMS[element] or {}) do
		local tRef = tDef.id
		table_insert(items, {
			text = tDef.name,
			rightText = tDef.shortName,
			checked = (curTotem == tDef.id),
			onClick = function()
				applyTotemFn(tRef, true)
			end,
		})
	end
	table_insert(items, { isSeparator = true })
	table_insert(items, {
		text = "Clear Totem",
		color = Theme.Colors.danger,
		checked = (curTotem == nil),
		onClick = function()
			applyTotemFn(nil, true)
		end,
	})
	table_insert(items, {
		text = curLocked and "Unlock Slot" or "Lock Slot",
		color = Theme.Colors.locked,
		onClick = function()
			applyTotemFn(curTotem, not curLocked)
		end,
	})
	return items
end

-- =========================================================================
-- Tab Renderers
-- =========================================================================

function MatrixFrame:RenderBuffsTab(content)
	local Theme = LBB.Theme
	local Assignments = LBB.Assignments
	local Catalog = LBB.Catalog

	local y = 8
	-- Section A: Raid / Group Buffs (Rows = Families, Columns = Groups 1..8)
	local secLabel = self:AcquireLabel(content, 11, "LEFT", Theme.Colors.accent)
	secLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 10, -y)
	secLabel:SetText("Group Buffs (Subgroups G1 - G8)")
	y = y + 18

	local labelW = 86
	local colW = 73
	local rowH = 22

	-- Column Headers G1..G8
	for sg = 1, 8 do
		local hdr = self:AcquireLabel(content, 10, "CENTER", Theme.Colors.muted)
		hdr:SetSize(colW, 16)
		hdr:SetPoint("TOPLEFT", content, "TOPLEFT", 10 + labelW + (sg - 1) * (colW + 2), -y)
		hdr:SetText("G" .. sg)
	end
	y = y + 16

	local groupFamilies = { "FORTITUDE", "SPIRIT", "SHADOW_PROT", "MOTW", "INTELLECT", "BATTLE_SHOUT", "BLOOD_PACT" }
	for _, famID in ipairs(groupFamilies) do
		local fam = Catalog.GetFamily(famID)
		local casters = collectCastersForFamily(famID)
		local r, g, b = Theme.GetClassColor(fam.class)

		local rowLbl = self:AcquireLabel(content, 10, "LEFT", { r, g, b, 1 })
		rowLbl:SetSize(labelW, rowH)
		rowLbl:SetPoint("TOPLEFT", content, "TOPLEFT", 10, -y)
		rowLbl:SetText(fam.shortName)

		for sg = 1, 8 do
			local entry = Assignments:GetGroupBuff(famID, sg)
			local caster = entry and entry.caster or nil
			local locked = entry and entry.locked or false
			local cellText = caster and Theme.ColorizeName(shortDisplayName(caster), fam.class) or "|cff64748b--|r"

			local famRef, sgRef = famID, sg
			local function applyChange(newCaster, newLocked)
				Assignments:SetGroupBuff(famRef, sgRef, newCaster, newLocked)
				Assignments:SaveToCharDB()
				LBB.Comms:BroadcastLock("GROUP", tostring(sgRef), famRef, newCaster, newLocked)
				LBB:RefreshUI()
			end

			local cell = makeCell(
				content,
				10 + labelW + (sg - 1) * (colW + 2),
				y,
				colW,
				rowH,
				cellText,
				locked,
				nil,
				function(btnSelf, mouseBtn)
					local cur = Assignments:GetGroupBuff(famRef, sgRef)
					local curCaster = cur and cur.caster or nil
					local curLocked = cur and cur.locked or false
					if _G.IsShiftKeyDown and _G.IsShiftKeyDown() then
						applyChange(curCaster, not curLocked)
					elseif mouseBtn == "RightButton" then
						applyChange(nil, true)
					else
						Theme.ShowDropdownMenu(btnSelf, MatrixFrame:BuildGroupBuffMenu(famRef, sgRef, casters, applyChange))
					end
				end,
				function(_, delta)
					local cur = Assignments:GetGroupBuff(famRef, sgRef)
					local nextCaster = cycleList(casters, cur and cur.caster or nil, delta > 0 and -1 or 1)
					applyChange(nextCaster, true)
				end,
				fam.name .. " - Group " .. sg .. (caster and ("\nAssigned: " .. caster) or "\nUnassigned") .. "\nLeft-Click: Dropdown | Scroll: Cycle"
			)
			table_insert(self.cells, cell)
		end
		y = y + rowH + 3
	end

	-- Section B: Paladin Blessings & Aura Column (Rows = Paladins, Columns = 9 Classes + Aura)
	y = y + 8
	local ppYield = LBB.Comms:IsPallyPowerLoaded()
	local palHdr = self:AcquireLabel(content, 11, "LEFT", ppYield and Theme.Colors.warn or Theme.Colors.accent)
	palHdr:SetPoint("TOPLEFT", content, "TOPLEFT", 10, -y)
	palHdr:SetText(ppYield
		and "Paladin Blessings & Auras  |cfffbbf24(Yielded to PallyPower - Read Only)|r"
		or "Paladin Blessings & Auras (Synced with PLPWR  |  Left-Click for Dropdown & Per-Player Overrides)")
	y = y + 18

	local paladins = {}
	for _, m in ipairs(Assignments.roster) do
		if m.class == "PALADIN" then
			table_insert(paladins, m.name)
		end
	end
	table_sort(paladins)

	if #paladins == 0 then
		local noneLbl = self:AcquireLabel(content, 10, "LEFT", Theme.Colors.muted)
		noneLbl:SetPoint("TOPLEFT", content, "TOPLEFT", 12, -y)
		noneLbl:SetText("No Paladins in current group/raid.")
		y = y + 20
	else
		local clsW = 56
		local auraW = 68
		for idx, cls in ipairs(Catalog.CLASS_ORDER) do
			local cInfo = Catalog.CLASS_INFO[cls]
			local ch = self:AcquireLabel(content, 10, "CENTER", { cInfo.color[1], cInfo.color[2], cInfo.color[3], 1 })
			ch:SetSize(clsW, 14)
			ch:SetPoint("TOPLEFT", content, "TOPLEFT", 10 + labelW + (idx - 1) * (clsW + 2), -y)
			ch:SetText(cInfo.short)
		end
		local auraX = 10 + labelW + 9 * (clsW + 2) + 4
		local ah = self:AcquireLabel(content, 10, "CENTER", Theme.Colors.accent)
		ah:SetSize(auraW, 14)
		ah:SetPoint("TOPLEFT", content, "TOPLEFT", auraX, -y)
		ah:SetText("AURA")
		y = y + 16

		local blessingCycle = { "BOW", "BOM", "BOK", "BOSALV", "BOL", "BOSANC" }
		local auraCycle = { 1, 2, 3, 4, 5, 6, 7 }
		for _, pName in ipairs(paladins) do
			local pLbl = self:AcquireLabel(content, 10, "LEFT", { 0.96, 0.55, 0.73, 1 })
			pLbl:SetSize(labelW, rowH)
			pLbl:SetPoint("TOPLEFT", content, "TOPLEFT", 10, -y)
			pLbl:SetText(shortDisplayName(pName))

			for idx, cls in ipairs(Catalog.CLASS_ORDER) do
				local entry = Assignments:GetClassBuff(pName, cls)
				local famID = entry and entry.familyID or nil
				local locked = entry and entry.locked or false
				local fam = famID and Catalog.GetFamily(famID)
				local overrides = Assignments:GetPaladinNormalOverridesForClass(pName, cls)
				local hasOvs = #overrides > 0
				local baseTxt = fam and fam.shortName or "|cff64748b--|r"
				local txt = hasOvs and (baseTxt .. "|cff38bdf8*|r") or baseTxt

				local tipLines = {
					pName .. " -> " .. Catalog.CLASS_INFO[cls].name .. (fam and (": " .. fam.name) or ": None"),
				}
				if hasOvs then
					table_insert(tipLines, "Per-Player Overrides:")
					for _, ov in ipairs(overrides) do
						local ovFam = Catalog.GetFamily(ov.familyID)
						table_insert(tipLines, "  " .. ov.target .. " -> " .. (ovFam and ovFam.name or ov.familyID))
					end
				end
				if not ppYield then
					table_insert(tipLines, "Left-Click: Dropdown & Overrides | Scroll: Cycle")
				end

				local pRef, clsRef = pName, cls
				local function applyPaladin(newFam, newLock)
					if ppYield then return end
					Assignments:SetClassBuff(pRef, clsRef, newFam, newLock)
					Assignments:SaveToCharDB()
					LBB.Comms:BroadcastLock("CLASS", clsRef, newFam, pRef, newLock)
					LBB:RefreshUI()
				end

				local cell = makeCell(
					content,
					10 + labelW + (idx - 1) * (clsW + 2),
					y,
					clsW,
					rowH,
					txt,
					locked,
					nil,
					function(btnSelf, mouseBtn)
						if ppYield then return end
						local cur = Assignments:GetClassBuff(pRef, clsRef)
						if _G.IsShiftKeyDown and _G.IsShiftKeyDown() then
							applyPaladin(cur and cur.familyID or nil, not (cur and cur.locked))
						elseif mouseBtn == "RightButton" then
							applyPaladin(nil, true)
						else
							Theme.ShowDropdownMenu(btnSelf, MatrixFrame:BuildPaladinClassMenu(pRef, clsRef, applyPaladin))
						end
					end,
					function(_, delta)
						if ppYield then return end
						local cur = Assignments:GetClassBuff(pRef, clsRef)
						applyPaladin(cycleList(blessingCycle, cur and cur.familyID or nil, delta > 0 and -1 or 1), true)
					end,
					table_concat(tipLines, "\n")
				)
				table_insert(self.cells, cell)
			end

			-- Paladin Aura Cell
			local aEntry = Assignments:GetPaladinAura(pName)
			local auraID = aEntry and aEntry.auraID or 0
			local auraLocked = aEntry and aEntry.locked or false
			local auraDef = auraID > 0 and Catalog.PALADIN_AURAS[auraID] or nil
			local auraTxt = auraDef and ("|cff38bdf8" .. auraDef.shortName .. "|r") or "|cff64748b--|r"

			local pRef = pName
			local function applyAura(newAuraID, newLock)
				if ppYield then return end
				Assignments:SetPaladinAura(pRef, newAuraID, newLock)
				Assignments:SaveToCharDB()
				LBB.Comms:BroadcastLock("AURA", pRef, tostring(newAuraID or 0), pRef, newLock)
				LBB:RefreshUI()
			end

			local auraCell = makeCell(
				content,
				auraX,
				y,
				auraW,
				rowH,
				auraTxt,
				auraLocked,
				nil,
				function(btnSelf, mouseBtn)
					if ppYield then return end
					local cur = Assignments:GetPaladinAura(pRef)
					if _G.IsShiftKeyDown and _G.IsShiftKeyDown() then
						applyAura(cur and cur.auraID or 0, not (cur and cur.locked))
					elseif mouseBtn == "RightButton" then
						applyAura(0, true)
					else
						Theme.ShowDropdownMenu(btnSelf, MatrixFrame:BuildPaladinAuraMenu(pRef, applyAura))
					end
				end,
				function(_, delta)
					if ppYield then return end
					local cur = Assignments:GetPaladinAura(pRef)
					local nextAura = cycleList(auraCycle, cur and cur.auraID and cur.auraID > 0 and cur.auraID or nil, delta > 0 and -1 or 1)
					applyAura(nextAura or 0, true)
				end,
				pName .. " Aura: " .. (auraDef and auraDef.name or "None") .. (ppYield and "" or "\nLeft-Click: Select Aura | Scroll: Cycle")
			)
			table_insert(self.cells, auraCell)
			y = y + rowH + 3
		end
	end

	-- Section C: All-Class Personal Self-Buff Quick Bar (when vertical space allows; otherwise 1-click tab shortcut)
	if y <= 316 then
		self:RenderSelfBuffsInline(content, y + 6)
	else
		local moreBtn = makeCell(
			content,
			580,
			4,
			130,
			18,
			"My Self Buffs ->",
			false,
			Theme.Colors.header,
			function()
				self:OpenTab("SELF")
			end,
			nil,
			"Open the My Self Buffs tab to configure your class personal buffs"
		)
		table_insert(self.cells, moreBtn)
	end
end

function MatrixFrame:RenderSelfBuffsInline(content, y)
	local Theme = LBB.Theme
	local Assignments = LBB.Assignments
	local Catalog = LBB.Catalog
	local ppYield = LBB.Comms:IsPallyPowerLoaded()
	local pVec = LBB.Capabilities and LBB.Capabilities:GetPlayerVector()
	if not pVec then
		return
	end

	if pVec.class == "PALADIN" then
		local selfCfg = Assignments:GetPaladinSelfConfig()
		local selfLbl = self:AcquireLabel(content, 10, "LEFT", Theme.Colors.accent)
		selfLbl:SetPoint("TOPLEFT", content, "TOPLEFT", 10, -y - 4)
		selfLbl:SetText("My Self Buffs:")

		if ppYield then
			local yLbl = self:AcquireLabel(content, 10, "LEFT", Theme.Colors.warn)
			yLbl:SetPoint("TOPLEFT", content, "TOPLEFT", 100, -y - 4)
			yLbl:SetText("Righteous Fury & Seals yielded to standalone PallyPower.")
		else
			local rfKnown = pVec.righteousFury and pVec.righteousFury.known
			local rfTxt = rfKnown
				and ("Righteous Fury: " .. (selfCfg.trackRF and "|cff34d399ON|r" or "|cff94a3b8OFF|r"))
				or "|cff64748bRighteous Fury (n/a)|r"
			local rfBtn = makeCell(
				content,
				100,
				y,
				150,
				22,
				rfTxt,
				selfCfg.trackRF,
				Theme.Colors.header,
				function(_, mouseBtn)
					if not rfKnown then return end
					if mouseBtn == "RightButton" then
						Assignments:SetRighteousFuryEnabled(false)
					else
						Assignments:SetRighteousFuryEnabled(not selfCfg.trackRF)
					end
					Assignments:SaveToCharDB()
					LBB:RefreshUI()
				end,
				nil,
				"Opt-in Righteous Fury tracking & one-click Buff Strip tile (Prot Paladins)"
			)
			table_insert(self.cells, rfBtn)

			local sealLabel = (selfCfg.trackSeal and selfCfg.sealName) and ("Seal: " .. selfCfg.sealName) or "Seal: Off"
			local sealBtn = makeCell(
				content,
				258,
				y,
				200,
				22,
				sealLabel .. "  |cff38bdf8v|r",
				selfCfg.trackSeal,
				Theme.Colors.header,
				function(btnSelf, mouseBtn)
					if mouseBtn == "RightButton" then
						Assignments:SetSelectedSeal(nil)
						Assignments:SaveToCharDB()
						LBB:RefreshUI()
					else
						Theme.ShowDropdownMenu(btnSelf, MatrixFrame:BuildPaladinSealMenu())
					end
				end,
				nil,
				"Pick your active Paladin Seal (supports Forever Seal of Fury & native combat timer)"
			)
			table_insert(self.cells, sealBtn)
		end
		return
	end

	local slots = Catalog.PERSONAL_SLOTS and Catalog.PERSONAL_SLOTS[pVec.class] or nil
	if not slots or #slots == 0 then
		return
	end

	local selfLbl = self:AcquireLabel(content, 10, "LEFT", Theme.Colors.accent)
	selfLbl:SetPoint("TOPLEFT", content, "TOPLEFT", 10, -y - 4)
	selfLbl:SetText("My Self Buffs:")

	local availW = 608
	local gap = 6
	local btnW = math.min(205, math.floor((availW - (#slots - 1) * gap) / #slots))
	local x = 100

	for _, slotDef in ipairs(slots) do
		local sDef = slotDef
		local slotBucket = pVec.personal and pVec.personal[sDef.slotID] or nil
		local learnedList = (slotBucket and slotBucket.list) or {}
		local slotCfg = Assignments:GetPersonalSlot(sDef.slotID)
		local enabled = slotCfg and slotCfg.enabled and true or false

		if sDef.mode == "TOGGLE" then
			local opt = learnedList[1]
			local txt = opt
				and (sDef.label .. ": " .. (enabled and "|cff34d399ON|r" or "|cff94a3b8OFF|r"))
				or ("|cff64748b" .. sDef.label .. " (n/a)|r")
			local btn = makeCell(
				content,
				x,
				y,
				btnW,
				22,
				txt,
				enabled,
				Theme.Colors.header,
				function(_, mouseBtn)
					if not opt then return end
					local nextState = (mouseBtn == "RightButton") and false or (not enabled)
					Assignments:SetPersonalToggle(sDef.slotID, nextState, opt)
					Assignments:SaveToCharDB()
					LBB:RefreshUI()
				end,
				nil,
				sDef.label .. (opt and (": Left-Click to toggle Buff Strip tracking") or " (Not yet learned in spellbook)")
			)
			table_insert(self.cells, btn)
		else
			local chosenShort = "Off"
			if enabled and slotCfg.optionName then
				local catOpt = (slotCfg.optionID and Catalog.PERSONAL_OPT_BY_ID[slotCfg.optionID])
					or Catalog.PERSONAL_NAME_TO_OPT[slotCfg.optionName]
				chosenShort = (catOpt and catOpt.shortName) or shortDisplayName(slotCfg.optionName)
			end
			local txt = string.format("%s: %s |cff38bdf8v|r", sDef.label, enabled and ("|cff34d399" .. chosenShort .. "|r") or "|cff94a3b8Off|r")
			local btn = makeCell(
				content,
				x,
				y,
				btnW,
				22,
				txt,
				enabled,
				Theme.Colors.header,
				function(btnSelf, mouseBtn)
					if mouseBtn == "RightButton" then
						Assignments:SetPersonalChoice(sDef.slotID, nil)
						Assignments:SaveToCharDB()
						LBB:RefreshUI()
					else
						Theme.ShowDropdownMenu(btnSelf, MatrixFrame:BuildPersonalSlotMenu(sDef))
					end
				end,
				function(_, delta)
					if #learnedList == 0 then return end
					local curID = enabled and slotCfg and slotCfg.optionID or nil
					local ids = {}
					for _, o in ipairs(learnedList) do
						table_insert(ids, o.id)
					end
					local nextID = cycleList(ids, curID, delta > 0 and -1 or 1)
					local nextOpt = nextID and slotBucket and slotBucket.byID[nextID] or nil
					Assignments:SetPersonalChoice(sDef.slotID, nextOpt)
					Assignments:SaveToCharDB()
					LBB:RefreshUI()
				end,
				sDef.label .. ": Left-Click for Dropdown | Scroll: Cycle | Right-Click: Off"
			)
			table_insert(self.cells, btn)
		end
		x = x + btnW + gap
	end
end

function MatrixFrame:RenderRolesTab(content)
	local Theme = LBB.Theme
	local Assignments = LBB.Assignments
	local Catalog = LBB.Catalog

	local y = 10
	local hdr = self:AcquireLabel(content, 11, "LEFT", Theme.Colors.accent)
	hdr:SetPoint("TOPLEFT", content, "TOPLEFT", 10, -y)
	hdr:SetText("Role & Per-Player Target Buffs (Thorns, Fear Ward, Soulstone, Magic Wards & Utility)")
	y = y + 16

	local sub = self:AcquireLabel(content, 10, "LEFT", Theme.Colors.muted)
	sub:SetPoint("TOPLEFT", content, "TOPLEFT", 10, -y)
	sub:SetText("Assigning a buff to a Role (e.g. Thorns -> Tanks) automatically tracks anyone marked Tank or Raid Main Tank.")
	y = y + 20

	local labelW = 136
	local roleW = 102
	local playerColW = 132
	local rowH = 26

	-- Count active roster members matching each role for header clarity
	local roleCounts = {}
	for _, rKey in ipairs(Catalog.ROLE_ORDER) do
		local cnt = 0
		for _, m in ipairs(Assignments.roster) do
			if Catalog.MatchesRoleFilter(rKey, m) then
				cnt = cnt + 1
			end
		end
		roleCounts[rKey] = cnt
	end

	local buffHdr = self:AcquireLabel(content, 10, "LEFT", Theme.Colors.muted)
	buffHdr:SetSize(labelW, 16)
	buffHdr:SetPoint("TOPLEFT", content, "TOPLEFT", 10, -y)
	buffHdr:SetText("Target Buff")

	for idx, rKey in ipairs(Catalog.ROLE_ORDER) do
		local rInfo = Catalog.ROLE_INFO[rKey]
		local rHdr = self:AcquireLabel(content, 10, "CENTER", { rInfo.color[1], rInfo.color[2], rInfo.color[3], 1 })
		rHdr:SetSize(roleW, 16)
		rHdr:SetPoint("TOPLEFT", content, "TOPLEFT", 10 + labelW + (idx - 1) * (roleW + 4), -y)
		rHdr:SetText(string.format("%s (%d)", rInfo.name, roleCounts[rKey] or 0))
	end

	local pColX = 10 + labelW + #Catalog.ROLE_ORDER * (roleW + 4) + 2
	local pHdr = self:AcquireLabel(content, 10, "CENTER", Theme.Colors.accent)
	pHdr:SetSize(playerColW, 16)
	pHdr:SetPoint("TOPLEFT", content, "TOPLEFT", pColX, -y)
	pHdr:SetText("Specific Players")
	y = y + 18

	for _, famID in ipairs(Catalog.TARGET_FAMILY_ORDER) do
		local fam = Catalog.GetFamily(famID)
		if fam then
			local casters = collectCastersForFamily(famID)
			local r, g, b = Theme.GetClassColor(fam.class)

			local rowLbl = self:AcquireLabel(content, 10, "LEFT", { r, g, b, 1 })
			rowLbl:SetSize(labelW, rowH)
			rowLbl:SetPoint("TOPLEFT", content, "TOPLEFT", 10, -y)
			rowLbl:SetText(fam.name)

			for idx, rKey in ipairs(Catalog.ROLE_ORDER) do
				local rInfo = Catalog.ROLE_INFO[rKey]
				local entry = Assignments:GetRoleBuff(famID, rKey)
				local caster = entry and entry.caster or nil
				local locked = entry and entry.locked or false
				local cellText = caster and Theme.ColorizeName(shortDisplayName(caster), fam.class) or "|cff64748b--|r"

				local famRef, roleRef = famID, rKey
				local function applyRole(newCaster, newLocked)
					Assignments:SetRoleBuff(famRef, roleRef, newCaster, newLocked)
					Assignments:SaveToCharDB()
					LBB.Comms:BroadcastLock("ROLE", roleRef, famRef, newCaster, newLocked)
					LBB:RefreshUI()
				end

				local cell = makeCell(
					content,
					10 + labelW + (idx - 1) * (roleW + 4),
					y,
					roleW,
					rowH,
					cellText,
					locked,
					nil,
					function(btnSelf, mouseBtn)
						local cur = Assignments:GetRoleBuff(famRef, roleRef)
						local curCaster = cur and cur.caster or nil
						local curLocked = cur and cur.locked or false
						if _G.IsShiftKeyDown and _G.IsShiftKeyDown() then
							applyRole(curCaster, not curLocked)
						elseif mouseBtn == "RightButton" then
							applyRole(nil, true)
						else
							Theme.ShowDropdownMenu(btnSelf, MatrixFrame:BuildRoleBuffMenu(famRef, roleRef, casters, applyRole))
						end
					end,
					function(_, delta)
						local cur = Assignments:GetRoleBuff(famRef, roleRef)
						local nextCaster = cycleList(casters, cur and cur.caster or nil, delta > 0 and -1 or 1)
						applyRole(nextCaster, true)
					end,
					string.format(
						"%s -> %s%s\nLeft-Click: Select Caster | Scroll: Cycle | Right-Click: Clear",
						fam.name,
						rInfo.name,
						caster and ("\nAssigned: " .. caster) or "\nUnassigned"
					)
				)
				table_insert(self.cells, cell)
			end

			-- Specific Players button for per-player assignments
			local tMap = Assignments.targetBuffs[famID] or {}
			local assignedList = {}
			for tName, e in pairs(tMap) do
				if e and e.caster then
					table_insert(assignedList, string.format("%s (%s)", shortDisplayName(tName), shortDisplayName(e.caster)))
				end
			end
			table_sort(assignedList)
			local pCount = #assignedList
			local pTxt = (pCount > 0)
				and string.format("|cff38bdf8%d Assigned|r v", pCount)
				or "|cff94a3b8+ Player|r v"

			local famRef = famID
			local pTip = fam.name .. " - Specific Players"
			if pCount > 0 then
				pTip = pTip .. ":\n  " .. table_concat(assignedList, "\n  ")
			else
				pTip = pTip .. "\nLeft-Click to assign specific individual players"
			end
			local pBtn = makeCell(
				content,
				pColX,
				y,
				playerColW,
				rowH,
				pTxt,
				pCount > 0,
				Theme.Colors.header,
				function(btnSelf, mouseBtn)
					if mouseBtn == "RightButton" then
						local names = {}
						for tName in pairs(Assignments.targetBuffs[famRef] or {}) do
							table_insert(names, tName)
						end
						for _, tName in ipairs(names) do
							Assignments:SetTargetBuff(famRef, tName, nil, false)
							LBB.Comms:BroadcastLock("TARGET", tName, famRef, nil, false)
						end
						Assignments:SaveToCharDB()
						LBB:RefreshUI()
					else
						Theme.ShowDropdownMenu(btnSelf, MatrixFrame:BuildTargetPlayersMenu(famRef, casters))
					end
				end,
				nil,
				pTip
			)
			table_insert(self.cells, pBtn)

			y = y + rowH + 4
		end
	end
end

function MatrixFrame:RenderSelfTab(content)
	local Theme = LBB.Theme
	local Assignments = LBB.Assignments
	local Catalog = LBB.Catalog
	local Compat = LBB.Compat
	local pVec = LBB.Capabilities and LBB.Capabilities:GetPlayerVector() or (LBB.Capabilities and LBB.Capabilities:ScanPlayer())
	local cls = (pVec and pVec.class) or "PRIEST"
	local clsInfo = Catalog.CLASS_INFO[cls]
	local clsName = (clsInfo and clsInfo.name) or cls

	local y = 10
	local hdr = self:AcquireLabel(content, 11, "LEFT", Theme.Colors.accent)
	hdr:SetPoint("TOPLEFT", content, "TOPLEFT", 10, -y)
	hdr:SetText(string.format("My Self Buffs & Class Trackers (%s)", clsName))
	y = y + 16

	local sub = self:AcquireLabel(content, 10, "LEFT", Theme.Colors.muted)
	sub:SetPoint("TOPLEFT", content, "TOPLEFT", 10, -y)
	sub:SetText("Enabled personal buffs appear on your Buff Strip, bind to native combat timers, and cast automatically via Smart Auto-Buff.")
	y = y + 22

	local scan = LBB.Scanner and LBB.Scanner:ScanUnit("player", Assignments.rosterByUnit["player"]) or nil

	-- Column headers
	local colSlotW = 240
	local colStateW = 190
	local colCtrlW = 240
	local rowH = 28

	local h1 = self:AcquireLabel(content, 10, "LEFT", Theme.Colors.muted)
	h1:SetSize(colSlotW, 16)
	h1:SetPoint("TOPLEFT", content, "TOPLEFT", 12, -y)
	h1:SetText("Personal Buff Slot")

	local h2 = self:AcquireLabel(content, 10, "CENTER", Theme.Colors.muted)
	h2:SetSize(colStateW, 16)
	h2:SetPoint("TOPLEFT", content, "TOPLEFT", 12 + colSlotW + 8, -y)
	h2:SetText("Current Status")

	local h3 = self:AcquireLabel(content, 10, "CENTER", Theme.Colors.muted)
	h3:SetSize(colCtrlW, 16)
	h3:SetPoint("TOPLEFT", content, "TOPLEFT", 12 + colSlotW + 8 + colStateW + 8, -y)
	h3:SetText("Tracking & Selection")
	y = y + 18

	if cls == "PALADIN" then
		local ppYield = LBB.Comms:IsPallyPowerLoaded()
		local selfCfg = Assignments:GetPaladinSelfConfig()
		if ppYield then
			local yLbl = self:AcquireLabel(content, 11, "LEFT", Theme.Colors.warn)
			yLbl:SetPoint("TOPLEFT", content, "TOPLEFT", 12, -y)
			yLbl:SetText("Paladin Righteous Fury & Seals are currently yielded to standalone PallyPower.")
			return
		end

		-- Row 1: Righteous Fury
		local rfKnown = pVec and pVec.righteousFury and pVec.righteousFury.known
		local rfLbl = self:AcquireLabel(content, 11, "LEFT", { 0.96, 0.55, 0.73, 1 })
		rfLbl:SetSize(colSlotW, rowH)
		rfLbl:SetPoint("TOPLEFT", content, "TOPLEFT", 12, -y)
		rfLbl:SetText("Righteous Fury (Tank Threat)")

		local rfStatusTxt = "|cff64748bOFF|r"
		if selfCfg.trackRF then
			if scan and scan.righteousFury then
				rfStatusTxt = "|cff34d399ACTIVE|r"
			else
				rfStatusTxt = "|cffef4444MISSING|r"
			end
		end
		local rfState = self:AcquireLabel(content, 10, "CENTER", Theme.Colors.text)
		rfState:SetSize(colStateW, rowH)
		rfState:SetPoint("TOPLEFT", content, "TOPLEFT", 12 + colSlotW + 8, -y)
		rfState:SetText(rfStatusTxt)

		local rfBtnTxt = rfKnown
			and ("Track Righteous Fury: " .. (selfCfg.trackRF and "|cff34d399ON|r" or "|cff94a3b8OFF|r"))
			or "|cff64748bNot Learned|r"
		local rfBtn = makeCell(
			content,
			12 + colSlotW + 8 + colStateW + 8,
			y,
			colCtrlW,
			rowH,
			rfBtnTxt,
			selfCfg.trackRF,
			Theme.Colors.header,
			function(_, mouseBtn)
				if not rfKnown then return end
				local nextVal = (mouseBtn == "RightButton") and false or (not selfCfg.trackRF)
				Assignments:SetRighteousFuryEnabled(nextVal)
				Assignments:SaveToCharDB()
				LBB:RefreshUI()
			end,
			nil,
			"Toggle Righteous Fury tracking (/lbb rf)"
		)
		table_insert(self.cells, rfBtn)
		y = y + rowH + 6

		-- Row 2: Active Seal
		local sLbl = self:AcquireLabel(content, 11, "LEFT", { 0.96, 0.55, 0.73, 1 })
		sLbl:SetSize(colSlotW, rowH)
		sLbl:SetPoint("TOPLEFT", content, "TOPLEFT", 12, -y)
		sLbl:SetText("Active Paladin Seal")

		local sealStatusTxt = "|cff64748bOFF|r"
		if selfCfg.trackSeal and selfCfg.sealName then
			local sHit = scan and scan.seals and scan.seals[selfCfg.sealName]
			if sHit then
				sealStatusTxt = "|cff34d399ACTIVE|r (" .. Theme.FormatTimer(sHit.remaining) .. ")"
			else
				sealStatusTxt = "|cffef4444MISSING|r"
			end
		end
		local sState = self:AcquireLabel(content, 10, "CENTER", Theme.Colors.text)
		sState:SetSize(colStateW, rowH)
		sState:SetPoint("TOPLEFT", content, "TOPLEFT", 12 + colSlotW + 8, -y)
		sState:SetText(sealStatusTxt)

		local sealBtnTxt = (selfCfg.trackSeal and selfCfg.sealName)
			and ("|cff34d399" .. selfCfg.sealName .. "|r  |cff38bdf8v|r")
			or "|cff94a3b8Off (Select Seal)|r  |cff38bdf8v|r"
		local sealBtn = makeCell(
			content,
			12 + colSlotW + 8 + colStateW + 8,
			y,
			colCtrlW,
			rowH,
			sealBtnTxt,
			selfCfg.trackSeal,
			Theme.Colors.header,
			function(btnSelf, mouseBtn)
				if mouseBtn == "RightButton" then
					Assignments:SetSelectedSeal(nil)
					Assignments:SaveToCharDB()
					LBB:RefreshUI()
				else
					Theme.ShowDropdownMenu(btnSelf, MatrixFrame:BuildPaladinSealMenu())
				end
			end,
			nil,
			"Choose your active Paladin Seal (/lbb seal)"
		)
		table_insert(self.cells, sealBtn)
		return
	end

	local slots = Catalog.PERSONAL_SLOTS and Catalog.PERSONAL_SLOTS[cls] or nil
	if not slots or #slots == 0 then
		local rLbl = self:AcquireLabel(content, 11, "LEFT", Theme.Colors.muted)
		rLbl:SetPoint("TOPLEFT", content, "TOPLEFT", 12, -y)
		rLbl:SetText("Weapon Poisons & Sharpening Stones are tracked automatically in the Consumables tab.")
		return
	end

	local r, g, b = Theme.GetClassColor(cls)
	for _, slotDef in ipairs(slots) do
		local sDef = slotDef
		local slotBucket = pVec and pVec.personal and pVec.personal[sDef.slotID] or nil
		local learnedList = (slotBucket and slotBucket.list) or {}
		local slotCfg = Assignments:GetPersonalSlot(sDef.slotID)
		local enabled = slotCfg and slotCfg.enabled and true or false

		local rowLbl = self:AcquireLabel(content, 11, "LEFT", { r, g, b, 1 })
		rowLbl:SetSize(colSlotW, rowH)
		rowLbl:SetPoint("TOPLEFT", content, "TOPLEFT", 12, -y)
		rowLbl:SetText(sDef.label)

		-- Compute live status text
		local statusTxt = "|cff64748bOFF|r"
		if enabled then
			local optName = slotCfg.optionName or (learnedList[1] and learnedList[1].name)
			if sDef.requiresPet and not Compat.UnitExists("pet") then
				statusTxt = "|cfffbbf24NO ACTIVE PET|r"
			elseif sDef.checkType == "WEAPON_OH" and not Compat.HasOffHandWeapon() then
				statusTxt = "|cfffbbf24NO OFF-HAND WEAPON|r"
			elseif sDef.checkType == "WEAPON_MH" then
				local mh = scan and scan.weaponImbues and scan.weaponImbues.mh
				statusTxt = mh and ("|cff34d399ACTIVE|r (" .. Theme.FormatTimer(mh.remaining) .. ")") or "|cffef4444MISSING|r"
			elseif sDef.checkType == "WEAPON_OH" then
				local oh = scan and scan.weaponImbues and scan.weaponImbues.oh
				statusTxt = oh and ("|cff34d399ACTIVE|r (" .. Theme.FormatTimer(oh.remaining) .. ")") or "|cffef4444MISSING|r"
			elseif optName then
				local pHit = scan and scan.personalByName and scan.personalByName[optName]
				if pHit then
					if sDef.isPermanentToggle or not pHit.remaining or pHit.remaining >= 99999 then
						statusTxt = "|cff34d399ACTIVE|r"
					else
						statusTxt = "|cff34d399ACTIVE|r (" .. Theme.FormatTimer(pHit.remaining) .. ")"
					end
				else
					statusTxt = "|cffef4444MISSING|r"
				end
			end
		elseif #learnedList == 0 then
			statusTxt = "|cff64748bNOT LEARNED|r"
		end

		local stLbl = self:AcquireLabel(content, 10, "CENTER", Theme.Colors.text)
		stLbl:SetSize(colStateW, rowH)
		stLbl:SetPoint("TOPLEFT", content, "TOPLEFT", 12 + colSlotW + 8, -y)
		stLbl:SetText(statusTxt)

		if sDef.mode == "TOGGLE" then
			local opt = learnedList[1]
			local ctrlTxt = opt
				and ((opt.name or sDef.label) .. ": " .. (enabled and "|cff34d399ON|r" or "|cff94a3b8OFF|r"))
				or "|cff64748bNot Learned Yet|r"
			local btn = makeCell(
				content,
				12 + colSlotW + 8 + colStateW + 8,
				y,
				colCtrlW,
				rowH,
				ctrlTxt,
				enabled,
				Theme.Colors.header,
				function(_, mouseBtn)
					if not opt then return end
					local nextState = (mouseBtn == "RightButton") and false or (not enabled)
					Assignments:SetPersonalToggle(sDef.slotID, nextState, opt)
					Assignments:SaveToCharDB()
					LBB:RefreshUI()
				end,
				nil,
				sDef.label .. ": Left-Click to toggle ON/OFF | Right-Click: Turn OFF"
			)
			table_insert(self.cells, btn)
		else
			local curLabel = (enabled and slotCfg.optionName)
				and ("|cff34d399" .. slotCfg.optionName .. "|r  |cff38bdf8v|r")
				or "|cff94a3b8Off (Select Buff)|r  |cff38bdf8v|r"
			local btn = makeCell(
				content,
				12 + colSlotW + 8 + colStateW + 8,
				y,
				colCtrlW,
				rowH,
				curLabel,
				enabled,
				Theme.Colors.header,
				function(btnSelf, mouseBtn)
					if mouseBtn == "RightButton" then
						Assignments:SetPersonalChoice(sDef.slotID, nil)
						Assignments:SaveToCharDB()
						LBB:RefreshUI()
					else
						Theme.ShowDropdownMenu(btnSelf, MatrixFrame:BuildPersonalSlotMenu(sDef))
					end
				end,
				function(_, delta)
					if #learnedList == 0 then return end
					local curID = enabled and slotCfg and slotCfg.optionID or nil
					local ids = {}
					for _, o in ipairs(learnedList) do
						table_insert(ids, o.id)
					end
					local nextID = cycleList(ids, curID, delta > 0 and -1 or 1)
					local nextOpt = nextID and slotBucket and slotBucket.byID[nextID] or nil
					Assignments:SetPersonalChoice(sDef.slotID, nextOpt)
					Assignments:SaveToCharDB()
					LBB:RefreshUI()
				end,
				sDef.label .. ": Left-Click for Dropdown | Scroll: Cycle | Right-Click: Turn Off"
			)
			table_insert(self.cells, btn)
		end

		y = y + rowH + 6
	end
end

function MatrixFrame:RenderTotemsTab(content)
	local Theme = LBB.Theme
	local Assignments = LBB.Assignments
	local Catalog = LBB.Catalog

	local y = 10
	local hdr = self:AcquireLabel(content, 11, "LEFT", Theme.Colors.accent)
	hdr:SetPoint("TOPLEFT", content, "TOPLEFT", 10, -y)
	hdr:SetText("Shaman 4-Element Totem Assignments (Per Party)")
	y = y + 20

	local shamans = {}
	for _, m in ipairs(Assignments.roster) do
		if m.class == "SHAMAN" then
			table_insert(shamans, m)
		end
	end
	if #shamans == 0 then
		local empty = self:AcquireLabel(content, 11, "LEFT", Theme.Colors.muted)
		empty:SetPoint("TOPLEFT", content, "TOPLEFT", 12, -y)
		empty:SetText("No Shamans in current group/raid.")
		return
	end

	local nameW = 140
	local colW = 132
	local rowH = 24
	for i, el in ipairs(Catalog.TOTEM_ELEMENTS) do
		local elHdr = self:AcquireLabel(content, 10, "CENTER", Theme.Colors.muted)
		elHdr:SetSize(colW, 16)
		elHdr:SetPoint("TOPLEFT", content, "TOPLEFT", 10 + nameW + (i - 1) * (colW + 4), -y)
		elHdr:SetText(el)
	end
	y = y + 18

	for _, s in ipairs(shamans) do
		local sg = s.subgroup or 1
		local lbl = self:AcquireLabel(content, 10, "LEFT", Theme.Colors.text)
		lbl:SetSize(nameW, rowH)
		lbl:SetPoint("TOPLEFT", content, "TOPLEFT", 10, -y)
		lbl:SetText(string.format("G%d  %s", sg, Theme.ColorizeName(shortDisplayName(s.name), "SHAMAN")))

		local curEntry = Assignments:GetShamanTotems(sg, s.name) or { locked = {} }
		for i, el in ipairs(Catalog.TOTEM_ELEMENTS) do
			local tid = curEntry[el]
			local locked = curEntry.locked and curEntry.locked[el] or false
			local def = tid and Catalog.TOTEM_BY_ID[tid]
			local txt = def and def.shortName or "|cff64748b--|r"

			local totemIDs = {}
			for _, tDef in ipairs(Catalog.SHAMAN_TOTEMS[el]) do
				table_insert(totemIDs, tDef.id)
			end

			local sName, sgRef, elRef = s.name, sg, el
			local function applyTotem(newID, newLock)
				Assignments:SetShamanTotem(sgRef, sName, elRef, newID, newLock)
				Assignments:SaveToCharDB()
				local cur = Assignments:GetShamanTotems(sgRef, sName) or { locked = {} }
				local mask = ""
				for _, element in ipairs(Catalog.TOTEM_ELEMENTS) do
					mask = mask .. ((cur.locked and cur.locked[element]) and "1" or "0")
				end
				LBB.Comms:BroadcastTotem(sgRef, sName, cur.EARTH, cur.FIRE, cur.WATER, cur.AIR, mask)
				LBB:RefreshUI()
			end

			local cell = makeCell(
				content,
				10 + nameW + (i - 1) * (colW + 4),
				y,
				colW,
				rowH,
				txt,
				locked,
				nil,
				function(btnSelf, mouseBtn)
					local cur = Assignments:GetShamanTotems(sgRef, sName) or { locked = {} }
					if _G.IsShiftKeyDown and _G.IsShiftKeyDown() then
						applyTotem(cur[elRef], not (cur.locked and cur.locked[elRef]))
					elseif mouseBtn == "RightButton" then
						applyTotem(nil, true)
					else
						Theme.ShowDropdownMenu(btnSelf, MatrixFrame:BuildTotemMenu(sName, sgRef, elRef, applyTotem))
					end
				end,
				function(_, delta)
					local cur = Assignments:GetShamanTotems(sgRef, sName) or { locked = {} }
					applyTotem(cycleList(totemIDs, cur[elRef], delta > 0 and -1 or 1), true)
				end,
				sName .. " (" .. elRef .. "): " .. (def and def.name or "None") .. "\nLeft-Click: Dropdown | Scroll: Cycle"
			)
			table_insert(self.cells, cell)
		end
		y = y + rowH + 4
	end
end

function MatrixFrame:RenderConsumablesTab(content)
	local Theme = LBB.Theme
	local Assignments = LBB.Assignments
	local report = LBB.Scanner:BuildReadinessReport(Assignments.roster, Assignments)

	local y = 10
	local hdr = self:AcquireLabel(content, 11, "LEFT", Theme.Colors.accent)
	hdr:SetPoint("TOPLEFT", content, "TOPLEFT", 10, -y)
	hdr:SetText("Effect-Based Consumables Status (Well Fed / Flask & Elixir / Weapon Oil)")
	y = y + 20

	local cols = { "Player", "Well Fed", "Flask / Elixir", "Weapon Oil" }
	local widths = { 210, 140, 150, 140 }
	local x = 10
	for i, title in ipairs(cols) do
		local c = self:AcquireLabel(content, 10, i == 1 and "LEFT" or "CENTER", Theme.Colors.muted)
		c:SetSize(widths[i], 16)
		c:SetPoint("TOPLEFT", content, "TOPLEFT", x, -y)
		c:SetText(title)
		x = x + widths[i] + 6
	end
	y = y + 18

	local maxRows = 13
	for idx = 1, math.min(#Assignments.roster, maxRows) do
		local m = Assignments.roster[idx]
		local st = report.consumables[m.name] or {}

		local nLbl = self:AcquireLabel(content, 10, "LEFT", Theme.Colors.text)
		nLbl:SetSize(widths[1], 18)
		nLbl:SetPoint("TOPLEFT", content, "TOPLEFT", 10, -y)
		nLbl:SetText(string.format("G%d %s", m.subgroup or 1, Theme.ColorizeName(m.name, m.class)))

		local vals = {
			st.WELL_FED and "|cff34d399ACTIVE|r" or "|cffef4444MISSING|r",
			st.FLASK_ELIXIR and "|cff34d399ACTIVE|r" or "|cffef4444MISSING|r",
			(m.unit == "player") and (st.WEAPON_OIL and "|cff34d399ACTIVE|r" or "|cffef4444MISSING|r") or "|cff64748b(self)|r",
		}
		local cx = 10 + widths[1] + 6
		for ci, txt in ipairs(vals) do
			local vLbl = self:AcquireLabel(content, 10, "CENTER", Theme.Colors.text)
			vLbl:SetSize(widths[ci + 1], 18)
			vLbl:SetPoint("TOPLEFT", content, "TOPLEFT", cx, -y)
			vLbl:SetText(txt)
			cx = cx + widths[ci + 1] + 6
		end
		y = y + 20
	end
end

function MatrixFrame:Refresh()
	if not self.frame then
		return
	end
	local Theme = LBB.Theme
	for tabID, btn in pairs(self.frame._tabBtns) do
		if tabID == self.activeTab then
			btn._baseBg = Theme.Colors.tileHover
			btn._lbbBg:SetColorTexture(Theme.Colors.tileHover[1], Theme.Colors.tileHover[2], Theme.Colors.tileHover[3], 1)
			Theme.SetBorderColor(btn, Theme.Colors.accent)
		else
			btn._baseBg = Theme.Colors.header
			btn._lbbBg:SetColorTexture(Theme.Colors.header[1], Theme.Colors.header[2], Theme.Colors.header[3], 1)
			Theme.SetBorderColor(btn, Theme.Colors.border)
		end
	end

	local ppYield = LBB.Comms:IsPallyPowerLoaded()
	if ppYield then
		self.frame._ppStatus:SetText("PLPWR: Yielded to PallyPower")
		self.frame._ppStatus:SetTextColor(Theme.Colors.warn[1], Theme.Colors.warn[2], Theme.Colors.warn[3], 1)
	else
		self.frame._ppStatus:SetText("PLPWR Bridge: Active")
		self.frame._ppStatus:SetTextColor(Theme.Colors.good[1], Theme.Colors.good[2], Theme.Colors.good[3], 1)
	end

	if self.frame._hint then
		if self.activeTab == "SELF" then
			self.frame._hint:SetText("Left-Click: Toggle or Select Buff  |  Scroll: Cycle Options  |  Right-Click: Turn Off  |  Saved per character & in Presets")
		elseif self.activeTab == "ROLES" then
			self.frame._hint:SetText("Left-Click: Assign Caster to Role/Player  |  Scroll: Cycle  |  Right-Click: Clear  |  Shift+Click: Toggle Lock")
		else
			self.frame._hint:SetText("Left-Click: Select from Dropdown  |  Scroll: Cycle  |  Right-Click: Clear  |  Shift+Click: Toggle Lock")
		end
	end

	self:ClearContentWidgets()
	local content = self.frame._content
	if self.activeTab == "BUFFS" then
		self:RenderBuffsTab(content)
	elseif self.activeTab == "ROLES" then
		self:RenderRolesTab(content)
	elseif self.activeTab == "SELF" then
		self:RenderSelfTab(content)
	elseif self.activeTab == "TOTEMS" then
		self:RenderTotemsTab(content)
	else
		self:RenderConsumablesTab(content)
	end
end
