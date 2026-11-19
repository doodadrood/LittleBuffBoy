local Mock = require("tests.wow_mock")

describe("Comms (PLPWR Round-Trip Interop & PallyPower Yield)", function()
	local env, LBB

	before_each(function()
		env = Mock.New()
		env:Install()
		LBB = env:LoadCore()
		LBB.Comms:Init()
	end)

	it("registers both LBB1 and PLPWR addon prefixes", function()
		assert.is_true(env.state.registeredPrefixes["LBB1"])
		assert.is_true(env.state.registeredPrefixes["PLPWR"])
	end)

	it("round-trips PLPWR SELF, ASELF, ASSIGN, MASSIGN, NASSIGN, SYMCOUNT, FREEASSIGN, REQ, and CLEAR", function()
		env:SetUnit("player", { name = "Pallyblaze Forever", class = "PALADIN", subgroup = 1 })
		env:SetUnit("raid1",  { name = "Pallyblaze Forever", class = "PALADIN", subgroup = 1 })
		env:SetUnit("raid2",  { name = "Arthas Menethil",    class = "PALADIN", subgroup = 1, isLeader = true })
		env:SetUnit("raid3",  { name = "Grom Hellscream",    class = "WARRIOR", subgroup = 1 })
		env:SetGroup("RAID", { "raid1", "raid2", "raid3" })

		env:SetKnownSpell(25290, "Blessing of Wisdom", 135970) -- rank 6
		env:SetKnownSpell(25291, "Blessing of Might", 135906)  -- rank 7
		env:SetKnownSpell(20217, "Blessing of Kings", 135995)  -- rank 1
		env:SetKnownSpell(465, "Devotion Aura", 135893)
		env:SetTalent("Improved Blessing of Might", 5)
		env:SetItemCount(21177, 88)

		LBB.Assignments:RefreshRosterFromGame()
		LBB.Capabilities:ScanPlayer()
		LBB.Assignments:SetClassBuff("Pallyblaze Forever", "WARRIOR", "BOM", true)
		LBB.Assignments:SetClassBuff("Pallyblaze Forever", "MAGE", "BOW", true)
		LBB.Assignments:SetPaladinAura("Pallyblaze Forever", 1, true)

		-- 1. Outbound SELF matches PallyPower wire format
		local selfPacket = LBB.Comms:BuildPLPWRSelf()
		-- Blessings 1..6: Wisdom(6,0)=60, Might(7,5)=75, Kings(1,1)=11, Salv=nn, Light=nn, Sanc=nn
		-- Classes 1..9: WAR=2(Might), ROG=n, PRI=n, DRU=n, PAL=n, HUN=n, MAG=1(Wisdom), WLK=n, SHA=n
		assert.are.equal("SELF 607511nnnnnn@2nnnnn1nn", selfPacket)

		-- 2. Inbound REQ triggers SELF, ASELF, and FREEASSIGN/SYMCOUNT whisper back
		env.state.sentAddonMessages = {}
		LBB.Comms:OnAddonMessage("PLPWR", "REQ", "RAID", "Arthas Menethil-ForeverRealm")
		assert.are.equal(3, #env.state.sentAddonMessages)
		assert.are.equal("PLPWR", env.state.sentAddonMessages[1].prefix)
		assert.are.equal("SELF 607511nnnnnn@2nnnnn1nn", env.state.sentAddonMessages[1].msg)
		assert.are.equal("WHISPER", env.state.sentAddonMessages[1].chatType)
		assert.are.equal("Arthas Menethil", env.state.sentAddonMessages[1].target)
		assert.is_truthy(env.state.sentAddonMessages[2].msg:find("^ASELF "))
		assert.is_truthy(env.state.sentAddonMessages[3].msg:find("SYMCOUNT 88"))

		-- 3. Inbound SELF from a PallyPower peer populates peer capabilities + assignments
		LBB.Comms:OnAddonMessage("PLPWR", "SELF 62701010nnnn@331333113", "RAID", "Arthas Menethil-ForeverRealm")
		local peer = LBB.Capabilities:GetPeerVector("Arthas Menethil")
		assert.is_not_nil(peer)
		assert.are.equal("PALADIN", peer.class)
		assert.are.equal(2, peer.buffs.BOW.talentRank)
		assert.are.equal("BOK", LBB.Assignments:GetClassBuff("Arthas Menethil", "WARRIOR").familyID)
		assert.are.equal("BOW", LBB.Assignments:GetClassBuff("Arthas Menethil", "PRIEST").familyID)

		-- 4. Inbound ASSIGN from raid leader updates our assignment (Forever name with space!)
		LBB.Comms:OnAddonMessage("PLPWR", "ASSIGN Pallyblaze Forever 1 3", "RAID", "Arthas Menethil-ForeverRealm")
		assert.are.equal("BOK", LBB.Assignments:GetClassBuff("Pallyblaze Forever", "WARRIOR").familyID)

		-- 5. Inbound MASSIGN sets all 9 classes
		LBB.Comms:OnAddonMessage("PLPWR", "MASSIGN Pallyblaze Forever 4", "RAID", "Arthas Menethil-ForeverRealm")
		assert.are.equal("BOSALV", LBB.Assignments:GetClassBuff("Pallyblaze Forever", "ROGUE").familyID)
		assert.are.equal("BOSALV", LBB.Assignments:GetClassBuff("Pallyblaze Forever", "SHAMAN").familyID)

		-- 6. Inbound NASSIGN handles Forever "_" space-escaped names
		LBB.Comms:OnAddonMessage("PLPWR", "NASSIGN Pallyblaze_Forever 1 Grom_Hellscream 2", "RAID", "Arthas Menethil-ForeverRealm")
		local norm = LBB.Assignments.paladinNormalOverrides["Pallyblaze Forever"]["Grom Hellscream"]
		assert.is_not_nil(norm)
		assert.are.equal("BOM", norm.familyID)

		-- 7. Inbound FREEASSIGN + SYMCOUNT metadata
		LBB.Comms:OnAddonMessage("PLPWR", "FREEASSIGN YES | SYMCOUNT 42 | COOLDOWNS:n:n:n:n", "RAID", "Arthas Menethil-ForeverRealm")
		assert.is_true(LBB.Comms.freeAssign["Arthas Menethil"])
		assert.are.equal(42, LBB.Capabilities:GetPeerVector("Arthas Menethil").symbols)

		-- 8. Inbound CLEAR from raid leader wipes Paladin assignments
		LBB.Comms:OnAddonMessage("PLPWR", "CLEAR", "RAID", "Arthas Menethil-ForeverRealm")
		assert.is_nil(LBB.Assignments:GetClassBuff("Pallyblaze Forever", "WARRIOR"))
	end)

	it("automatically yields PLPWR broadcasting and Paladin control when PallyPower is loaded while keeping LBB1 active", function()
		env:SetAddonLoaded("PallyPower", true)
		env:SetUnit("player", { name = "Hybrid Pally", class = "PALADIN", subgroup = 1 })
		env:SetUnit("raid1",  { name = "Hybrid Pally", class = "PALADIN", subgroup = 1 })
		env:SetUnit("raid2",  { name = "Raid Priest",  class = "PRIEST",  subgroup = 1 })
		env:SetGroup("RAID", { "raid1", "raid2" })

		env:SetKnownSpell(20217, "Blessing of Kings", 135995)
		LBB.Assignments:RefreshRosterFromGame()
		LBB.Capabilities:ScanPlayer()

		assert.is_true(LBB.Comms:IsPallyPowerLoaded())

		-- Outbound PLPWR calls MUST yield cleanly
		local okSelf, reasonSelf = LBB.Comms:SendPLPWRSelf()
		assert.is_false(okSelf)
		assert.are.equal("yielded", reasonSelf)

		local okAssign, reasonAssign = LBB.Comms:SendPLPWRAssign("Hybrid Pally", 1, 3)
		assert.is_false(okAssign)
		assert.are.equal("yielded", reasonAssign)

		-- Inbound PLPWR REQ must NOT send any PLPWR response when yielded
		env.state.sentAddonMessages = {}
		LBB.Comms:OnAddonMessage("PLPWR", "REQ", "RAID", "OtherPally-ForeverRealm")
		assert.are.equal(0, #env.state.sentAddonMessages)

		-- LBB1 comms MUST continue working normally for non-blessing coordination!
		local okCap = LBB.Comms:BroadcastCapabilities("RAID")
		assert.is_true(okCap)
		assert.are.equal(1, #env.state.sentAddonMessages)
		assert.are.equal("LBB1", env.state.sentAddonMessages[1].prefix)

		-- LBB1 group buff lock succeeds, while LBB1 Paladin CLASS lock is yielded/ignored
		LBB.Comms:HandleLBBMessage("Raid Priest", "LOCK|GROUP|1|FORTITUDE|Raid Priest|1", "RAID")
		assert.are.equal("Raid Priest", LBB.Assignments:GetGroupBuff("FORTITUDE", 1).caster)

		LBB.Comms:HandleLBBMessage("Raid Priest", "LOCK|CLASS|WARRIOR|BOK|Hybrid Pally|1", "RAID")
		assert.is_nil(LBB.Assignments:GetClassBuff("Hybrid Pally", "WARRIOR"))
	end)
end)
