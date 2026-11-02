Made-up fixture for tools/check_loot.py (used by tools/test/test_check_loot.py). Every name, NPC id and item id here is invented;
no AtlasLoot or CMaNGOS content. Same layout as the repo (`--root tools/test/loot_check`), AtlasLoot folder in `atlas/`
(`--atlas`), CMaNGOS classic-db format in `classic-db-fixture.sql.txt` (`--cdb`; `.txt` because `*.sql` is git-ignored).
Expected per boss (instance 9001 "Fixture Keep" unless noted):
  Alpha Boss     same loot everywhere; one Forever item -> cross-check: agrees, Forever item listed apart
  Beta Boss      AtlasLoot gained 2003 and lost 2002 -> NEW +2003, REMOVED -2002; CMaNGOS has 2099 (via a reference) -> MISMATCH
  Gamma Event    no loot anywhere, allowlisted -> ALLOWLISTED
  Delta Add      allowlisted but has loot -> STALE ALLOWLIST; LootId 0 in CMaNGOS -> no CMaNGOS loot
  Epsilon Boss   no loot anywhere, not allowlisted -> MISSING
  Zeta Newcomer  AtlasLoot has loot, Loot.lua has no entry -> NEW (new boss loot); cross-check agrees
  Eta Retired    in Loot.lua, AtlasLoot dropped it -> REMOVED
  Trash          trash table via boss_trash.csv -> unchanged, not cross-checked
  Theta Lone     (instance 9002) no AtlasLoot data for the instance -> MISSING
  Omega Gone     allowlist row for a boss Dungeons.lua does not have -> STALE ALLOWLIST
  FixtureUnmapped  AtlasLoot dungeon without a plain InstanceID -> unmapped=1
  Iota Unreleased  (instance 9003, dungeon_status.csv classic) no loot anywhere -> NOT RELEASED, not MISSING;
                   MISSING again when its status row is removed (the test does that on a copy)
  Kappa Hidden     (instance 9004, dungeon_status.csv hidden) no loot anywhere -> NOT RELEASED
