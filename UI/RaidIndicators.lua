local addonName, LBB = ...
LBB = LBB or _G.LittleBuffBoy or {}
_G.LittleBuffBoy = LBB

local RaidIndicators = {}
LBB.RaidIndicators = RaidIndicators

local pairs = pairs
local ipairs = ipairs
local table_insert = table.insert

RaidIndicators.hooked = false
RaidIndicators.trackedFrames = {}

local MAX_PIPS = 4
local PIP_SIZE = 6
local PIP_GAP = 2

local function ensurePipPool(frame)
	if frame._lbbPips then
		return frame._lbbPips
	end
	local pips = {}
	for i = 1, MAX_PIPS do
		local container = _G.CreateFrame("Frame", nil, frame)
		container:SetSize(PIP_SIZE, PIP_SIZE)
		container:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2 - (i - 1) * (PIP_SIZE + PIP_GAP), 2)
		container:SetFrameLevel((frame.GetFrameLevel and frame:GetFrameLevel() or 1) + 4)

		local bg = container:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints(container)
		bg:SetColorTexture(0.05, 0.06, 0.08, 0.95)

		local fill = container:CreateTexture(nil, "ARTWORK")
		fill:SetPoint("TOPLEFT", container, "TOPLEFT", 1, -1)
		fill:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -1, 1)
		container._fill = fill
		container:Hide()
		pips[i] = container
	end
	frame._lbbPips = pips
	return pips
end

local function hideAllPips(frame)
	if not frame or not frame._lbbPips then
		return
	end
	for i = 1, #frame._lbbPips do
		frame._lbbPips[i]:Hide()
	end
end

function RaidIndicators:UpdateFrame(frame)
	if not frame then
		return
	end
	if LBB.DB and LBB.DB.showRaidIndicators == false then
		hideAllPips(frame)
		return
	end

	local Compat = LBB.Compat
	local unit = frame.displayedUnit or frame.unit
	if type(unit) ~= "string" or not Compat.UnitExists(unit) then
		hideAllPips(frame)
		return
	end
	local unitName = Compat.GetFullUnitName(unit)
	local unitInfo = (unitName and LBB.Assignments.rosterByName[unitName]) or LBB.Assignments.rosterByUnit[unit]
	if Compat.UnitIsDeadOrGhost(unit) then
		-- Notify Scanner of death so a mid-combat Battle Rez triggers a critical missing-buff pip
		LBB.Scanner:ScanUnit(unit, unitInfo)
		hideAllPips(frame)
		return
	end
	if not Compat.UnitIsConnected(unit) or not unitInfo then
		hideAllPips(frame)
		return
	end

	local playerVec = LBB.Capabilities.playerVector
	local playerName = playerVec and playerVec.name or Compat.GetFullUnitName("player")
	local assignedFamilies = LBB.Assignments:GetAssignedFamiliesForUnit(playerName, unitInfo)

	-- Yield Paladin Blessings on raid frames if PallyPower is active
	local ppYield = LBB.Comms and LBB.Comms:IsPallyPowerLoaded()
	local myFamilies = {}
	for _, famID in ipairs(assignedFamilies) do
		local fam = LBB.Catalog.GetFamily(famID)
		if fam and not (ppYield and fam.isBlessing) then
			table_insert(myFamilies, famID)
		end
	end

	if #myFamilies == 0 then
		hideAllPips(frame)
		return
	end

	local now = Compat.GetTime()
	local inCombat = Compat.InCombat()
	local refreshThreshold = (LBB.DB and LBB.DB.refreshThreshold) or LBB.Scanner.DEFAULT_REFRESH_THRESHOLD
	local scan = LBB.Scanner:ScanUnit(unit, unitInfo)

	local alerts = {}
	for _, famID in ipairs(myFamilies) do
		local entry = scan.families[famID]
		if inCombat then
			-- Calm combat mode: suppress low-timer nagging; only highlight critical losses
			-- (e.g., battle-rezzed unit missing your primary buff, or readable aura confirmed missing)
			if not entry and (scan.battleRezzed or not scan.restricted) then
				table_insert(alerts, "MISSING")
			end
		else
			if not entry or not entry.present then
				table_insert(alerts, "MISSING")
			else
				local rem = LBB.Scanner:GetRemainingSeconds(entry, now)
				if rem < refreshThreshold then
					table_insert(alerts, "EXPIRING")
				end
			end
		end
	end

	if #alerts == 0 then
		hideAllPips(frame)
		return
	end

	local Theme = LBB.Theme
	local pips = ensurePipPool(frame)
	self.trackedFrames[frame] = true

	for i = 1, MAX_PIPS do
		local status = alerts[i]
		local pip = pips[i]
		if status then
			local c = (status == "MISSING") and Theme.Colors.danger or Theme.Colors.warn
			pip._fill:SetColorTexture(c[1], c[2], c[3], 1)
			pip:Show()
		else
			pip:Hide()
		end
	end
end

function RaidIndicators:RefreshAll()
	for frame in pairs(self.trackedFrames) do
		if frame.IsShown and frame:IsShown() then
			self:UpdateFrame(frame)
		end
	end
end

function RaidIndicators:Init()
	if self.hooked then
		return
	end
	if _G.hooksecurefunc and _G.CompactUnitFrame_UpdateAuras then
		_G.hooksecurefunc("CompactUnitFrame_UpdateAuras", function(frame)
			if frame and (frame.displayedUnit or frame.unit) and not (frame.IsForbidden and frame:IsForbidden()) then
				self:UpdateFrame(frame)
			end
		end)
		self.hooked = true
	end
end
