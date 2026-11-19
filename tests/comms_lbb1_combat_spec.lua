local Mock = require("tests.wow_mock")

describe("Comms LBB1 Chunking, Combat Lockdown Queuing & Secret-Value Guards", function()
	local env, LBB

	before_each(function()
		env = Mock.New()
		env:Install()
		LBB = env:LoadCore()
		LBB.Comms:Init()
	end)

	it("chunks large LBB1 payloads strictly under 255 bytes and reassembles out-of-order frames", function()
		local bigPayload = "CAP|LongName|" .. string.rep("FORTITUDE:6:2:1:125,", 35)
		assert.is_true(#bigPayload > 600)

		local frames = LBB.Comms:ChunkPayload(bigPayload, 42)
		assert.is_true(#frames >= 3)
		for _, frame in ipairs(frames) do
			assert.is_true(#frame <= 255, "Frame exceeded 255 bytes: " .. tostring(#frame))
		end

		-- Deliver frames out of order (last -> first -> middle)
		local r1 = LBB.Comms:IngestLBBFrame("SenderOne", frames[#frames])
		assert.is_nil(r1)
		local r2 = LBB.Comms:IngestLBBFrame("SenderOne", frames[1])
		assert.is_nil(r2)
		local finalPayload
		for i = 2, #frames - 1 do
			finalPayload = LBB.Comms:IngestLBBFrame("SenderOne", frames[i])
		end
		assert.are.equal(bigPayload, finalPayload)
		assert.is_nil(LBB.Comms.reassembly["SenderOne::42"])
	end)

	it("throttles LBB1 bursts and drains queued packets as time advances", function()
		env:SetGroup("RAID", { "raid1" })
		env:SetTime(100)
		LBB.Comms.tokens = 2
		LBB.Comms.lastTick = 100

		for i = 1, 5 do
			LBB.Comms:SendLBB("PING|" .. i, "RAID")
		end
		-- Only 2 burst tokens available initially; 3 remain queued
		assert.are.equal(2, #env.state.sentAddonMessages)
		assert.are.equal(3, #LBB.Comms.sendQueue)

		-- Advance 1 second (rate = 4/sec) -> remaining 3 drain cleanly
		env:AdvanceTime(1.0)
		local drained = LBB.Comms:ProcessQueue(env.state.time)
		assert.are.equal(3, drained)
		assert.are.equal(5, #env.state.sentAddonMessages)
		assert.are.equal(0, #LBB.Comms.sendQueue)
	end)

	it("queues SecureActionButtonTemplate attribute mutations during InCombatLockdown and flushes on PLAYER_REGEN_ENABLED", function()
		local btn = _G.CreateFrame("Button", "LBBTestSecureBtn", _G.UIParent, "SecureActionButtonTemplate")

		-- Out of combat: applied immediately
		env:SetCombat(false)
		assert.is_true(LBB.Compat.SetSecureAttribute(btn, "type1", "spell"))
		assert.is_true(LBB.Compat.SetSecureAttribute(btn, "unit1", "raid1"))
		assert.are.equal("raid1", btn:GetAttribute("unit1"))

		-- Enter combat: direct SetAttribute would error, but Compat.SetSecureAttribute queues safely!
		env:SetCombat(true)
		assert.has_no.errors(function()
			local immediate1 = LBB.Compat.SetSecureAttribute(btn, "unit1", "raid2")
			local immediate2 = LBB.Compat.SetSecureAttribute(btn, "unit1", "raid3") -- deduplicates same key
			local immediate3 = LBB.Compat.SetSecureAttribute(btn, "spell1", "Power Word: Fortitude")
			assert.is_false(immediate1)
			assert.is_false(immediate2)
			assert.is_false(immediate3)
		end)

		-- Attribute has NOT mutated mid-combat; 2 unique attribute keys queued
		assert.are.equal("raid1", btn:GetAttribute("unit1"))
		assert.are.equal(2, LBB.Compat.GetPendingCombatQueueCount())

		-- Flushing while still in combat is a safe no-op
		assert.are.equal(0, LBB.Compat.FlushCombatQueue())
		assert.are.equal("raid1", btn:GetAttribute("unit1"))

		-- Leave combat (PLAYER_REGEN_ENABLED): queue flushes latest values immediately
		env:SetCombat(false)
		local applied = LBB.Compat.FlushCombatQueue()
		assert.are.equal(2, applied)
		assert.are.equal("raid3", btn:GetAttribute("unit1"))
		assert.are.equal("Power Word: Fortitude", btn:GetAttribute("spell1"))
		assert.are.equal(0, LBB.Compat.GetPendingCombatQueueCount())
	end)

	it("safely guards Midnight issecretvalue() aura tables and fields in combat without throwing", function()
		-- 1. Out of combat: populate readable aura cache (Fortitude expires at t=2800)
		env:SetTime(1000)
		env:SetCombat(false)
		env:SetUnit("raid1", {
			name = "TankOne",
			class = "WARRIOR",
			subgroup = 1,
			auras = {
				{
					name = "Power Word: Fortitude",
					spellId = 10938,
					duration = 1800,
					expirationTime = 2800,
					applications = 0,
					sourceUnit = "player",
				},
			},
		})

		local preScan = LBB.Scanner:ScanUnit("raid1", { guid = "GUID-TankOne" })
		assert.is_false(preScan.restricted)
		assert.is_not_nil(preScan.families.FORTITUDE)
		assert.are.equal(1800, LBB.Scanner:GetRemainingSeconds(preScan.families.FORTITUDE, 1000))

		-- 2. Enter combat: Case A - entire aura table becomes secret
		env:SetCombat(true)
		env:SetTime(1100)
		env.state.units["raid1"].auraBlocked = true

		local combatScanA
		assert.has_no.errors(function()
			combatScanA = LBB.Scanner:ScanUnit("raid1", { guid = "GUID-TankOne" })
		end)
		assert.is_true(combatScanA.restricted)
		-- Extrapolated from pre-combat cache (2800 - 1100 = 1700s left, no false missing alarm!)
		assert.is_not_nil(combatScanA.families.FORTITUDE)
		assert.are.equal(1700, LBB.Scanner:GetRemainingSeconds(combatScanA.families.FORTITUDE, 1100))

		-- 3. Case B - table is readable, but name & expirationTime are individual secret values
		env.state.units["raid1"].auraBlocked = false
		env.state.units["raid1"].auras = {
			{
				name = Mock.MakeSecret("aura_name"),
				spellId = Mock.MakeSecret("aura_spellId"),
				duration = Mock.MakeSecret("aura_dur"),
				expirationTime = Mock.MakeSecret("aura_exp"),
				applications = Mock.MakeSecret("aura_apps"),
			},
		}

		local combatScanB
		assert.has_no.errors(function()
			combatScanB = LBB.Scanner:ScanUnit("raid1", { guid = "GUID-TankOne" })
		end)
		assert.is_true(combatScanB.restricted)
		assert.is_not_nil(combatScanB.families.FORTITUDE)
	end)
end)
