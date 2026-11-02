-- Made-up fixture for tools/test/test_check_loot.py (not real data)
local _, ns = ...
ns.Dungeons = {
  [9001] = { name = "Fixture Keep", raid = false, hasArt = false, bosses = {
    { id = 1, name = "Alpha Boss", diff = 0, order = 0 },
    { id = 2, name = "Beta Boss", diff = 0, order = 1000 },
    { id = 3, name = "Gamma Event", diff = 0, order = 2000 },
    { id = 4, name = "Delta Add", diff = 0, order = 3000 },
    { id = 5, name = "Epsilon Boss", diff = 0, order = 4000 },
    { id = 6, name = "Zeta Newcomer", diff = 0, order = 5000 },
    { id = 7, name = "Eta Retired", diff = 0, order = 6000 },
    { id = 9, name = "Lambda Sub", diff = 0, order = 7000 },
    { id = 99, name = "Trash", diff = 0, order = 99000, trash = true },
  } },
  [9002] = { name = "Fixture Hall", raid = false, hasArt = false, bosses = {
    { id = 8, name = "Theta Lone", diff = 0, order = 0 },
  } },
  [9005] = { name = "Fixture Raid", raid = true, hasArt = false, status = "classic", bosses = {
    { id = 10, name = "Iota Unreleased", diff = 0, order = 0 },
  } },
  [9006] = { name = "Fixture Vault", raid = false, hasArt = false, bosses = {
    { id = 11, name = "Kappa Hidden", diff = 0, order = 0 },
  } },
}
