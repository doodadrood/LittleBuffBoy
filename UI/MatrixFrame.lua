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

MatrixFrame.frame = nil
MatrixFrame.activeTab = "BUFFS" -- "BUFFS", "TOTEMS", "CONSUMABLES"
MatrixFrame.cells = {}
MatrixFrame.btnPool = {}
MatrixFrame.btnUsed = 0
MatrixFrame.fsPool = {}
MatrixFrame.fsUsed = 0

local FRAME_W = 680
local FRAME_H = 440

local function collectCastersForFamily(familyID)
	local fam = LBB.Catalog.GetFamily(familyID)
	if not fam then
		return {}
	end
	local list = {}
	local seen = {}
	for _, m in ipairs(LBB.Assignments.roster) do
		if m.class == fam.class and not seen[m.name] then
			seen[m.name] = true
			table_insert(list, m.name)
		end
	end
	table_sort(list)
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

function MatrixFrame:Init()
	if self.frame then
		return self.frame
	end
	local Theme = LBB.Theme
	local f = _G.CreateFrame("Frame", "LittleBuffBoyMatrixFrame", _G.UIParent)
	f:SetSize(FRAME_W, FRAME_H)
	f:SetPoint("CENTER", _G.UIParent, "CENTER", 0, 40)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetFrameStrata("DIALOG")
	Theme.ApplyPanel(f, Theme.Colors.bg, Theme.Colors.borderLight)

	f:SetScript("OnDragStart", function(self) self:StartMoving() end)
	f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

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
		{ id = "BUFFS",       label = "Raid Buffs & Blessings", w = 165 },
		{ id = "TOTEMS",      label = "Shaman Totems",          w = 120 },
		{ id = "CONSUMABLES", label = "Consumables",            w = 110 },
	}
	f._tabBtns = {}
	local xOff = 0
	for _, t in ipairs(tabs) do
		local tabID = t.id
		local btn = Theme.CreateButton(tabBar, t.label, t.w, 22, function()
			self.activeTab = tabID
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
	Theme.ApplyPanel(content, Theme.Colors.panel, Theme.Colors.border)
	f._content = content

	-- Hint text
	local hint = Theme.CreateFontString(content, 10, "LEFT", Theme.Colors.muted)
	hint:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 8, 6)
	hint:SetText("Left-Click: Cycle  |  Right-Click: Clear  |  Shift+Click: Toggle Lock  |  Mousewheel: Scroll")
	f._hint = hint

	-- Footer action bar
	local footer = _G.CreateFrame("Frame", nil, f)
	footer:SetHeight(30)
	footer:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 4)
	footer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 4)

	local btnAuto = Theme.CreateButton(footer, "Auto-Assign", 96, 22, function()
		if _G.IsShiftKeyDown and _G.IsShiftKeyDown() then
			LBB:ResetAssignments()
		else
			LBB:RunNegotiator(true)
		end
	end)
	btnAuto:SetPoint("LEFT", footer, "LEFT", 0, 0)
	btnAuto._tooltipText = "Re-run deterministic auto-negotiation (preserves locked cells). Shift+Click unlocks all."

	local btnReset = Theme.CreateButton(footer, "Reset Locks", 88, 22, function()
		LBB:ResetAssignments()
	end)
	btnReset:SetPoint("LEFT", btnAuto, "RIGHT", 6, 0)
	btnReset._tooltipText = "Clear all manual overrides and re-negotiate"

	local btnSync = Theme.CreateButton(footer, "Sync", 60, 22, function()
		LBB:SyncGroup()
	end)
	btnSync:SetPoint("LEFT", btnReset, "RIGHT", 6, 0)
	btnSync._tooltipText = "Broadcast capabilities and request updates from LBB1 & PLPWR peers"

	local btnNudge = Theme.CreateButton(footer, "Nudge", 64, 22, function()
		if LBB.ReminderPill then
			LBB.ReminderPill:ShowNudgeBar()
		end
	end)
	btnNudge:SetPoint("LEFT", btnSync, "RIGHT", 6, 0)
	btnNudge._tooltipText = "Open Ready Check & Smart Whisper Nudge Bar"

	local btnOpt = Theme.CreateButton(footer, "Options", 68, 22, function()
		if LBB.Options then
			LBB.Options:Toggle()
		end
	end)
	btnOpt:SetPoint("LEFT", btnNudge, "RIGHT", 6, 0)

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

	local labelW = 92
	local colW = 66
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
				function(_, mouseBtn)
					local cur = Assignments:GetGroupBuff(famRef, sgRef)
					local curCaster = cur and cur.caster or nil
					local curLocked = cur and cur.locked or false
					if _G.IsShiftKeyDown and _G.IsShiftKeyDown() then
						applyChange(curCaster, not curLocked)
					elseif mouseBtn == "RightButton" then
						applyChange(nil, true)
					else
						local nextCaster = cycleList(casters, curCaster, 1)
						applyChange(nextCaster, true)
					end
				end,
				function(_, delta)
					local cur = Assignments:GetGroupBuff(famRef, sgRef)
					local nextCaster = cycleList(casters, cur and cur.caster or nil, delta > 0 and -1 or 1)
					applyChange(nextCaster, true)
				end,
				fam.name .. " - Group " .. sg .. (caster and ("\nAssigned: " .. caster) or "\nUnassigned")
			)
			table_insert(self.cells, cell)
		end
		y = y + rowH + 3
	end

	-- Section B: Paladin Blessings (Rows = Paladins, Columns = 9 Classes)
	y = y + 8
	local ppYield = LBB.Comms:IsPallyPowerLoaded()
	local palHdr = self:AcquireLabel(content, 11, "LEFT", ppYield and Theme.Colors.warn or Theme.Colors.accent)
	palHdr:SetPoint("TOPLEFT", content, "TOPLEFT", 10, -y)
	palHdr:SetText(ppYield
		and "Paladin Blessings  |cfffbbf24(Yielded to PallyPower - Read Only)|r"
		or "Paladin Blessings (Synced with PLPWR)")
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
		return
	end

	local clsW = 58
	for idx, cls in ipairs(Catalog.CLASS_ORDER) do
		local cInfo = Catalog.CLASS_INFO[cls]
		local ch = self:AcquireLabel(content, 10, "CENTER", { cInfo.color[1], cInfo.color[2], cInfo.color[3], 1 })
		ch:SetSize(clsW, 14)
		ch:SetPoint("TOPLEFT", content, "TOPLEFT", 10 + labelW + (idx - 1) * (clsW + 2), -y)
		ch:SetText(cInfo.short)
	end
	y = y + 16

	local blessingCycle = { "BOW", "BOM", "BOK", "BOSALV", "BOL", "BOSANC" }
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
			local txt = fam and fam.shortName or "|cff64748b--|r"

			local pRef, clsRef = pName, cls
			local function applyPaladin(newFam, newLock)
				if ppYield then return end
				Assignments:SetClassBuff(pRef, clsRef, newFam, newLock)
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
				function(_, mouseBtn)
					if ppYield then return end
					local cur = Assignments:GetClassBuff(pRef, clsRef)
					if _G.IsShiftKeyDown and _G.IsShiftKeyDown() then
						applyPaladin(cur and cur.familyID or nil, not (cur and cur.locked))
					elseif mouseBtn == "RightButton" then
						applyPaladin(nil, true)
					else
						applyPaladin(cycleList(blessingCycle, cur and cur.familyID or nil, 1), true)
					end
				end,
				function(_, delta)
					if ppYield then return end
					local cur = Assignments:GetClassBuff(pRef, clsRef)
					applyPaladin(cycleList(blessingCycle, cur and cur.familyID or nil, delta > 0 and -1 or 1), true)
				end,
				pName .. " -> " .. Catalog.CLASS_INFO[cls].name .. (fam and (": " .. fam.name) or ": None")
			)
			table_insert(self.cells, cell)
		end
		y = y + rowH + 3
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
	local colW = 120
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
				function(_, mouseBtn)
					local cur = Assignments:GetShamanTotems(sgRef, sName) or { locked = {} }
					if _G.IsShiftKeyDown and _G.IsShiftKeyDown() then
						applyTotem(cur[elRef], not (cur.locked and cur.locked[elRef]))
					elseif mouseBtn == "RightButton" then
						applyTotem(nil, true)
					else
						applyTotem(cycleList(totemIDs, cur[elRef], 1), true)
					end
				end,
				function(_, delta)
					local cur = Assignments:GetShamanTotems(sgRef, sName) or { locked = {} }
					applyTotem(cycleList(totemIDs, cur[elRef], delta > 0 and -1 or 1), true)
				end,
				sName .. " (" .. elRef .. "): " .. (def and def.name or "None")
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
	local widths = { 180, 120, 140, 120 }
	local x = 10
	for i, title in ipairs(cols) do
		local c = self:AcquireLabel(content, 10, i == 1 and "LEFT" or "CENTER", Theme.Colors.muted)
		c:SetSize(widths[i], 16)
		c:SetPoint("TOPLEFT", content, "TOPLEFT", x, -y)
		c:SetText(title)
		x = x + widths[i] + 6
	end
	y = y + 18

	local maxRows = 12
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
	-- Highlight active tab button
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

	-- Update PallyPower bridge badge
	local ppYield = LBB.Comms:IsPallyPowerLoaded()
	if ppYield then
		self.frame._ppStatus:SetText("PLPWR: Yielded to PallyPower")
		self.frame._ppStatus:SetTextColor(Theme.Colors.warn[1], Theme.Colors.warn[2], Theme.Colors.warn[3], 1)
	else
		self.frame._ppStatus:SetText("PLPWR Bridge: Active")
		self.frame._ppStatus:SetTextColor(Theme.Colors.good[1], Theme.Colors.good[2], Theme.Colors.good[3], 1)
	end

	self:ClearContentWidgets()
	local content = self.frame._content
	if self.activeTab == "BUFFS" then
		self:RenderBuffsTab(content)
	elseif self.activeTab == "TOTEMS" then
		self:RenderTotemsTab(content)
	else
		self:RenderConsumablesTab(content)
	end
end
