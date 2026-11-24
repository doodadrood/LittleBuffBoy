local addonName, LBB = ...
LBB = LBB or _G.LittleBuffBoy or {}
_G.LittleBuffBoy = LBB

local Theme = {}
LBB.Theme = Theme

local math_floor = math.floor
local string_format = string.format

Theme.Colors = {
	bg          = { 0.08, 0.09, 0.12, 0.94 },
	windowBg    = { 0.07, 0.08, 0.11, 1.00 },
	panelSolid  = { 0.11, 0.13, 0.17, 1.00 },
	panel       = { 0.11, 0.13, 0.17, 0.96 },
	header      = { 0.14, 0.17, 0.23, 0.98 },
	tile        = { 0.12, 0.14, 0.19, 0.92 },
	tileHover   = { 0.18, 0.22, 0.30, 0.96 },
	border      = { 0.26, 0.31, 0.40, 0.95 },
	borderLight = { 0.38, 0.46, 0.58, 1.00 },
	accent      = { 0.22, 0.74, 0.97, 1.00 },
	good        = { 0.20, 0.82, 0.45, 1.00 },
	warn        = { 0.98, 0.72, 0.18, 1.00 },
	danger      = { 0.94, 0.28, 0.30, 1.00 },
	locked      = { 0.75, 0.52, 0.99, 1.00 },
	text        = { 0.93, 0.95, 0.98, 1.00 },
	muted       = { 0.58, 0.64, 0.73, 1.00 },
}

function Theme.ApplyPanel(frame, bgColor, borderColor)
	bgColor = bgColor or Theme.Colors.bg
	borderColor = borderColor or Theme.Colors.border

	if not frame._lbbBg then
		local bg = frame:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints(frame)
		frame._lbbBg = bg
	end
	frame._lbbBg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 1)

	if not frame._lbbBorders then
		local borders = {}
		local edges = {
			top    = { { "TOPLEFT", 0, 0 }, { "TOPRIGHT", 0, 0 }, nil, 1 },
			bottom = { { "BOTTOMLEFT", 0, 0 }, { "BOTTOMRIGHT", 0, 0 }, nil, 1 },
			left   = { { "TOPLEFT", 0, 0 }, { "BOTTOMLEFT", 0, 0 }, 1, nil },
			right  = { { "TOPRIGHT", 0, 0 }, { "BOTTOMRIGHT", 0, 0 }, 1, nil },
		}
		for side, cfg in pairs(edges) do
			local tex = frame:CreateTexture(nil, "BORDER")
			tex:SetPoint(cfg[1][1], frame, cfg[1][1], cfg[1][2], cfg[1][3])
			tex:SetPoint(cfg[2][1], frame, cfg[2][1], cfg[2][2], cfg[2][3])
			if cfg[3] then tex:SetWidth(cfg[3]) end
			if cfg[4] then tex:SetHeight(cfg[4]) end
			borders[side] = tex
		end
		frame._lbbBorders = borders
	end
	for _, tex in pairs(frame._lbbBorders) do
		tex:SetColorTexture(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
	end
end

function Theme.SetBorderColor(frame, color)
	if not frame or not frame._lbbBorders or not color then
		return
	end
	for _, tex in pairs(frame._lbbBorders) do
		tex:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
	end
end

function Theme.ApplyDropShadow(frame)
	if not frame or frame._lbbShadow then
		return
	end
	local sh = frame:CreateTexture(nil, "BACKGROUND")
	sh:SetPoint("TOPLEFT", frame, "TOPLEFT", -5, 5)
	sh:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 5, -5)
	sh:SetColorTexture(0, 0, 0, 0.62)
	frame._lbbShadow = sh
end

function Theme.CreateFontString(parent, size, justifyH, color)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	if _G.STANDARD_TEXT_FONT then
		fs:SetFont(_G.STANDARD_TEXT_FONT, size or 11, "OUTLINE")
	else
		fs:SetFont("Fonts\\FRIZQT__.TTF", size or 11, "OUTLINE")
	end
	fs:SetJustifyH(justifyH or "CENTER")
	fs:SetJustifyV("MIDDLE")
	local c = color or Theme.Colors.text
	fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
	return fs
end

function Theme.CreateButton(parent, label, width, height, onClick)
	local btn = _G.CreateFrame("Button", nil, parent)
	btn:SetSize(width or 80, height or 22)
	Theme.ApplyPanel(btn, Theme.Colors.header, Theme.Colors.border)

	local fs = Theme.CreateFontString(btn, 11, "CENTER", Theme.Colors.text)
	fs:SetAllPoints(btn)
	fs:SetText(label or "")
	btn._label = fs

	btn:SetScript("OnEnter", function(self)
		if self._lbbBg then
			local c = Theme.Colors.tileHover
			self._lbbBg:SetColorTexture(c[1], c[2], c[3], c[4])
		end
		Theme.SetBorderColor(self, Theme.Colors.accent)
		if self._tooltipText and _G.GameTooltip then
			_G.GameTooltip:SetOwner(self, "ANCHOR_TOP")
			_G.GameTooltip:ClearLines()
			_G.GameTooltip:AddLine(self._tooltipText, 0.93, 0.95, 0.98, true)
			_G.GameTooltip:Show()
		end
	end)
	btn:SetScript("OnLeave", function(self)
		if self._lbbBg then
			local c = self._baseBg or Theme.Colors.header
			self._lbbBg:SetColorTexture(c[1], c[2], c[3], c[4])
		end
		Theme.SetBorderColor(self, Theme.Colors.border)
		if _G.GameTooltip then
			_G.GameTooltip:Hide()
		end
	end)
	if onClick then
		btn:SetScript("OnClick", onClick)
	end
	return btn
end

function Theme.GetClassColor(classToken)
	local info = LBB.Catalog and LBB.Catalog.CLASS_INFO[classToken]
	if info and info.color then
		return info.color[1], info.color[2], info.color[3]
	end
	return 0.85, 0.88, 0.92
end

function Theme.ColorizeName(name, classToken)
	local r, g, b = Theme.GetClassColor(classToken)
	return string_format("|cff%02x%02x%02x%s|r",
		math_floor(r * 255),
		math_floor(g * 255),
		math_floor(b * 255),
		tostring(name or "")
	)
end

function Theme.FormatTimer(seconds)
	if not seconds or seconds <= 0 then
		return "--"
	end
	if seconds >= 3600 then
		return string_format("%dh", math_floor(seconds / 3600))
	elseif seconds >= 180 then
		return string_format("%dm", math_floor(seconds / 60))
	elseif seconds >= 60 then
		local m = math_floor(seconds / 60)
		local s = math_floor(seconds % 60)
		return string_format("%d:%02d", m, s)
	else
		return string_format("%ds", math_floor(seconds))
	end
end

-- =========================================================================
-- Lightweight Pooled Dark-Slate Popup Dropdown Menu (with inline Submenus)
-- =========================================================================

local MENU_ROW_H = 20
local MENU_PAD = 4

local function ensureMenuPanel(name, parent, level)
	local panel = _G.CreateFrame("Frame", name, parent or _G.UIParent)
	panel:SetFrameStrata("TOOLTIP")
	if panel.SetFrameLevel and level then
		panel:SetFrameLevel(level)
	end
	panel:SetClampedToScreen(true)
	panel:EnableMouse(true)
	Theme.ApplyDropShadow(panel)
	Theme.ApplyPanel(panel, Theme.Colors.windowBg, Theme.Colors.accent)
	panel._rows = {}
	panel:Hide()
	return panel
end

local function populateMenuPanel(panel, items, subPanel, onCloseAll)
	for i = 1, #panel._rows do
		panel._rows[i]:Hide()
	end

	local maxW = 156
	local y = MENU_PAD

	for idx, item in ipairs(items or {}) do
		local row = panel._rows[idx]
		if not row then
			row = _G.CreateFrame("Button", nil, panel)
			row:SetHeight(MENU_ROW_H)
			row:RegisterForClicks("LeftButtonUp")
			row._hl = row:CreateTexture(nil, "BACKGROUND")
			row._hl:SetAllPoints(row)
			row._hl:SetColorTexture(Theme.Colors.tileHover[1], Theme.Colors.tileHover[2], Theme.Colors.tileHover[3], 0.95)
			row._hl:Hide()

			row._left = Theme.CreateFontString(row, 11, "LEFT", Theme.Colors.text)
			row._left:SetPoint("LEFT", row, "LEFT", 8, 0)
			row._right = Theme.CreateFontString(row, 10, "RIGHT", Theme.Colors.muted)
			row._right:SetPoint("RIGHT", row, "RIGHT", -8, 0)
			panel._rows[idx] = row
		end

		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", panel, "TOPLEFT", MENU_PAD, -y)
		row:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -MENU_PAD, -y)
		row._hl:Hide()

		local prefix = ""
		if item.checked then
			prefix = "|cff34d399* |r"
		elseif not item.isTitle and not item.isSeparator then
			prefix = "  "
		end

		local textStr = prefix .. tostring(item.text or "")
		local rightStr = item.rightText or (item.submenu and ">" or "")
		local estW = (#tostring(item.text or "") * 7) + (#tostring(rightStr) * 7) + 38
		if estW > maxW then
			maxW = estW
		end

		if item.isSeparator then
			row:SetHeight(6)
			row._left:SetText("")
			row._right:SetText("")
			row:SetScript("OnClick", nil)
			row:SetScript("OnEnter", nil)
			row:SetScript("OnLeave", nil)
			y = y + 6
		elseif item.isTitle then
			row:SetHeight(18)
			local c = item.color or Theme.Colors.accent
			row._left:SetTextColor(c[1], c[2], c[3], 1)
			row._left:SetText(tostring(item.text or ""))
			row._right:SetText("")
			row:SetScript("OnClick", nil)
			row:SetScript("OnEnter", function()
				if subPanel then subPanel:Hide() end
			end)
			row:SetScript("OnLeave", nil)
			y = y + 18
		else
			row:SetHeight(MENU_ROW_H)
			local c = item.color or Theme.Colors.text
			row._left:SetTextColor(c[1], c[2], c[3], 1)
			row._left:SetText(textStr)
			local rc = item.rightColor or (item.submenu and Theme.Colors.accent or Theme.Colors.muted)
			row._right:SetTextColor(rc[1], rc[2], rc[3], 1)
			row._right:SetText(rightStr)

			local itemRef = item
			row:SetScript("OnEnter", function(self)
				self._hl:Show()
				if subPanel then
					if itemRef.submenu and #itemRef.submenu > 0 then
						populateMenuPanel(subPanel, itemRef.submenu, nil, onCloseAll)
						subPanel:ClearAllPoints()
						subPanel:SetPoint("TOPLEFT", self, "TOPRIGHT", 4, 2)
						subPanel:Show()
					else
						subPanel:Hide()
					end
				end
			end)
			row:SetScript("OnLeave", function(self)
				self._hl:Hide()
			end)
			row:SetScript("OnClick", function(self)
				if itemRef.submenu and #itemRef.submenu > 0 and subPanel then
					populateMenuPanel(subPanel, itemRef.submenu, nil, onCloseAll)
					subPanel:ClearAllPoints()
					subPanel:SetPoint("TOPLEFT", self, "TOPRIGHT", 4, 2)
					subPanel:Show()
					return
				end
				if itemRef.onClick then
					itemRef.onClick()
				end
				if not itemRef.keepOpen and onCloseAll then
					onCloseAll()
				end
			end)
			y = y + MENU_ROW_H
		end
		row:Show()
	end

	panel:SetSize(maxW, y + MENU_PAD)
end

function Theme.HideDropdownMenu()
	if Theme._menuSub then Theme._menuSub:Hide() end
	if Theme._menuMain then Theme._menuMain:Hide() end
	if Theme._menuCatcher then Theme._menuCatcher:Hide() end
end

function Theme.ShowDropdownMenu(anchorFrame, items)
	if not items or #items == 0 then
		Theme.HideDropdownMenu()
		return nil
	end
	if not Theme._menuCatcher then
		local catcher = _G.CreateFrame("Button", "LittleBuffBoyDropdownCatcher", _G.UIParent)
		catcher:SetAllPoints(_G.UIParent)
		catcher:SetFrameStrata("TOOLTIP")
		if catcher.SetFrameLevel then
			catcher:SetFrameLevel(1)
		end
		catcher:EnableMouse(true)
		catcher:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		catcher:SetScript("OnClick", function()
			Theme.HideDropdownMenu()
		end)
		catcher:Hide()
		Theme._menuCatcher = catcher

		Theme._menuMain = ensureMenuPanel("LittleBuffBoyDropdownMain", catcher, 10)
		Theme._menuSub = ensureMenuPanel("LittleBuffBoyDropdownSub", catcher, 25)
		if _G.UISpecialFrames then
			table.insert(_G.UISpecialFrames, "LittleBuffBoyDropdownCatcher")
		end
	end

	Theme._menuSub:Hide()
	populateMenuPanel(Theme._menuMain, items, Theme._menuSub, Theme.HideDropdownMenu)

	Theme._menuMain:ClearAllPoints()
	if anchorFrame then
		Theme._menuMain:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -2)
	else
		Theme._menuMain:SetPoint("CENTER", _G.UIParent, "CENTER", 0, 0)
	end

	Theme._menuCatcher:Show()
	Theme._menuMain:Show()
	return Theme._menuMain
end
