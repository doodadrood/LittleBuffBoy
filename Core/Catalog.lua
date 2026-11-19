local addonName, LBB = ...
LBB = LBB or _G.LittleBuffBoy or {}
_G.LittleBuffBoy = LBB

local Catalog = {}
LBB.Catalog = Catalog

-- WoW: Forever class order (matches PallyPower Forever 1..9 indices)
Catalog.CLASS_ORDER = {
	"WARRIOR",
	"ROGUE",
	"PRIEST",
	"DRUID",
	"PALADIN",
	"HUNTER",
	"MAGE",
	"WARLOCK",
	"SHAMAN",
}

Catalog.CLASS_TO_ID = {}
Catalog.ID_TO_CLASS = {}
for idx, token in ipairs(Catalog.CLASS_ORDER) do
	Catalog.CLASS_TO_ID[token] = idx
	Catalog.ID_TO_CLASS[idx] = token
end

Catalog.CLASS_INFO = {
	WARRIOR = { name = "Warrior", short = "WAR", usesMana = false, isMelee = true, isCaster = false, isTank = true, color = { 0.78, 0.61, 0.43 } },
	ROGUE   = { name = "Rogue",   short = "ROG", usesMana = false, isMelee = true, isCaster = false, isTank = false, color = { 1.00, 0.96, 0.41 } },
	PRIEST  = { name = "Priest",  short = "PRI", usesMana = true,  isMelee = false, isCaster = true, isTank = false, color = { 1.00, 1.00, 1.00 } },
	DRUID   = { name = "Druid",   short = "DRU", usesMana = true,  isMelee = true, isCaster = true, isTank = true, color = { 1.00, 0.49, 0.04 } },
	PALADIN = { name = "Paladin", short = "PAL", usesMana = true,  isMelee = true, isCaster = true, isTank = true, color = { 0.96, 0.55, 0.73 } },
	HUNTER  = { name = "Hunter",  short = "HUN", usesMana = true,  isMelee = true, isCaster = false, isTank = false, color = { 0.67, 0.83, 0.45 } },
	MAGE    = { name = "Mage",    short = "MAG", usesMana = true,  isMelee = false, isCaster = true, isTank = false, color = { 0.25, 0.78, 0.92 } },
	WARLOCK = { name = "Warlock", short = "WLK", usesMana = true,  isMelee = false, isCaster = true, isTank = false, color = { 0.53, 0.53, 0.93 } },
	SHAMAN  = { name = "Shaman",  short = "SHA", usesMana = true,  isMelee = true, isCaster = true, isTank = false, color = { 0.00, 0.44, 0.87 } },
}

-- Complete all-class raid & party buff definitions
-- Ranks are ordered highest -> lowest so spell discovery finds the best known rank first.
Catalog.BUFF_FAMILIES = {
	-- PRIEST
	FORTITUDE = {
		id = "FORTITUDE",
		class = "PRIEST",
		name = "Power Word: Fortitude",
		groupName = "Prayer of Fortitude",
		shortName = "Fort",
		icon = 135987, -- Spell_Holy_WordFortitude
		scope = "GROUP",
		targetFilter = "ALL",
		defaultDuration = 1800,
		groupDuration = 3600,
		groupThreshold = 2,
		reagentItemID = 17029, -- Sacred Candle
		reagentLowThreshold = 20,
		singleRanks = {
			{ rank = 6, spellID = 10938, minLevel = 60 },
			{ rank = 5, spellID = 10937, minLevel = 48 },
			{ rank = 4, spellID = 2791,  minLevel = 36 },
			{ rank = 3, spellID = 1245,  minLevel = 24 },
			{ rank = 2, spellID = 1244,  minLevel = 12 },
			{ rank = 1, spellID = 1243,  minLevel = 1 },
		},
		groupRanks = {
			{ rank = 2, spellID = 21564, minLevel = 60 },
			{ rank = 1, spellID = 21562, minLevel = 48 },
		},
		auraNames = { "Power Word: Fortitude", "Prayer of Fortitude" },
		talent = {
			name = "Improved Power Word: Fortitude",
			maxRank = 2,
			weightPerRank = 25,
		},
	},
	SPIRIT = {
		id = "SPIRIT",
		class = "PRIEST",
		name = "Divine Spirit",
		groupName = "Prayer of Spirit",
		shortName = "Spirit",
		icon = 135898, -- Spell_Holy_DivineSpirit
		scope = "GROUP",
		targetFilter = "MANA",
		talentGated = true,
		defaultDuration = 1800,
		groupDuration = 3600,
		groupThreshold = 2,
		reagentItemID = 17029, -- Sacred Candle
		reagentLowThreshold = 20,
		singleRanks = {
			{ rank = 4, spellID = 27841, minLevel = 60 },
			{ rank = 3, spellID = 14819, minLevel = 50 },
			{ rank = 2, spellID = 14818, minLevel = 40 },
			{ rank = 1, spellID = 14752, minLevel = 30 },
		},
		groupRanks = {
			{ rank = 1, spellID = 27681, minLevel = 60 },
		},
		auraNames = { "Divine Spirit", "Prayer of Spirit" },
		talent = {
			name = "Divine Spirit",
			maxRank = 1,
			weightPerRank = 15,
		},
	},
	SHADOW_PROT = {
		id = "SHADOW_PROT",
		class = "PRIEST",
		name = "Shadow Protection",
		groupName = "Prayer of Shadow Protection",
		shortName = "SProt",
		icon = 136121, -- Spell_Shadow_AntiShadow
		scope = "GROUP",
		targetFilter = "ALL",
		defaultDuration = 600,
		groupDuration = 1200,
		groupThreshold = 2,
		reagentItemID = 17029,
		reagentLowThreshold = 20,
		singleRanks = {
			{ rank = 3, spellID = 10958, minLevel = 56 },
			{ rank = 2, spellID = 10957, minLevel = 42 },
			{ rank = 1, spellID = 976,   minLevel = 30 },
		},
		groupRanks = {
			{ rank = 1, spellID = 27683, minLevel = 56 },
		},
		auraNames = { "Shadow Protection", "Prayer of Shadow Protection" },
	},

	-- MAGE
	INTELLECT = {
		id = "INTELLECT",
		class = "MAGE",
		name = "Arcane Intellect",
		groupName = "Arcane Brilliance",
		shortName = "AI",
		icon = 135932, -- Spell_Holy_MagicalSentry
		scope = "GROUP",
		targetFilter = "MANA",
		defaultDuration = 1800,
		groupDuration = 3600,
		groupThreshold = 2,
		reagentItemID = 17020, -- Arcane Powder
		reagentLowThreshold = 20,
		singleRanks = {
			{ rank = 5, spellID = 10157, minLevel = 56 },
			{ rank = 4, spellID = 10156, minLevel = 42 },
			{ rank = 3, spellID = 10155, minLevel = 28 },
			{ rank = 2, spellID = 1460,  minLevel = 14 },
			{ rank = 1, spellID = 1459,  minLevel = 1 },
		},
		groupRanks = {
			{ rank = 1, spellID = 23028, minLevel = 56 },
		},
		auraNames = { "Arcane Intellect", "Arcane Brilliance" },
	},
	DAMPEN_MAGIC = {
		id = "DAMPEN_MAGIC",
		class = "MAGE",
		name = "Dampen Magic",
		shortName = "Dampen",
		icon = 136006, -- Spell_Nature_AbolishMagic
		scope = "TARGET",
		targetFilter = "SINGLE_KEY",
		optional = true,
		defaultDuration = 600,
		singleRanks = {
			{ rank = 5, spellID = 10174, minLevel = 60 },
			{ rank = 4, spellID = 10173, minLevel = 48 },
			{ rank = 3, spellID = 8451,  minLevel = 36 },
			{ rank = 2, spellID = 8450,  minLevel = 24 },
			{ rank = 1, spellID = 604,   minLevel = 12 },
		},
		auraNames = { "Dampen Magic" },
	},
	AMPLIFY_MAGIC = {
		id = "AMPLIFY_MAGIC",
		class = "MAGE",
		name = "Amplify Magic",
		shortName = "Amp",
		icon = 135907, -- Spell_Holy_FlashHeal
		scope = "TARGET",
		targetFilter = "SINGLE_KEY",
		optional = true,
		defaultDuration = 600,
		singleRanks = {
			{ rank = 4, spellID = 10170, minLevel = 54 },
			{ rank = 3, spellID = 10169, minLevel = 42 },
			{ rank = 2, spellID = 8455,  minLevel = 30 },
			{ rank = 1, spellID = 1008,  minLevel = 18 },
		},
		auraNames = { "Amplify Magic" },
	},

	-- DRUID
	MOTW = {
		id = "MOTW",
		class = "DRUID",
		name = "Mark of the Wild",
		groupName = "Gift of the Wild",
		shortName = "MotW",
		icon = 136078, -- Spell_Nature_Regeneration
		scope = "GROUP",
		targetFilter = "ALL",
		defaultDuration = 1800,
		groupDuration = 3600,
		groupThreshold = 2,
		reagentItemID = 17026, -- Wild Thornroot
		reagentLowThreshold = 20,
		singleRanks = {
			{ rank = 7, spellID = 9885, minLevel = 60 },
			{ rank = 6, spellID = 9884, minLevel = 50 },
			{ rank = 5, spellID = 8907, minLevel = 40 },
			{ rank = 4, spellID = 5234, minLevel = 30 },
			{ rank = 3, spellID = 5232, minLevel = 20 },
			{ rank = 2, spellID = 6756, minLevel = 10 },
			{ rank = 1, spellID = 1126, minLevel = 1 },
		},
		groupRanks = {
			{ rank = 2, spellID = 21850, minLevel = 60 },
			{ rank = 1, spellID = 21849, minLevel = 50 },
		},
		auraNames = { "Mark of the Wild", "Gift of the Wild" },
		talent = {
			name = "Improved Mark of the Wild",
			maxRank = 5,
			weightPerRank = 10,
		},
	},
	THORNS = {
		id = "THORNS",
		class = "DRUID",
		name = "Thorns",
		shortName = "Thorns",
		icon = 136104, -- Spell_Nature_Thorns
		scope = "TARGET",
		targetFilter = "TANK_MELEE",
		defaultDuration = 600,
		singleRanks = {
			{ rank = 6, spellID = 9910, minLevel = 54 },
			{ rank = 5, spellID = 9756, minLevel = 44 },
			{ rank = 4, spellID = 8914, minLevel = 34 },
			{ rank = 3, spellID = 1075, minLevel = 24 },
			{ rank = 2, spellID = 782,  minLevel = 14 },
			{ rank = 1, spellID = 467,  minLevel = 6 },
		},
		auraNames = { "Thorns" },
	},

	-- PALADIN BLESSINGS (pallyPowerID matches PallyPower Forever 1..6)
	BOW = {
		id = "BOW",
		class = "PALADIN",
		isBlessing = true,
		pallyPowerID = 1,
		name = "Blessing of Wisdom",
		groupName = "Greater Blessing of Wisdom",
		shortName = "BoW",
		icon = 135970,
		scope = "CLASS",
		targetFilter = "MANA",
		defaultDuration = 3600,
		groupDuration = 3600,
		groupThreshold = 2,
		reagentItemID = 21177, -- Symbol of Kings
		reagentLowThreshold = 20,
		singleRanks = {
			{ rank = 6, spellID = 25290, minLevel = 60 },
			{ rank = 5, spellID = 19854, minLevel = 54 },
			{ rank = 4, spellID = 19853, minLevel = 44 },
			{ rank = 3, spellID = 19852, minLevel = 34 },
			{ rank = 2, spellID = 19850, minLevel = 24 },
			{ rank = 1, spellID = 19742, minLevel = 14 },
		},
		groupRanks = {
			{ rank = 2, spellID = 25918, minLevel = 60 },
			{ rank = 1, spellID = 25894, minLevel = 54 },
		},
		auraNames = { "Blessing of Wisdom", "Greater Blessing of Wisdom" },
		talent = {
			name = "Improved Blessing of Wisdom",
			maxRank = 2,
			weightPerRank = 25,
		},
	},
	BOM = {
		id = "BOM",
		class = "PALADIN",
		isBlessing = true,
		pallyPowerID = 2,
		name = "Blessing of Might",
		groupName = "Greater Blessing of Might",
		shortName = "BoM",
		icon = 135906,
		scope = "CLASS",
		targetFilter = "ALL",
		defaultDuration = 3600,
		groupDuration = 3600,
		groupThreshold = 2,
		reagentItemID = 21177,
		reagentLowThreshold = 20,
		singleRanks = {
			{ rank = 7, spellID = 25291, minLevel = 60 },
			{ rank = 6, spellID = 19838, minLevel = 52 },
			{ rank = 5, spellID = 19837, minLevel = 42 },
			{ rank = 4, spellID = 19836, minLevel = 32 },
			{ rank = 3, spellID = 19835, minLevel = 22 },
			{ rank = 2, spellID = 19834, minLevel = 12 },
			{ rank = 1, spellID = 19740, minLevel = 4 },
		},
		groupRanks = {
			{ rank = 2, spellID = 25916, minLevel = 60 },
			{ rank = 1, spellID = 25782, minLevel = 52 },
		},
		auraNames = { "Blessing of Might", "Greater Blessing of Might" },
		talent = {
			name = "Improved Blessing of Might",
			maxRank = 5,
			weightPerRank = 10,
		},
	},
	BOK = {
		id = "BOK",
		class = "PALADIN",
		isBlessing = true,
		pallyPowerID = 3,
		talentGated = true,
		name = "Blessing of Kings",
		groupName = "Greater Blessing of Kings",
		shortName = "BoK",
		icon = 135995,
		scope = "CLASS",
		targetFilter = "ALL",
		defaultDuration = 3600,
		groupDuration = 3600,
		groupThreshold = 2,
		reagentItemID = 21177,
		reagentLowThreshold = 20,
		singleRanks = {
			{ rank = 1, spellID = 20217, minLevel = 20 },
		},
		groupRanks = {
			{ rank = 1, spellID = 25898, minLevel = 60 },
		},
		auraNames = { "Blessing of Kings", "Greater Blessing of Kings" },
		talent = {
			name = "Blessing of Kings",
			maxRank = 1,
			weightPerRank = 30,
		},
	},
	BOSALV = {
		id = "BOSALV",
		class = "PALADIN",
		isBlessing = true,
		pallyPowerID = 4,
		name = "Blessing of Salvation",
		groupName = "Greater Blessing of Salvation",
		shortName = "Salv",
		icon = 135967,
		scope = "CLASS",
		targetFilter = "ALL",
		defaultDuration = 3600,
		groupDuration = 3600,
		groupThreshold = 2,
		reagentItemID = 21177,
		reagentLowThreshold = 20,
		singleRanks = {
			{ rank = 1, spellID = 1038, minLevel = 26 },
		},
		groupRanks = {
			{ rank = 1, spellID = 25895, minLevel = 60 },
		},
		auraNames = { "Blessing of Salvation", "Greater Blessing of Salvation" },
	},
	BOL = {
		id = "BOL",
		class = "PALADIN",
		isBlessing = true,
		pallyPowerID = 5,
		name = "Blessing of Light",
		groupName = "Greater Blessing of Light",
		shortName = "Light",
		icon = 135943,
		scope = "CLASS",
		targetFilter = "ALL",
		defaultDuration = 3600,
		groupDuration = 3600,
		groupThreshold = 2,
		reagentItemID = 21177,
		reagentLowThreshold = 20,
		singleRanks = {
			{ rank = 3, spellID = 19979, minLevel = 60 },
			{ rank = 2, spellID = 19978, minLevel = 50 },
			{ rank = 1, spellID = 19977, minLevel = 40 },
		},
		groupRanks = {
			{ rank = 1, spellID = 25890, minLevel = 60 },
		},
		auraNames = { "Blessing of Light", "Greater Blessing of Light" },
	},
	BOSANC = {
		id = "BOSANC",
		class = "PALADIN",
		isBlessing = true,
		pallyPowerID = 6,
		talentGated = true,
		name = "Blessing of Sanctuary",
		groupName = "Greater Blessing of Sanctuary",
		shortName = "Sanc",
		icon = 136051,
		scope = "CLASS",
		targetFilter = "ALL",
		defaultDuration = 3600,
		groupDuration = 3600,
		groupThreshold = 2,
		reagentItemID = 21177,
		reagentLowThreshold = 20,
		singleRanks = {
			{ rank = 4, spellID = 20914, minLevel = 60 },
			{ rank = 3, spellID = 20913, minLevel = 50 },
			{ rank = 2, spellID = 20912, minLevel = 40 },
			{ rank = 1, spellID = 20911, minLevel = 30 },
		},
		groupRanks = {
			{ rank = 1, spellID = 25899, minLevel = 60 },
		},
		auraNames = { "Blessing of Sanctuary", "Greater Blessing of Sanctuary" },
		talent = {
			name = "Blessing of Sanctuary",
			maxRank = 1,
			weightPerRank = 25,
		},
	},

	-- WARLOCK
	SOULSTONE = {
		id = "SOULSTONE",
		class = "WARLOCK",
		name = "Soulstone Resurrection",
		shortName = "SS",
		icon = 136210, -- Spell_Shadow_SoulGem
		scope = "TARGET",
		targetFilter = "HEALER_TANK",
		defaultDuration = 1800,
		reagentItemID = 6265, -- Soul Shard
		reagentLowThreshold = 5,
		singleRanks = {
			{ rank = 5, spellID = 20763, minLevel = 58 },
			{ rank = 4, spellID = 20762, minLevel = 48 },
			{ rank = 3, spellID = 20761, minLevel = 38 },
			{ rank = 2, spellID = 20760, minLevel = 28 },
			{ rank = 1, spellID = 20707, minLevel = 18 },
		},
		auraNames = { "Soulstone Resurrection" },
	},
	BLOOD_PACT = {
		id = "BLOOD_PACT",
		class = "WARLOCK",
		name = "Blood Pact",
		shortName = "Imp",
		icon = 136121,
		scope = "PARTY",
		targetFilter = "PARTY",
		defaultDuration = 3600,
		singleRanks = {
			{ rank = 5, spellID = 11767, minLevel = 50 },
			{ rank = 4, spellID = 11766, minLevel = 38 },
			{ rank = 3, spellID = 7805,  minLevel = 26 },
			{ rank = 2, spellID = 7804,  minLevel = 14 },
			{ rank = 1, spellID = 6307,  minLevel = 4 },
			{ rank = 1, spellID = 688,   minLevel = 1 }, -- Summon Imp fallback
		},
		auraNames = { "Blood Pact" },
	},
	DETECT_INVIS = {
		id = "DETECT_INVIS",
		class = "WARLOCK",
		name = "Detect Invisibility",
		shortName = "Invis",
		icon = 136153,
		scope = "TARGET",
		targetFilter = "SINGLE_KEY",
		optional = true,
		defaultDuration = 600,
		singleRanks = {
			{ rank = 3, spellID = 11743, minLevel = 50 },
			{ rank = 2, spellID = 2970,  minLevel = 38 },
			{ rank = 1, spellID = 132,   minLevel = 26 },
		},
		auraNames = { "Detect Greater Invisibility", "Detect Invisibility", "Detect Lesser Invisibility" },
	},
	UNENDING_BREATH = {
		id = "UNENDING_BREATH",
		class = "WARLOCK",
		name = "Unending Breath",
		shortName = "Breath",
		icon = 136148,
		scope = "TARGET",
		targetFilter = "SINGLE_KEY",
		optional = true,
		defaultDuration = 600,
		singleRanks = {
			{ rank = 1, spellID = 5697, minLevel = 16 },
		},
		auraNames = { "Unending Breath" },
	},

	-- WARRIOR
	BATTLE_SHOUT = {
		id = "BATTLE_SHOUT",
		class = "WARRIOR",
		name = "Battle Shout",
		shortName = "Shout",
		icon = 132333, -- Ability_Warrior_BattleShout
		scope = "PARTY",
		targetFilter = "PARTY",
		defaultDuration = 120,
		singleRanks = {
			{ rank = 7, spellID = 25289, minLevel = 60 },
			{ rank = 6, spellID = 11551, minLevel = 52 },
			{ rank = 5, spellID = 11550, minLevel = 42 },
			{ rank = 4, spellID = 11549, minLevel = 32 },
			{ rank = 3, spellID = 6192,  minLevel = 22 },
			{ rank = 2, spellID = 5242,  minLevel = 12 },
			{ rank = 1, spellID = 6673,  minLevel = 1 },
		},
		auraNames = { "Battle Shout" },
		talent = {
			name = "Improved Battle Shout",
			maxRank = 5,
			weightPerRank = 10,
		},
	},
}

-- Ordered lookup tables
Catalog.CLASS_BUFFS = {}
Catalog.PALLYPOWER_ID_TO_FAMILY = {}
Catalog.FAMILY_TO_PALLYPOWER_ID = {}
Catalog.SPELL_ID_TO_FAMILY = {}
Catalog.AURA_NAME_TO_FAMILY = {}

local function registerBuffFamily(family)
	Catalog.CLASS_BUFFS[family.class] = Catalog.CLASS_BUFFS[family.class] or {}
	table.insert(Catalog.CLASS_BUFFS[family.class], family.id)
	if family.pallyPowerID then
		Catalog.PALLYPOWER_ID_TO_FAMILY[family.pallyPowerID] = family.id
		Catalog.FAMILY_TO_PALLYPOWER_ID[family.id] = family.pallyPowerID
	end
	family.allSpellIDs = {}
	for _, r in ipairs(family.singleRanks or {}) do
		family.allSpellIDs[r.spellID] = true
		Catalog.SPELL_ID_TO_FAMILY[r.spellID] = family.id
	end
	for _, r in ipairs(family.groupRanks or {}) do
		family.allSpellIDs[r.spellID] = true
		Catalog.SPELL_ID_TO_FAMILY[r.spellID] = family.id
	end
	for _, auraName in ipairs(family.auraNames or {}) do
		Catalog.AURA_NAME_TO_FAMILY[auraName] = family.id
	end
end

-- Deterministic registration order per class
Catalog.FAMILY_ORDER = {
	"FORTITUDE", "SPIRIT", "SHADOW_PROT",
	"INTELLECT", "DAMPEN_MAGIC", "AMPLIFY_MAGIC",
	"MOTW", "THORNS",
	"BOW", "BOM", "BOK", "BOSALV", "BOL", "BOSANC",
	"SOULSTONE", "BLOOD_PACT", "DETECT_INVIS", "UNENDING_BREATH",
	"BATTLE_SHOUT",
}

for _, famID in ipairs(Catalog.FAMILY_ORDER) do
	registerBuffFamily(Catalog.BUFF_FAMILIES[famID])
end

-- Paladin Auras (matching PallyPower 1..7)
Catalog.PALADIN_AURAS = {
	[1] = { id = "DEVOTION_AURA",    pallyPowerID = 1, name = "Devotion Aura",          shortName = "Devo",  icon = 135893, ranks = { 10293, 10292, 1032, 10291, 643, 10290, 465 } },
	[2] = { id = "RETRIBUTION_AURA", pallyPowerID = 2, name = "Retribution Aura",       shortName = "Ret",   icon = 135873, ranks = { 10301, 10300, 10299, 10298, 7294 } },
	[3] = { id = "CONCENTRATION",    pallyPowerID = 3, name = "Concentration Aura",     shortName = "Conc",  icon = 135933, ranks = { 19746 } },
	[4] = { id = "SHADOW_RES_AURA",  pallyPowerID = 4, name = "Shadow Resistance Aura", shortName = "ShRes", icon = 136192, ranks = { 19896, 19895, 19876 } },
	[5] = { id = "FROST_RES_AURA",   pallyPowerID = 5, name = "Frost Resistance Aura",  shortName = "FrRes", icon = 135865, ranks = { 19898, 19897, 19888 } },
	[6] = { id = "FIRE_RES_AURA",    pallyPowerID = 6, name = "Fire Resistance Aura",   shortName = "FiRes", icon = 135824, ranks = { 19900, 19899, 19891 } },
	[7] = { id = "SANCTITY_AURA",    pallyPowerID = 7, name = "Sanctity Aura",          shortName = "SancA", icon = 135934, ranks = { 20218 }, talentGated = true },
}

-- Paladin Personal Self-Buffs: Righteous Fury & Seals (including WoW: Forever Seal of Fury)
Catalog.RIGHTEOUS_FURY = {
	id = "RIGHTEOUS_FURY",
	spellID = 25780,
	ranks = { 25780 },
	name = "Righteous Fury",
	shortName = "RF",
	icon = 135962, -- Spell_Holy_SealOfFury
	defaultDuration = 1800,
}

Catalog.PALADIN_SEALS = {
	{ id = "SEAL_OF_RIGHTEOUSNESS", name = "Seal of Righteousness", shortName = "SoR",  icon = 132325, duration = 30, ranks = { 21084, 20293, 20292, 20291, 20290, 20289, 20288, 20287, 20154 } },
	{ id = "SEAL_OF_COMMAND",       name = "Seal of Command",       shortName = "SoC",  icon = 132347, duration = 30, ranks = { 20920, 20919, 20918, 20915, 20375 }, talentGated = true },
	{ id = "SEAL_OF_THE_CRUSADER",  name = "Seal of the Crusader",  shortName = "SotC", icon = 135924, duration = 30, ranks = { 20308, 20307, 20306, 20305, 20162, 21082 } },
	{ id = "SEAL_OF_JUSTICE",       name = "Seal of Justice",       shortName = "SoJ",  icon = 135971, duration = 30, ranks = { 20164 } },
	{ id = "SEAL_OF_LIGHT",         name = "Seal of Light",         shortName = "SoL",  icon = 135917, duration = 30, ranks = { 20349, 20348, 20347, 20165 } },
	{ id = "SEAL_OF_WISDOM",        name = "Seal of Wisdom",        shortName = "SoW",  icon = 135960, duration = 30, ranks = { 20357, 20356, 20166 } },
	{ id = "SEAL_OF_FURY",          name = "Seal of Fury",          shortName = "SoF",  icon = 135962, duration = 30, ranks = { 1311656 }, isTankSeal = true },
}

Catalog.SEAL_BY_ID = {}
Catalog.SEAL_BY_NAME = {}
Catalog.SEAL_SPELL_ID_TO_ID = {}
for _, sealDef in ipairs(Catalog.PALADIN_SEALS) do
	Catalog.SEAL_BY_ID[sealDef.id] = sealDef
	Catalog.SEAL_BY_NAME[sealDef.name] = sealDef
	for _, sid in ipairs(sealDef.ranks) do
		Catalog.SEAL_SPELL_ID_TO_ID[sid] = sealDef.id
	end
end

-- Paladin class blessing priority templates
Catalog.PALADIN_CLASS_PRIORITIES = {
	WARRIOR = { "BOK", "BOM", "BOL", "BOSANC", "BOSALV" },
	ROGUE   = { "BOK", "BOM", "BOSALV", "BOL", "BOSANC" },
	PRIEST  = { "BOK", "BOW", "BOSALV", "BOL", "BOSANC" },
	DRUID   = { "BOK", "BOW", "BOM", "BOSALV", "BOL", "BOSANC" },
	PALADIN = { "BOK", "BOW", "BOM", "BOSALV", "BOL", "BOSANC" },
	HUNTER  = { "BOK", "BOM", "BOW", "BOSALV", "BOL" },
	MAGE    = { "BOK", "BOW", "BOSALV", "BOL", "BOSANC" },
	WARLOCK = { "BOK", "BOW", "BOSALV", "BOL", "BOSANC" },
	SHAMAN  = { "BOK", "BOW", "BOM", "BOSALV", "BOL", "BOSANC" },
}

-- Shaman Totems (4 elements)
Catalog.TOTEM_ELEMENTS = { "EARTH", "FIRE", "WATER", "AIR" }

Catalog.SHAMAN_TOTEMS = {
	EARTH = {
		{ id = "STRENGTH_OF_EARTH", name = "Strength of Earth Totem", shortName = "Str",    icon = 136023, ranks = { 25361, 10442, 8161, 8160, 8075 }, auraName = "Strength of Earth" },
		{ id = "STONESKIN",         name = "Stoneskin Totem",         shortName = "Skin",   icon = 136097, ranks = { 10408, 10407, 10406, 8155, 8154, 8071 }, auraName = "Stoneskin" },
		{ id = "TREMOR",            name = "Tremor Totem",            shortName = "Tremor", icon = 136108, ranks = { 8143 }, auraName = "Tremor Totem" },
	},
	FIRE = {
		{ id = "FLAMETONGUE",       name = "Flametongue Totem",       shortName = "Flame",  icon = 136040, ranks = { 16387, 10526, 8249, 8227 }, auraName = "Flametongue Totem" },
		{ id = "FROST_RES_TOTEM",   name = "Frost Resistance Totem",  shortName = "FrRes",  icon = 135866, ranks = { 10479, 10478, 8181 }, auraName = "Frost Resistance" },
		{ id = "SEARING",           name = "Searing Totem",           shortName = "Sear",   icon = 135825, ranks = { 10438, 10437, 6365, 6364, 6363, 3599 }, auraName = "Searing Totem" },
	},
	WATER = {
		{ id = "MANA_SPRING",       name = "Mana Spring Totem",       shortName = "Mana",   icon = 136053, ranks = { 10497, 10496, 10495, 5675 }, auraName = "Mana Spring" },
		{ id = "HEALING_STREAM",    name = "Healing Stream Totem",    shortName = "Heal",   icon = 135127, ranks = { 10463, 10462, 6377, 6375, 5394 }, auraName = "Healing Stream" },
		{ id = "POISON_CLEANSING",  name = "Poison Cleansing Totem",  shortName = "Pois",   icon = 136070, ranks = { 8166 }, auraName = "Poison Cleansing Totem" },
		{ id = "FIRE_RES_TOTEM",    name = "Fire Resistance Totem",   shortName = "FiRes",  icon = 135832, ranks = { 10538, 10537, 8184 }, auraName = "Fire Resistance" },
	},
	AIR = {
		{ id = "WINDFURY",          name = "Windfury Totem",          shortName = "WF",     icon = 136114, ranks = { 10614, 10613, 8512 }, auraName = "Windfury Totem" },
		{ id = "GRACE_OF_AIR",      name = "Grace of Air Totem",      shortName = "Grace",  icon = 136046, ranks = { 25359, 10627, 8835 }, auraName = "Grace of Air" },
		{ id = "TRANQUIL_AIR",      name = "Tranquil Air Totem",      shortName = "Tranq",  icon = 136013, ranks = { 25908 }, auraName = "Tranquil Air" },
		{ id = "NATURE_RES_TOTEM",  name = "Nature Resistance Totem", shortName = "NatRes", icon = 136061, ranks = { 10601, 10600, 10595 }, auraName = "Nature Resistance" },
		{ id = "GROUNDING",         name = "Grounding Totem",         shortName = "Ground", icon = 136039, ranks = { 8177 }, auraName = "Grounding Totem" },
	},
}

Catalog.TOTEM_BY_ID = {}
for _, element in ipairs(Catalog.TOTEM_ELEMENTS) do
	for _, totem in ipairs(Catalog.SHAMAN_TOTEMS[element]) do
		totem.element = element
		Catalog.TOTEM_BY_ID[totem.id] = totem
	end
end

Catalog.SHAMAN_ROLE_PRESETS = {
	MELEE = {
		EARTH = { "STRENGTH_OF_EARTH", "STONESKIN", "TREMOR" },
		FIRE  = { "FLAMETONGUE", "SEARING", "FROST_RES_TOTEM" },
		WATER = { "MANA_SPRING", "HEALING_STREAM", "POISON_CLEANSING", "FIRE_RES_TOTEM" },
		AIR   = { "WINDFURY", "GRACE_OF_AIR", "TRANQUIL_AIR", "NATURE_RES_TOTEM", "GROUNDING" },
	},
	CASTER = {
		EARTH = { "STONESKIN", "TREMOR", "STRENGTH_OF_EARTH" },
		FIRE  = { "FLAMETONGUE", "FROST_RES_TOTEM", "SEARING" },
		WATER = { "MANA_SPRING", "HEALING_STREAM", "POISON_CLEANSING", "FIRE_RES_TOTEM" },
		AIR   = { "TRANQUIL_AIR", "NATURE_RES_TOTEM", "GROUNDING", "GRACE_OF_AIR", "WINDFURY" },
	},
}

-- Effect-based Consumables
Catalog.CONSUMABLES = {
	WELL_FED = {
		id = "WELL_FED",
		name = "Well Fed",
		shortName = "Food",
		icon = 134062,
		patterns = { "^Well Fed", "Increased Stamina", "Increased Intellect", "Mana Regeneration", "Increased Agility", "Increased Strength", "Spell Damage" },
		spellIDs = {
			[19705] = true, [19706] = true, [19708] = true, [19709] = true,
			[19710] = true, [19711] = true, [22730] = true, [24799] = true,
			[25661] = true, [25941] = true, [18192] = true, [18194] = true,
			[18222] = true, [22731] = true,
		},
	},
	FLASK_ELIXIR = {
		id = "FLASK_ELIXIR",
		name = "Flask / Elixir",
		shortName = "Flask",
		icon = 134877,
		patterns = {
			"^Flask of",
			"^Elixir of",
			"Greater Arcane Elixir",
			"Arcane Elixir",
			"Mageblood",
			"Mongoose",
			"Greater Agility",
			"Elixir of the Giants",
			"Superior Defense",
			"Shadow Power",
			"Greater Firepower",
			"Frost Power",
			"Juju Power",
			"Juju Might",
			"Winterfall Firewater",
		},
		spellIDs = {
			[17626] = true, [17627] = true, [17628] = true, [17629] = true, -- Flasks
			[17538] = true, [17539] = true, [24363] = true, [11405] = true, -- Mongoose, GAE, Mageblood, Giants
			[11334] = true, [11390] = true, [11474] = true, [26276] = true,
			[17537] = true, [11348] = true, [3593]  = true, [17038] = true,
		},
	},
	WEAPON_OIL = {
		id = "WEAPON_OIL",
		name = "Weapon Oil / Stone",
		shortName = "Wep",
		icon = 134886,
		usesWeaponEnchantAPI = true,
	},
}

Catalog.CONSUMABLE_ORDER = { "WELL_FED", "FLASK_ELIXIR", "WEAPON_OIL" }

-- Tracking keyword classification for Capabilities / Tracking watcher
Catalog.TRACKING_PATTERNS = {
	PROFESSION = {
		"Find Minerals",
		"Find Herbs",
		"Find Treasure",
		"Find Fish",
	},
	HUNTER = {
		"Track Beasts",
		"Track Humanoids",
		"Track Undead",
		"Track Hidden",
		"Track Elementals",
		"Track Demons",
		"Track Giants",
		"Track Dragonkin",
	},
	CLASS = {
		"Sense Undead",
		"Sense Demons",
	},
}

function Catalog.GetFamily(familyID)
	return Catalog.BUFF_FAMILIES[familyID]
end

function Catalog.GetClassFamilies(classToken)
	return Catalog.CLASS_BUFFS[classToken] or {}
end

function Catalog.ClassUsesMana(classToken)
	local info = Catalog.CLASS_INFO[classToken]
	return info and info.usesMana or false
end

function Catalog.MatchesUnitFilter(family, unitInfo)
	if not family or not unitInfo then
		return false
	end
	local filter = family.targetFilter or "ALL"
	if filter == "ALL" or filter == "PARTY" then
		return true
	elseif filter == "MANA" then
		return Catalog.ClassUsesMana(unitInfo.class)
	elseif filter == "TANK_MELEE" then
		if unitInfo.role == "TANK" then
			return true
		end
		local info = Catalog.CLASS_INFO[unitInfo.class]
		return info and info.isTank or false
	elseif filter == "HEALER_TANK" then
		return unitInfo.role == "HEALER" or unitInfo.role == "TANK"
	elseif filter == "CASTER" then
		local info = Catalog.CLASS_INFO[unitInfo.class]
		return info and info.isCaster or false
	end
	return true
end
