local Mock = require("tests.wow_mock")

describe("Capabilities (Spellbook, Talent & Tracking Discovery)", function()
	local env, LBB

	before_each(function()
		env = Mock.New()
		env:Install()
		LBB = env:LoadCore()
	end)

	it("discovers only spells known via C_SpellBook.IsSpellKnown and selects highest rank", function()
		env:SetUnit("player", { name = "Aeloria Light", class = "PRIEST", subgroup = 1 })
		-- Know Fortitude Rank 4 and Rank 6, Prayer of Fortitude Rank 2, but NOT Divine Spirit (talent-gated)
		env:SetKnownSpell(2791, "Power Word: Fortitude", 135987)
		env:SetKnownSpell(10938, "Power Word: Fortitude", 135987)
		env:SetKnownSpell(21564, "Prayer of Fortitude", 135941)
		env:SetItemCount(17029, 45) -- Sacred Candles

		local vec = LBB.Capabilities:ScanPlayer()
		assert.are.equal("Aeloria Light", vec.name)
		assert.are.equal("PRIEST", vec.class)

		-- Fortitude discovered at highest rank (Rank 6 = 10938) + Group spell (21564)
		assert.is_not_nil(vec.buffs.FORTITUDE)
		assert.is_true(vec.buffs.FORTITUDE.known)
		assert.are.equal(10938, vec.buffs.FORTITUDE.bestSingleID)
		assert.are.equal(6, vec.buffs.FORTITUDE.bestSingleRank)
		assert.is_true(vec.buffs.FORTITUDE.hasGroup)
		assert.are.equal(21564, vec.buffs.FORTITUDE.bestGroupID)

		-- Talent-gated Divine Spirit & unknown Shadow Protection excluded
		assert.is_nil(vec.buffs.SPIRIT)
		assert.is_nil(vec.buffs.SHADOW_PROT)
		assert.are.equal(45, vec.reagents[17029])
	end)

	it("computes higher priority scores from C_Traits talent ranks", function()
		env:SetUnit("player", { name = "Talented Priest", class = "PRIEST" })
		env:SetKnownSpell(10938, "Power Word: Fortitude", 135987)
		env:SetKnownSpell(21564, "Prayer of Fortitude", 135941)

		local baseVec = LBB.Capabilities:ScanPlayer()
		local baseScore = baseVec.buffs.FORTITUDE.priorityScore

		env:SetTalent("Improved Power Word: Fortitude", 2)
		local impVec = LBB.Capabilities:ScanPlayer()
		assert.are.equal(2, impVec.buffs.FORTITUDE.talentRank)
		assert.is_true(impVec.buffs.FORTITUDE.priorityScore > baseScore)
		assert.are.equal(baseScore + 50, impVec.buffs.FORTITUDE.priorityScore)
	end)

	it("handles async SPELL_DATA_LOAD_RESULT when spell info is initially uncached", function()
		env:SetUnit("player", { name = "Async Mage", class = "MAGE" })
		-- Spell is known in spellbook, but GetSpellInfo initially returns nil
		env:SetKnownSpell(10157, false)

		local vec = LBB.Capabilities:ScanPlayer()
		assert.is_not_nil(vec.buffs.INTELLECT)
		assert.is_true(env.state.requestedSpellLoads[10157])
		assert.is_true(LBB.Capabilities.pendingSpellLoads[10157])

		-- Client later caches spell data and fires SPELL_DATA_LOAD_RESULT
		env:SetSpellInfo(10157, "Arcane Intellect", 135932)
		local updated = LBB.Capabilities:OnSpellDataLoaded(10157, true)
		assert.is_true(updated)
		assert.are.equal("Arcane Intellect", vec.buffs.INTELLECT.bestSingleName)
		assert.are.equal(135932, vec.buffs.INTELLECT.icon)
		assert.is_nil(LBB.Capabilities.pendingSpellLoads[10157])
	end)

	it("discovers profession and hunter tracking modes from C_Minimap (table & multi-return)", function()
		env:SetUnit("player", { name = "Rexxar Wild", class = "HUNTER" })
		env:SetTrackingList({
			{ name = "Find Minerals", texture = 136025, active = false, spellID = 2580 },
			{ name = "Track Beasts", texture = 132328, active = true, spellID = 1494 },
			{ name = "Track Humanoids", texture = 135942, active = false, spellID = 19883 },
		}, true)

		local st1 = LBB.Capabilities:ScanTracking()
		assert.are.equal(3, #st1.list)
		assert.are.equal("PROFESSION", st1.byName["Find Minerals"].category)
		assert.are.equal("HUNTER", st1.byName["Track Beasts"].category)
		assert.are.equal("Track Beasts", st1.active.name)

		-- Also verify multi-return C_Minimap.GetTrackingInfo compatibility
		env:SetTrackingList({
			{ name = "Find Herbs", texture = 133939, active = true, spellID = 2383 },
		}, false)
		local st2 = LBB.Capabilities:ScanTracking()
		assert.are.equal(1, #st2.list)
		assert.are.equal("Find Herbs", st2.active.name)
		assert.are.equal("PROFESSION", st2.byName["Find Herbs"].category)
	end)

	it("round-trips capability vector serialization and deserialization", function()
		env:SetUnit("player", { name = "Uther Silverhand", class = "PALADIN" })
		env:SetKnownSpell(25291, "Blessing of Might", 135906)
		env:SetKnownSpell(25916, "Greater Blessing of Might", 135908)
		env:SetKnownSpell(20217, "Blessing of Kings", 135995)
		env:SetKnownSpell(465, "Devotion Aura", 135893)
		env:SetTalent("Improved Blessing of Might", 5)
		env:SetItemCount(21177, 120)

		local orig = LBB.Capabilities:ScanPlayer()
		local wire = LBB.Capabilities:SerializeVector(orig)
		local parsed = LBB.Capabilities:DeserializeVector(orig.name, wire)

		assert.is_not_nil(parsed)
		assert.are.equal("PALADIN", parsed.class)
		assert.are.equal(120, parsed.symbols)
		assert.is_true(parsed.buffs.BOM.known)
		assert.are.equal(5, parsed.buffs.BOM.talentRank)
		assert.is_true(parsed.buffs.BOM.hasGroup)
		assert.is_true(parsed.buffs.BOK.known)
		assert.is_nil(parsed.buffs.BOSANC)
		assert.is_not_nil(parsed.auras[1])
	end)
end)
