local addonName, LBB = ...
LBB = LBB or _G.LittleBuffBoy or {}
_G.LittleBuffBoy = LBB

local Options = {}
LBB.Options = Options

Options.frame = nil

local function makeToggleRow(parent, y, labelText, getFn, setFn)
	local Theme = LBB.Theme
	local row = _G.CreateFrame("Frame", nil, parent)
	row:SetSize(336, 24)
	row:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, -y)

	local lbl = Theme.CreateFontString(row, 11, "LEFT", Theme.Colors.text)
	lbl:SetPoint("LEFT", row, "LEFT", 0, 0)
	lbl:SetText(labelText)

	local btn = Theme.CreateButton(row, "", 68, 20, function(self)
		local nextVal = not getFn()
		setFn(nextVal)
		self._refresh()
	end)
	btn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	btn._refresh = function()
		local on = getFn()
		btn._label:SetText(on and "|cff34d399ON|r" or "|cffef4444OFF|r")
	end
	btn._refresh()
	return btn
end

function Options:Init()
	if self.frame then
		return self.frame
	end
	local Theme = LBB.Theme
	local f = _G.CreateFrame("Frame", "LittleBuffBoyOptionsFrame", _G.UIParent)
	f:SetSize(366, 496)
	f:SetPoint("CENTER", _G.UIParent, "CENTER", 0, 20)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetFrameStrata("DIALOG")
	Theme.ApplyPanel(f, Theme.Colors.bg, Theme.Colors.borderLight)

	f:SetScript("OnDragStart", function(self) self:StartMoving() end)
	f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

	if _G.UISpecialFrames then
		table.insert(_G.UISpecialFrames, "LittleBuffBoyOptionsFrame")
	end

	local header = _G.CreateFrame("Frame", nil, f)
	header:SetHeight(28)
	header:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
	header:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
	Theme.ApplyPanel(header, Theme.Colors.header, Theme.Colors.border)

	local title = Theme.CreateFontString(header, 12, "LEFT", Theme.Colors.accent)
	title:SetPoint("LEFT", header, "LEFT", 10, 0)
	title:SetText("LittleBuffBoy  |cff94a3b8Options|r")

	local closeBtn = Theme.CreateButton(header, "X", 22, 18, function() f:Hide() end)
	closeBtn:SetPoint("RIGHT", header, "RIGHT", -5, 0)

	f._refreshables = {}
	local y = 38

	table.insert(f._refreshables, makeToggleRow(f, y, "Lock Buff Strip Position",
		function() return LBB.DB and LBB.DB.locked end,
		function(v)
			LBB.DB.locked = v
			if LBB.BuffStrip then LBB.BuffStrip:UpdateLockVisual() end
		end
	))
	y = y + 28

	table.insert(f._refreshables, makeToggleRow(f, y, "Vertical Buff Strip",
		function() return LBB.DB and LBB.DB.stripOrientation == "VERTICAL" end,
		function(v)
			LBB.DB.stripOrientation = v and "VERTICAL" or "HORIZONTAL"
			LBB:RefreshUI()
		end
	))
	y = y + 28

	-- Buff Strip Scale stepper (0.7x - 1.4x)
	local scaleRow = _G.CreateFrame("Frame", nil, f)
	scaleRow:SetSize(336, 24)
	scaleRow:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -y)
	local scLbl = Theme.CreateFontString(scaleRow, 11, "LEFT", Theme.Colors.text)
	scLbl:SetPoint("LEFT", scaleRow, "LEFT", 0, 0)
	scLbl:SetText("Buff Strip Scale (0.7x - 1.4x)")
	local scVal = Theme.CreateFontString(scaleRow, 11, "CENTER", Theme.Colors.accent)
	scVal:SetSize(44, 20)
	scVal:SetPoint("RIGHT", scaleRow, "RIGHT", -28, 0)
	local function applyScale(delta)
		local cur = (LBB.DB and LBB.DB.stripScale) or 1.0
		local nextVal = math.floor(((cur + delta) * 10) + 0.5) / 10
		if nextVal < 0.7 then nextVal = 0.7 end
		if nextVal > 1.4 then nextVal = 1.4 end
		LBB.DB.stripScale = nextVal
		scVal:SetText(string.format("%.1fx", nextVal))
		LBB:RefreshUI()
	end
	local btnScaleDown = Theme.CreateButton(scaleRow, "-", 24, 20, function() applyScale(-0.1) end)
	btnScaleDown:SetPoint("RIGHT", scVal, "LEFT", -2, 0)
	local btnScaleUp = Theme.CreateButton(scaleRow, "+", 24, 20, function() applyScale(0.1) end)
	btnScaleUp:SetPoint("RIGHT", scaleRow, "RIGHT", 0, 0)
	scaleRow._refresh = function()
		scVal:SetText(string.format("%.1fx", (LBB.DB and LBB.DB.stripScale) or 1.0))
	end
	scaleRow._refresh()
	table.insert(f._refreshables, scaleRow)
	y = y + 28

	-- Healthy Strip Behavior (Always Show / Fade 35% / Auto-Hide)
	local healthyRow = _G.CreateFrame("Frame", nil, f)
	healthyRow:SetSize(336, 24)
	healthyRow:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -y)
	local hLbl = Theme.CreateFontString(healthyRow, 11, "LEFT", Theme.Colors.text)
	hLbl:SetPoint("LEFT", healthyRow, "LEFT", 0, 0)
	hLbl:SetText("When All Buffs Healthy")
	local healthyModes = {
		{ id = "SHOW", label = "Always Show" },
		{ id = "FADE", label = "Fade (35%)" },
		{ id = "HIDE", label = "Auto-Hide" },
	}
	local hBtn = Theme.CreateButton(healthyRow, "Always Show", 110, 20, function(self)
		local cur = (LBB.DB and LBB.DB.stripHealthyMode) or "SHOW"
		local nextIdx = 1
		for i, m in ipairs(healthyModes) do
			if m.id == cur then
				nextIdx = (i % #healthyModes) + 1
				break
			end
		end
		LBB.DB.stripHealthyMode = healthyModes[nextIdx].id
		self._refresh()
		LBB:RefreshUI()
	end)
	hBtn:SetPoint("RIGHT", healthyRow, "RIGHT", 0, 0)
	hBtn._refresh = function()
		local cur = (LBB.DB and LBB.DB.stripHealthyMode) or "SHOW"
		for _, m in ipairs(healthyModes) do
			if m.id == cur then
				hBtn._label:SetText(m.label)
				break
			end
		end
	end
	hBtn._refresh()
	table.insert(f._refreshables, hBtn)
	y = y + 28

	table.insert(f._refreshables, makeToggleRow(f, y, "Show Smart Auto-Buff Tile",
		function() return LBB.DB == nil or LBB.DB.showAutoBuffTile ~= false end,
		function(v)
			LBB.DB.showAutoBuffTile = v
			LBB:RefreshUI()
		end
	))
	y = y + 28

	table.insert(f._refreshables, makeToggleRow(f, y, "Show Minimap Icon",
		function() return LBB.MinimapButton and LBB.MinimapButton:IsShown() or (not (LBB.DB and LBB.DB.minimap and LBB.DB.minimap.hide)) end,
		function(v)
			if LBB.MinimapButton then
				LBB.MinimapButton:SetShown(v)
			elseif LBB.DB then
				LBB.DB.minimap = LBB.DB.minimap or { minimapPos = 220 }
				LBB.DB.minimap.hide = not v
			end
		end
	))
	y = y + 28

	table.insert(f._refreshables, makeToggleRow(f, y, "Raid Frame Micro-Indicators",
		function() return LBB.DB == nil or LBB.DB.showRaidIndicators ~= false end,
		function(v)
			LBB.DB.showRaidIndicators = v
			if LBB.RaidIndicators then LBB.RaidIndicators:RefreshAll() end
		end
	))
	y = y + 28

	table.insert(f._refreshables, makeToggleRow(f, y, "Auto-Negotiate on Roster Change",
		function() return LBB.DB == nil or LBB.DB.autoNegotiate ~= false end,
		function(v) LBB.DB.autoNegotiate = v end
	))
	y = y + 28

	table.insert(f._refreshables, makeToggleRow(f, y, "Auto-Remember Minimap Tracking",
		function() return LBB.DB == nil or LBB.DB.autoRememberTracking ~= false end,
		function(v) LBB.DB.autoRememberTracking = v end
	))
	y = y + 28

	table.insert(f._refreshables, makeToggleRow(f, y, "PLPWR Free Assignment",
		function() return LBB.DB and LBB.DB.freeAssign end,
		function(v)
			LBB.DB.freeAssign = v
			if LBB.Comms then LBB.Comms:SendPLPWRSelf() end
		end
	))
	y = y + 32

	-- Refresh Threshold cycle button
	local threshRow = _G.CreateFrame("Frame", nil, f)
	threshRow:SetSize(336, 24)
	threshRow:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -y)
	local tLbl = Theme.CreateFontString(threshRow, 11, "LEFT", Theme.Colors.text)
	tLbl:SetPoint("LEFT", threshRow, "LEFT", 0, 0)
	tLbl:SetText("Expiring Warning Threshold")
	local steps = { 60, 120, 180, 300, 600 }
	local tBtn = Theme.CreateButton(threshRow, "3 min", 80, 20, function(self)
		local cur = (LBB.DB and LBB.DB.refreshThreshold) or 180
		local nextVal = steps[1]
		for i, s in ipairs(steps) do
			if s == cur then
				nextVal = steps[(i % #steps) + 1]
				break
			end
		end
		LBB.DB.refreshThreshold = nextVal
		self._refresh()
		LBB:RefreshUI()
	end)
	tBtn:SetPoint("RIGHT", threshRow, "RIGHT", 0, 0)
	tBtn._refresh = function()
		local cur = (LBB.DB and LBB.DB.refreshThreshold) or 180
		tBtn._label:SetText(string.format("%d min", math.floor(cur / 60)))
	end
	tBtn._refresh()
	table.insert(f._refreshables, tBtn)
	y = y + 28

	-- Preferred Tracking cycler
	local trackRow = _G.CreateFrame("Frame", nil, f)
	trackRow:SetSize(336, 24)
	trackRow:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -y)
	local trLbl = Theme.CreateFontString(trackRow, 11, "LEFT", Theme.Colors.text)
	trLbl:SetPoint("LEFT", trackRow, "LEFT", 0, 0)
	trLbl:SetText("Pinned Tracking")
	local trBtn = Theme.CreateButton(trackRow, "Auto", 150, 20, function(self)
		local modes = LBB.Tracking:GetAvailableModes()
		local pref = LBB.Tracking:GetPreferred()
		if #modes == 0 then
			LBB.Tracking:SetPreferred(nil)
		else
			local idx = 0
			for i, m in ipairs(modes) do
				if pref and pref.name == m.name then
					idx = i
					break
				end
			end
			if idx >= #modes then
				LBB.Tracking:SetPreferred(nil)
			else
				LBB.Tracking:SetPreferred(modes[idx + 1], true)
			end
		end
		self._refresh()
	end)
	trBtn:SetPoint("RIGHT", trackRow, "RIGHT", 0, 0)
	trBtn._refresh = function()
		local pref = LBB.Tracking:GetPreferred()
		trBtn._label:SetText(pref and pref.name or "Auto / None")
	end
	trBtn._refresh()
	table.insert(f._refreshables, trBtn)
	y = y + 32

	-- Paladin Self Buffs (Righteous Fury opt-in + Seal dropdown)
	table.insert(f._refreshables, makeToggleRow(f, y, "Paladin: Track Righteous Fury",
		function()
			local cfg = LBB.Assignments and LBB.Assignments:GetPaladinSelfConfig()
			return cfg and cfg.trackRF or false
		end,
		function(v)
			LBB.Assignments:SetRighteousFuryEnabled(v)
			LBB:RefreshUI()
		end
	))
	y = y + 28

	local sealRow = _G.CreateFrame("Frame", nil, f)
	sealRow:SetSize(336, 24)
	sealRow:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -y)
	local sLbl = Theme.CreateFontString(sealRow, 11, "LEFT", Theme.Colors.text)
	sLbl:SetPoint("LEFT", sealRow, "LEFT", 0, 0)
	sLbl:SetText("Paladin: Active Seal")
	local sBtn = Theme.CreateButton(sealRow, "Off", 160, 20, function(self)
		if LBB.MatrixFrame and LBB.MatrixFrame.BuildPaladinSealMenu then
			Theme.ShowDropdownMenu(self, LBB.MatrixFrame:BuildPaladinSealMenu())
		end
	end)
	sBtn:SetPoint("RIGHT", sealRow, "RIGHT", 0, 0)
	sBtn._refresh = function()
		local cfg = LBB.Assignments and LBB.Assignments:GetPaladinSelfConfig()
		sBtn._label:SetText((cfg and cfg.trackSeal and cfg.sealName) and cfg.sealName or "Off")
	end
	sBtn._refresh()
	table.insert(f._refreshables, sBtn)
	y = y + 32

	-- PallyPower Bridge Status
	local ppLbl = Theme.CreateFontString(f, 10, "LEFT", Theme.Colors.muted)
	ppLbl:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 12)
	f._ppLbl = ppLbl

	f:Hide()
	self.frame = f
	return f
end

function Options:Refresh()
	if not self.frame then
		return
	end
	for _, item in ipairs(self.frame._refreshables or {}) do
		if item._refresh then
			item._refresh()
		end
	end
	local ppYield = LBB.Comms and LBB.Comms:IsPallyPowerLoaded()
	self.frame._ppLbl:SetText(ppYield
		and "PallyPower Bridge: |cfffbbf24Yielded to standalone PallyPower|r"
		or "PallyPower Bridge: |cff34d399Active (native PLPWR sync)|r")
end

function Options:Toggle()
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
