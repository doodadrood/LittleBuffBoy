local addonName, LBB = ...
LBB = LBB or _G.LittleBuffBoy or {}
_G.LittleBuffBoy = LBB

local Comms = {}
LBB.Comms = Comms

local pairs = pairs
local ipairs = ipairs
local tonumber = tonumber
local tostring = tostring
local math_min = math.min
local math_max = math.max
local math_ceil = math.ceil
local string_format = string.format
local string_sub = string.sub
local table_insert = table.insert
local table_remove = table.remove
local table_concat = table.concat

Comms.PREFIX_LBB = "LBB1"
Comms.PREFIX_PLPWR = "PLPWR"
Comms.MAX_PACKET_BYTES = 255
Comms.REASSEMBLY_TTL = 15

-- Throttle config (token bucket)
Comms.THROTTLE_BURST = 6
Comms.THROTTLE_RATE = 4 -- messages per second

Comms.initialized = false
Comms.msgSeq = 0
Comms.reassembly = {}
Comms.sendQueue = {}
Comms.tokens = Comms.THROTTLE_BURST
Comms.lastTick = 0
Comms.freeAssign = {}
Comms.listeners = {}

function Comms:Reset()
	self.msgSeq = 0
	self.reassembly = {}
	self.sendQueue = {}
	self.tokens = self.THROTTLE_BURST
	self.lastTick = LBB.Compat.GetTime()
	self.freeAssign = {}
	self.listeners = {}
	self.initialized = false
end

function Comms:OnChange(callback)
	if type(callback) == "function" then
		table_insert(self.listeners, callback)
	end
end

function Comms:NotifyChange(reason, payload)
	for _, fn in ipairs(self.listeners) do
		pcall(fn, reason, payload)
	end
end

function Comms:Init()
	local Compat = LBB.Compat
	Compat.RegisterAddonMessagePrefix(self.PREFIX_LBB)
	Compat.RegisterAddonMessagePrefix(self.PREFIX_PLPWR)
	self.lastTick = Compat.GetTime()
	self.tokens = self.THROTTLE_BURST
	self.initialized = true
end

-- Automatic yield when standalone PallyPower is loaded
function Comms:IsPallyPowerLoaded()
	return LBB.Compat.IsAddOnLoaded("PallyPower")
end

-- Wire escaping helpers
local function escapeField(s)
	s = tostring(s or "")
	s = s:gsub("%%", "%%25")
	s = s:gsub("|", "%%7C")
	return s
end

local function unescapeField(s)
	s = tostring(s or "")
	s = s:gsub("%%7C", "|")
	s = s:gsub("%%25", "%%")
	return s
end

local function splitPipe(str)
	local out = {}
	local idx = 1
	while true do
		local pos = str:find("|", idx, true)
		if not pos then
			table_insert(out, unescapeField(str:sub(idx)))
			break
		end
		table_insert(out, unescapeField(str:sub(idx, pos - 1)))
		idx = pos + 1
	end
	return out
end

-- Forever names contain a space ("First Last"); PallyPower NASSIGN uses "_" on the wire
function Comms.WirePPName(name)
	return tostring(name or ""):gsub(" ", "_")
end

function Comms.UnwirePPName(name)
	return tostring(name or ""):gsub("_", " ")
end

-- =========================================================================
-- LBB1 Chunking, Reassembly & Lightweight Throttling
-- =========================================================================

function Comms:ChunkPayload(payload, msgID)
	payload = tostring(payload or "")
	if not msgID then
		self.msgSeq = (self.msgSeq % 99999) + 1
		msgID = tostring(self.msgSeq)
	else
		msgID = tostring(msgID)
	end

	-- Fast path: single chunk
	local singleHeader = string_format("1:%s:1/1:", msgID)
	if #singleHeader + #payload <= self.MAX_PACKET_BYTES then
		return { singleHeader .. payload }
	end

	-- Multi-chunk: estimate total chunks conservatively so header length is exact
	local maxHeaderGuess = string_format("1:%s:99/99:", msgID)
	local maxBody = self.MAX_PACKET_BYTES - #maxHeaderGuess
	if maxBody < 32 then
		maxBody = 32
	end

	local rawSlices = {}
	local pos = 1
	local len = #payload
	while pos <= len do
		local nextPos = math_min(len, pos + maxBody - 1)
		table_insert(rawSlices, string_sub(payload, pos, nextPos))
		pos = nextPos + 1
	end

	local total = #rawSlices
	local frames = {}
	for i = 1, total do
		local frame = string_format("1:%s:%d/%d:%s", msgID, i, total, rawSlices[i])
		table_insert(frames, frame)
	end
	return frames
end

function Comms:PruneReassembly(now)
	now = now or LBB.Compat.GetTime()
	for key, bucket in pairs(self.reassembly) do
		if (now - bucket.createdAt) > self.REASSEMBLY_TTL then
			self.reassembly[key] = nil
		end
	end
end

function Comms:IngestLBBFrame(sender, rawFrame)
	if type(rawFrame) ~= "string" then
		return nil
	end
	local ver, msgID, partStr, totalStr, body = rawFrame:match("^(%d+):([^:]+):(%d+)/(%d+):(.*)$")
	if ver ~= "1" then
		return nil
	end
	local part = tonumber(partStr)
	local total = tonumber(totalStr)
	if not part or not total or part < 1 or total < 1 or part > total then
		return nil
	end
	if total == 1 then
		return body
	end

	local now = LBB.Compat.GetTime()
	self:PruneReassembly(now)

	local key = tostring(sender) .. "::" .. msgID
	local bucket = self.reassembly[key]
	if not bucket or bucket.total ~= total then
		bucket = {
			total = total,
			parts = {},
			received = 0,
			createdAt = now,
		}
		self.reassembly[key] = bucket
	end
	if bucket.parts[part] == nil then
		bucket.parts[part] = body
		bucket.received = bucket.received + 1
	end
	if bucket.received >= total then
		local combined = {}
		for i = 1, total do
			combined[i] = bucket.parts[i] or ""
		end
		self.reassembly[key] = nil
		return table_concat(combined)
	end
	return nil
end

function Comms:Enqueue(prefix, frame, channel, target, dedupeKey)
	if not channel then
		channel = LBB.Compat.GetGroupChannel()
	end
	if not channel then
		return false
	end
	if dedupeKey then
		for i = #self.sendQueue, 1, -1 do
			if self.sendQueue[i].dedupeKey == dedupeKey then
				table_remove(self.sendQueue, i)
			end
		end
	end
	table_insert(self.sendQueue, {
		prefix = prefix,
		frame = frame,
		channel = channel,
		target = target,
		dedupeKey = dedupeKey,
	})
	self:ProcessQueue(LBB.Compat.GetTime())
	return true
end

function Comms:ProcessQueue(now)
	now = now or LBB.Compat.GetTime()
	local elapsed = math_max(0, now - (self.lastTick or now))
	self.lastTick = now
	self.tokens = math_min(self.THROTTLE_BURST, self.tokens + elapsed * self.THROTTLE_RATE)

	local sent = 0
	while #self.sendQueue > 0 and self.tokens >= 1 do
		local item = table_remove(self.sendQueue, 1)
		LBB.Compat.SendAddonMessage(item.prefix, item.frame, item.channel, item.target)
		self.tokens = self.tokens - 1
		sent = sent + 1
	end
	return sent
end

function Comms:SendLBB(payload, channel, target, dedupeKey)
	channel = channel or LBB.Compat.GetGroupChannel()
	if not channel then
		return false
	end
	local frames = self:ChunkPayload(payload)
	for idx, frame in ipairs(frames) do
		local dKey = (dedupeKey and #frames == 1) and dedupeKey or nil
		self:Enqueue(self.PREFIX_LBB, frame, channel, target, dKey)
	end
	return true
end

-- =========================================================================
-- LBB1 High-Level Broadcasts & Handlers
-- =========================================================================

function Comms:BroadcastCapabilities(channel, target)
	local vec = LBB.Capabilities:GetPlayerVector()
	if not vec then
		return false
	end
	local capData = LBB.Capabilities:SerializeVector(vec)
	local payload = table_concat({
		"CAP",
		escapeField(vec.name),
		escapeField(vec.class),
		escapeField(capData),
	}, "|")
	return self:SendLBB(payload, channel, target, target and nil or "LBB_CAP")
end

function Comms:SendRequest(channel)
	local okLbb = self:SendLBB("REQ", channel, nil, "LBB_REQ")
	local okPP = false
	if not self:IsPallyPowerLoaded() then
		okPP = self:SendPLPWR("REQ", channel)
	end
	return okLbb or okPP
end

function Comms:BroadcastLock(scope, key, buffID, casterName, locked, extraClass)
	local payload = table_concat({
		"LOCK",
		escapeField(scope),
		escapeField(key),
		escapeField(buffID or ""),
		escapeField(casterName or ""),
		locked and "1" or "0",
		escapeField(extraClass or ""),
	}, "|")
	self:SendLBB(payload)

	-- Mirror Paladin blessing / per-player override / aura locks to PLPWR peers when not yielded to PallyPower
	if not self:IsPallyPowerLoaded() then
		if scope == "CLASS" then
			local clsID = LBB.Catalog.CLASS_TO_ID[key]
			local ppID = (buffID and LBB.Catalog.FAMILY_TO_PALLYPOWER_ID[buffID]) or 0
			if clsID and casterName then
				self:SendPLPWRAssign(casterName, clsID, ppID)
			end
		elseif scope == "NORMAL" and casterName and key then
			local clsToken = extraClass
			if (not clsToken or clsToken == "") and LBB.Assignments.rosterByName[key] then
				clsToken = LBB.Assignments.rosterByName[key].class
			end
			local clsID = clsToken and LBB.Catalog.CLASS_TO_ID[clsToken]
			local ppID = (buffID and LBB.Catalog.FAMILY_TO_PALLYPOWER_ID[buffID]) or 0
			if clsID then
				self:SendPLPWRNormalAssign(casterName, clsID, key, ppID)
			end
		elseif scope == "AURA" and casterName then
			local auraID = tonumber(buffID) or 0
			self:SendPLPWRAuraAssign(casterName, auraID)
		end
	end
end

function Comms:BroadcastClassAll(casterName, familyID, locked)
	local payload = table_concat({
		"LOCK",
		"CLASS_ALL",
		escapeField(casterName or ""),
		escapeField(familyID or ""),
		escapeField(casterName or ""),
		locked and "1" or "0",
		"",
	}, "|")
	self:SendLBB(payload)
	if not self:IsPallyPowerLoaded() and casterName then
		local ppID = (familyID and LBB.Catalog.FAMILY_TO_PALLYPOWER_ID[familyID]) or 0
		self:SendPLPWRMassAssign(casterName, ppID)
	end
end

function Comms:BroadcastGroupAll(familyID, casterName, locked)
	local payload = table_concat({
		"LOCK",
		"GROUP_ALL",
		escapeField(familyID or ""),
		escapeField(familyID or ""),
		escapeField(casterName or ""),
		locked and "1" or "0",
		"",
	}, "|")
	self:SendLBB(payload)
end

function Comms:BroadcastTotem(subgroup, casterName, earth, fire, water, air, lockedMask)
	local payload = table_concat({
		"TOTEM",
		tostring(subgroup or 1),
		escapeField(casterName or ""),
		escapeField(earth or ""),
		escapeField(fire or ""),
		escapeField(water or ""),
		escapeField(air or ""),
		escapeField(lockedMask or "0000"),
	}, "|")
	return self:SendLBB(payload)
end

function Comms:BroadcastRenegotiate()
	return self:SendLBB("RENEG", nil, nil, "LBB_RENEG")
end

function Comms:HandleLBBMessage(sender, payload, distribution)
	local fields = splitPipe(payload)
	local cmd = fields[1]
	if not cmd then
		return
	end

	if cmd == "REQ" then
		self:BroadcastCapabilities("WHISPER", sender)
		return
	end

	if cmd == "CAP" then
		local name = LBB.Compat.NormalizeName(fields[2]) or sender
		local capData = fields[4] or ""
		local vec = LBB.Capabilities:DeserializeVector(name, capData)
		if vec then
			LBB.Capabilities:SetPeerVector(name, vec)
			self:NotifyChange("CAP", name)
		end
		return
	end

	if cmd == "LOCK" then
		local scope = fields[2]
		local key = fields[3]
		local buffID = fields[4]
		local casterName = LBB.Compat.NormalizeName(fields[5])
		local locked = (fields[6] == "1")
		if buffID == "" then
			buffID = nil
		end
		if scope == "GROUP" then
			local sg = tonumber(key)
			if sg and buffID then
				LBB.Assignments:SetGroupBuff(buffID, sg, casterName, locked)
				self:NotifyChange("LOCK", scope)
			end
		elseif scope == "CLASS" then
			if not self:IsPallyPowerLoaded() and casterName and key then
				LBB.Assignments:SetClassBuff(casterName, key, buffID, locked)
				LBB.Assignments:SaveToCharDB()
				self:NotifyChange("LOCK", scope)
			end
		elseif scope == "CLASS_ALL" then
			if not self:IsPallyPowerLoaded() and casterName then
				LBB.Assignments:SetAllClassBuffs(casterName, buffID, locked)
				self:NotifyChange("LOCK", scope)
			end
		elseif scope == "GROUP_ALL" then
			if buffID then
				LBB.Assignments:SetAllGroupBuffs(buffID, casterName, locked)
				self:NotifyChange("LOCK", scope)
			end
		elseif scope == "NORMAL" then
			if not self:IsPallyPowerLoaded() and casterName and key then
				local clsToken = fields[7]
				if clsToken == "" then clsToken = nil end
				LBB.Assignments:SetPaladinNormalOverride(casterName, key, clsToken, buffID, locked)
				LBB.Assignments:SaveToCharDB()
				self:NotifyChange("LOCK", scope)
			end
		elseif scope == "TARGET" then
			if buffID and key then
				LBB.Assignments:SetTargetBuff(buffID, key, casterName, locked)
				LBB.Assignments:SaveToCharDB()
				self:NotifyChange("LOCK", scope)
			end
		elseif scope == "ROLE" then
			if buffID and key then
				LBB.Assignments:SetRoleBuff(buffID, key, casterName, locked)
				LBB.Assignments:SaveToCharDB()
				self:NotifyChange("LOCK", scope)
			end
		elseif scope == "AURA" then
			if not self:IsPallyPowerLoaded() and casterName then
				LBB.Assignments:SetPaladinAura(casterName, tonumber(buffID) or 0, locked)
				self:NotifyChange("LOCK", scope)
			end
		end
		return
	end

	if cmd == "TOTEM" then
		local sg = tonumber(fields[2]) or 1
		local caster = LBB.Compat.NormalizeName(fields[3])
		local mask = fields[8] or "0000"
		if caster then
			local vals = { fields[4], fields[5], fields[6], fields[7] }
			for i, el in ipairs(LBB.Catalog.TOTEM_ELEMENTS) do
				local tid = vals[i]
				if tid == "" then
					tid = nil
				end
				local isLocked = (mask:sub(i, i) == "1")
				LBB.Assignments:SetShamanTotem(sg, caster, el, tid, isLocked)
			end
			self:NotifyChange("TOTEM", caster)
		end
		return
	end

	if cmd == "RENEG" then
		self:NotifyChange("RENEG", sender)
		return
	end
end

-- =========================================================================
-- Native PLPWR Bridge (PallyPower Forever 100% Compatibility + Yield)
-- =========================================================================

function Comms:SendPLPWR(msg, channel, target)
	if self:IsPallyPowerLoaded() then
		return false, "yielded"
	end
	channel = channel or LBB.Compat.GetGroupChannel()
	if not channel then
		return false, "no_channel"
	end
	return self:Enqueue(self.PREFIX_PLPWR, msg, channel, target), nil
end

function Comms:BuildPLPWRSelf(vec, assignments)
	local Catalog = LBB.Catalog
	vec = vec or LBB.Capabilities:GetPlayerVector()
	assignments = assignments or LBB.Assignments
	if not vec or vec.class ~= "PALADIN" then
		return nil
	end

	-- 6 blessings x 2 chars (hex rank, hex talent) or "nn"
	local skillChars = {}
	for ppID = 1, 6 do
		local famID = Catalog.PALLYPOWER_ID_TO_FAMILY[ppID]
		local b = famID and vec.buffs and vec.buffs[famID]
		if b and b.known then
			local rank = math_min(15, math_max(1, b.bestSingleRank or 1))
			local talent = math_min(15, math_max(0, b.talentRank or 0))
			table_insert(skillChars, string_format("%x%x", rank, talent))
		else
			table_insert(skillChars, "nn")
		end
	end

	-- 9 classes (1..9): blessing ID or "n"
	local assignChars = {}
	local myClasses = assignments.classBuffs[vec.name] or {}
	for clsID = 1, 9 do
		local clsToken = Catalog.ID_TO_CLASS[clsID]
		local entry = clsToken and myClasses[clsToken]
		local ppID = entry and entry.familyID and Catalog.FAMILY_TO_PALLYPOWER_ID[entry.familyID] or 0
		if ppID and ppID > 0 then
			table_insert(assignChars, tostring(ppID))
		else
			table_insert(assignChars, "n")
		end
	end

	return "SELF " .. table_concat(skillChars) .. "@" .. table_concat(assignChars)
end

function Comms:BuildPLPWRAuraSelf(vec, assignments)
	local Catalog = LBB.Catalog
	vec = vec or LBB.Capabilities:GetPlayerVector()
	assignments = assignments or LBB.Assignments
	if not vec or vec.class ~= "PALADIN" then
		return nil
	end
	local auraChars = {}
	for aid = 1, 7 do
		local a = vec.auras and vec.auras[aid]
		if a then
			table_insert(auraChars, string_format("%x0", math_min(15, math_max(1, a.rank or 1))))
		else
			table_insert(auraChars, "nn")
		end
	end
	local assigned = assignments:GetPaladinAura(vec.name)
	local aid = (assigned and assigned.auraID) or 0
	return "ASELF " .. table_concat(auraChars) .. "@" .. tostring(aid)
end

function Comms:SendPLPWRSelf(target)
	if self:IsPallyPowerLoaded() then
		return false, "yielded"
	end
	local vec = LBB.Capabilities:GetPlayerVector()
	if not vec or vec.class ~= "PALADIN" then
		return false, "not_paladin"
	end
	local channel = target and "WHISPER" or LBB.Compat.GetGroupChannel()
	if not channel then
		return false, "no_channel"
	end
	local selfMsg = self:BuildPLPWRSelf(vec, LBB.Assignments)
	if selfMsg then
		self:SendPLPWR(selfMsg, channel, target)
	end
	local auraMsg = self:BuildPLPWRAuraSelf(vec, LBB.Assignments)
	if auraMsg then
		self:SendPLPWR(auraMsg, channel, target)
	end
	-- Also transmit any per-player normal overrides in PallyPower NASSIGN format (batched 5 per packet)
	local normMap = LBB.Assignments.paladinNormalOverrides[vec.name]
	if normMap then
		local entries = {}
		local tNames = {}
		for tName in pairs(normMap) do
			table_insert(tNames, tName)
		end
		table.sort(tNames)
		for _, tName in ipairs(tNames) do
			local ov = normMap[tName]
			local cls = ov.class or (LBB.Assignments.rosterByName[tName] and LBB.Assignments.rosterByName[tName].class)
			local clsID = cls and LBB.Catalog.CLASS_TO_ID[cls]
			local bid = ov.familyID and LBB.Catalog.FAMILY_TO_PALLYPOWER_ID[ov.familyID]
			if clsID and bid and bid > 0 then
				table_insert(entries, string_format("%s %d %s %d", Comms.WirePPName(vec.name), clsID, Comms.WirePPName(tName), bid))
			end
		end
		local idx = 1
		while idx <= #entries do
			local last = math_min(idx + 4, #entries)
			self:SendPLPWR("NASSIGN " .. table_concat(entries, "@", idx, last), channel, target)
			idx = idx + 5
		end
	end
	local sym = vec.symbols or LBB.Compat.GetItemCount(21177)
	local freeFlag = (LBB.DB and LBB.DB.freeAssign) and "YES" or "NO"
	self:SendPLPWR(string_format("FREEASSIGN %s | SYMCOUNT %d | COOLDOWNS:n:n:n:n", freeFlag, sym), channel, target)
	return true
end

function Comms:SendPLPWRAssign(pallyName, classID, blessingID)
	return self:SendPLPWR(string_format("ASSIGN %s %d %d", tostring(pallyName), tonumber(classID) or 0, tonumber(blessingID) or 0))
end

function Comms:SendPLPWRMassAssign(pallyName, blessingID)
	return self:SendPLPWR(string_format("MASSIGN %s %d", tostring(pallyName), tonumber(blessingID) or 0))
end

function Comms:SendPLPWRAuraAssign(pallyName, auraID)
	return self:SendPLPWR(string_format("AASSIGN %s %d", tostring(pallyName), tonumber(auraID) or 0))
end

function Comms:SendPLPWRNormalAssign(pallyName, classID, targetName, blessingID)
	return self:SendPLPWR(string_format("NASSIGN %s %d %s %d",
		Comms.WirePPName(pallyName),
		tonumber(classID) or 0,
		Comms.WirePPName(targetName),
		tonumber(blessingID) or 0
	))
end

function Comms:SendPLPWRClear()
	return self:SendPLPWR("CLEAR")
end

local function isSenderAuthorizedForPLPWR(sender, targetPally)
	if sender == targetPally then
		return true
	end
	local rosterEntry = LBB.Assignments.rosterByName[sender]
	if rosterEntry and (rosterEntry.isLeader or rosterEntry.isAssist) then
		return true
	end
	if Comms.freeAssign[targetPally] or (LBB.DB and LBB.DB.freeAssign) then
		return true
	end
	return false
end

function Comms:HandlePLPWRMessage(sender, msg, distribution)
	local Catalog = LBB.Catalog
	local Assignments = LBB.Assignments
	local Capabilities = LBB.Capabilities

	if msg == "REQ" then
		if not self:IsPallyPowerLoaded() then
			self:SendPLPWRSelf(sender)
		end
		return
	end

	-- SELF <numbers>@<assign>
	if msg:find("^SELF ") then
		local numbers, assign = msg:match("^SELF ([0-9a-fn]*)@([0-9n]*)")
		if numbers then
			local existing = Capabilities:GetPeerVector(sender)
			local vec = existing or {
				name = sender,
				guid = sender,
				class = "PALADIN",
				source = "PLPWR",
				buffs = {},
				auras = {},
				totems = {},
				symbols = 0,
			}
			vec.class = "PALADIN"
			if vec.source ~= "LBB" then
				vec.source = "PLPWR"
			end
			vec.buffs = {}
			for ppID = 1, 6 do
				local rankChar = numbers:sub((ppID - 1) * 2 + 1, (ppID - 1) * 2 + 1)
				local talChar = numbers:sub((ppID - 1) * 2 + 2, (ppID - 1) * 2 + 2)
				if rankChar ~= "" and rankChar ~= "n" then
					local famID = Catalog.PALLYPOWER_ID_TO_FAMILY[ppID]
					local fam = famID and Catalog.GetFamily(famID)
					if fam then
						local rank = tonumber(rankChar, 16) or 1
						local tal = tonumber(talChar, 16) or 0
						local weight = (fam.talent and fam.talent.weightPerRank) or 10
						vec.buffs[famID] = {
							familyID = famID,
							known = true,
							bestSingleRank = rank,
							bestSingleName = fam.name,
							bestGroupName = fam.groupName,
							hasGroup = (rank >= 1),
							talentRank = tal,
							priorityScore = (rank * 10) + 15 + (tal * weight),
							icon = fam.icon,
						}
					end
				end
			end
			Capabilities:SetPeerVector(sender, vec)

			if assign then
				for clsID = 1, 9 do
					local clsToken = Catalog.ID_TO_CLASS[clsID]
					local c = assign:sub(clsID, clsID)
					local bid = (c == "" or c == "n") and 0 or (tonumber(c) or 0)
					local famID = bid > 0 and Catalog.PALLYPOWER_ID_TO_FAMILY[bid] or nil
					if clsToken then
						Assignments:SetClassBuff(sender, clsToken, famID, famID ~= nil)
					end
				end
			end
			self:NotifyChange("PLPWR_SELF", sender)
		end
		return
	end

	-- ASELF <numbers>@<auraID>
	if msg:find("^ASELF ") then
		local numbers, assign = msg:match("^ASELF ([0-9a-fn]*)@([0-9n]*)")
		if numbers then
			local vec = Capabilities:GetPeerVector(sender)
			if vec then
				vec.auras = {}
				for aid = 1, 7 do
					local rankChar = numbers:sub((aid - 1) * 2 + 1, (aid - 1) * 2 + 1)
					local def = Catalog.PALADIN_AURAS[aid]
					if def and rankChar ~= "" and rankChar ~= "n" then
						vec.auras[aid] = {
							auraID = aid,
							id = def.id,
							name = def.name,
							icon = def.icon,
							rank = tonumber(rankChar, 16) or 1,
						}
					end
				end
			end
			local aid = (assign == "" or assign == "n") and 0 or (tonumber(assign) or 0)
			Assignments:SetPaladinAura(sender, aid, aid > 0)
			self:NotifyChange("PLPWR_ASELF", sender)
		end
		return
	end

	-- ASSIGN <pallyName> <classID> <blessingID>
	if msg:find("^ASSIGN ") then
		local pName, clsStr, skillStr = msg:match("^ASSIGN (.*) (%d+) (%d+)$")
		pName = LBB.Compat.NormalizeName(pName)
		local clsID = tonumber(clsStr)
		local bid = tonumber(skillStr)
		if pName and clsID and bid and isSenderAuthorizedForPLPWR(sender, pName) then
			local clsToken = Catalog.ID_TO_CLASS[clsID]
			local famID = bid > 0 and Catalog.PALLYPOWER_ID_TO_FAMILY[bid] or nil
			if clsToken then
				Assignments:SetClassBuff(pName, clsToken, famID, true)
				self:NotifyChange("PLPWR_ASSIGN", pName)
			end
		end
		return
	end

	-- MASSIGN <pallyName> <blessingID>
	if msg:find("^MASSIGN ") then
		local pName, skillStr = msg:match("^MASSIGN (.*) (%d+)$")
		pName = LBB.Compat.NormalizeName(pName)
		local bid = tonumber(skillStr)
		if pName and bid and isSenderAuthorizedForPLPWR(sender, pName) then
			local famID = bid > 0 and Catalog.PALLYPOWER_ID_TO_FAMILY[bid] or nil
			for clsID = 1, 9 do
				local clsToken = Catalog.ID_TO_CLASS[clsID]
				if clsToken then
					Assignments:SetClassBuff(pName, clsToken, famID, true)
				end
			end
			self:NotifyChange("PLPWR_MASSIGN", pName)
		end
		return
	end

	-- PASSIGN <pallyName>@<9-char>
	if msg:find("^PASSIGN ") then
		local pName, assign = msg:match("^PASSIGN (.*)@([0-9n]*)$")
		pName = LBB.Compat.NormalizeName(pName)
		if pName and assign and isSenderAuthorizedForPLPWR(sender, pName) then
			for clsID = 1, 9 do
				local clsToken = Catalog.ID_TO_CLASS[clsID]
				local c = assign:sub(clsID, clsID)
				local bid = (c == "" or c == "n") and 0 or (tonumber(c) or 0)
				local famID = bid > 0 and Catalog.PALLYPOWER_ID_TO_FAMILY[bid] or nil
				if clsToken then
					Assignments:SetClassBuff(pName, clsToken, famID, famID ~= nil)
				end
			end
			self:NotifyChange("PLPWR_PASSIGN", pName)
		end
		return
	end

	-- NASSIGN <wirePally> <classID> <wireTarget> <blessingID>[@...]
	if msg:find("^NASSIGN ") then
		local body = msg:sub(9)
		for wp, clsStr, wt, skillStr in body:gmatch("([^@ ]+) (%d+) ([^@ ]+) (%d+)") do
			local pName = LBB.Compat.NormalizeName(Comms.UnwirePPName(wp))
			local tName = LBB.Compat.NormalizeName(Comms.UnwirePPName(wt))
			local clsID = tonumber(clsStr)
			local bid = tonumber(skillStr)
			if pName and tName and clsID and bid and isSenderAuthorizedForPLPWR(sender, pName) then
				local clsToken = Catalog.ID_TO_CLASS[clsID]
				local famID = bid > 0 and Catalog.PALLYPOWER_ID_TO_FAMILY[bid] or nil
				Assignments:SetPaladinNormalOverride(pName, tName, clsToken, famID, true)
			end
		end
		self:NotifyChange("PLPWR_NASSIGN", sender)
		return
	end

	-- AASSIGN <pallyName> <auraID>
	if msg:find("^AASSIGN ") then
		local pName, auraStr = msg:match("^AASSIGN (.*) (%d+)$")
		pName = LBB.Compat.NormalizeName(pName)
		local aid = tonumber(auraStr)
		if pName and aid and isSenderAuthorizedForPLPWR(sender, pName) then
			Assignments:SetPaladinAura(pName, aid, true)
			self:NotifyChange("PLPWR_AASSIGN", pName)
		end
		return
	end

	-- CLEAR
	if msg:find("^CLEAR") then
		local rosterEntry = Assignments.rosterByName[sender]
		local isLeader = rosterEntry and (rosterEntry.isLeader or rosterEntry.isAssist)
		if isLeader or self.freeAssign[sender] or (LBB.DB and LBB.DB.freeAssign) then
			Assignments.classBuffs = {}
			Assignments.paladinNormalOverrides = {}
			Assignments.paladinAuras = {}
			self:NotifyChange("PLPWR_CLEAR", sender)
		end
		return
	end

	-- FREEASSIGN / FREE and SYMCOUNT / SYM (may appear combined on one line!)
	local handledMeta = false
	if msg:find("FREEASSIGN YES") or msg:find("^FREE YES") then
		self.freeAssign[sender] = true
		handledMeta = true
	elseif msg:find("FREEASSIGN NO") or msg:find("^FREE NO") then
		self.freeAssign[sender] = false
		handledMeta = true
	end

	local symCount = msg:match("SYMCOUNT (%d+)") or msg:match("^SYM (%d+)")
	if symCount then
		local vec = Capabilities:GetPeerVector(sender)
		if vec then
			vec.symbols = tonumber(symCount) or 0
		end
		handledMeta = true
	end

	if handledMeta then
		self:NotifyChange("PLPWR_META", sender)
	end
end

-- Unified CHAT_MSG_ADDON dispatcher
function Comms:OnAddonMessage(prefix, message, distribution, rawSender)
	if prefix ~= self.PREFIX_LBB and prefix ~= self.PREFIX_PLPWR then
		return
	end
	if distribution ~= "PARTY" and distribution ~= "RAID" and distribution ~= "INSTANCE_CHAT" and distribution ~= "WHISPER" then
		return
	end
	local sender = LBB.Compat.NormalizeName(rawSender)
	if not sender then
		return
	end
	local myName = LBB.Capabilities.playerVector and LBB.Capabilities.playerVector.name or LBB.Compat.GetFullUnitName("player")
	if sender == myName then
		return
	end

	if prefix == self.PREFIX_LBB then
		local full = self:IngestLBBFrame(sender, message)
		if full then
			self:HandleLBBMessage(sender, full, distribution)
		end
	elseif prefix == self.PREFIX_PLPWR then
		self:HandlePLPWRMessage(sender, message, distribution)
	end
end
