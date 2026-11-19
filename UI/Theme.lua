local addonName, LBB = ...
LBB = LBB or _G.LittleBuffBoy or {}
_G.LittleBuffBoy = LBB

local Theme = {}
LBB.Theme = Theme

local math_floor = math.floor
local string_format = string.format

Theme.Colors = {
	bg          = { 0.08, 0.09, 0.12, 0.94 },
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
