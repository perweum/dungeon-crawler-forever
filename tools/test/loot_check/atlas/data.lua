-- Made-up fixture in the layout of AtlasLootClassic_DungeonsAndRaids/data.lua (not real data)
local data = {}
data["FixtureKeep"] = {
	name = "Fixture Keep",
	InstanceID = 9001,
	items = {
		{ -- FixtureAlpha
			name = AL["Alpha Boss"],
			npcID = 50001,
			[NORMAL_DIFF] = {
				{ 1, 1001 }, -- Made-up Sword
				{ 2, 1002 }, -- Made-up Shield
				{ 3, 270001 }, -- {FOREVER} Made-up Forever Ring
			},
		},
		{ -- FixtureBeta
			name = AL["Beta Boss"],
			npcID = 50002,
			[NORMAL_DIFF] = {
				{ 1, 2001 }, -- Made-up Helm
				{ 2, 2003 }, -- Made-up Boots
			},
		},
		{ -- FixtureDelta
			name = AL["Delta Add"],
			npcID = 50004,
			[NORMAL_DIFF] = {
				{ 1, 4001 }, -- Made-up Charm
			},
		},
		{ -- FixtureZeta
			name = AL["Zeta Newcomer"],
			npcID = 50006,
			[NORMAL_DIFF] = {
				{ 1, 6001 }, -- Made-up Cloak
				{ 2, 6002 }, -- Made-up Belt
			},
		},
		{ -- FixturePair
			name = AL["Pair Table"],
			npcID = { 50011, 50012 },
			[NORMAL_DIFF] = {
				{ 1,  "INV_Box_01", nil, AL["Lambda Sub"],  nil },
				{ 2, 1101 }, -- Made-up Gloves
				{ 3, 1102 }, -- Made-up Bracers
				{ 16, "INV_Box_01", nil, AL["Mu Outsider"], nil },
				{ 17, 1201 }, -- Made-up Recipe
			},
		},
		{ -- FixtureTrash
			name = AL["Trash"],
			[NORMAL_DIFF] = {
				{ 1, 9901 }, -- Made-up Junk
			},
		},
	},
}
data["FixtureUnmapped"] = {
	name = "Fixture Unmapped",
	InstanceID = SomeVersionCheck(9003),
	items = {
		{ -- FixtureUnmappedBoss
			name = AL["Unmapped Boss"],
			[NORMAL_DIFF] = {
				{ 1, 8001 }, -- Made-up Gem
			},
		},
	},
}
