-- Made-up fixture for tools/test/test_check_loot.py (not real data)
-- [instanceMapID][bossName] = { {itemID, forever(0/1), dropPercent|nil}, ... }
local _, ns = ...
ns.Loot = {
  [9001] = { -- Fixture Keep
    ["Alpha Boss"] = {{1001,0,20},{1002,0},{270001,1}},
    ["Beta Boss"] = {{2001,0},{2002,0}},
    ["Delta Add"] = {{4001,0}},
    ["Eta Retired"] = {{7001,0}},
    ["Lambda Sub"] = {{1101,0},{1102,0}},
    ["Trash"] = {{9901,0}},
  },
}
