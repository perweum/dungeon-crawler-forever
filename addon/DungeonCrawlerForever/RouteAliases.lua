-- Old route versions that still count (D-073). A route's version is a hash of its boss set, so changing a route's bosses starts a new board and
-- the runs on the old one stop showing, here and on every machine that has the new addon. When a change does NOT make times incomparable (a boss
-- left off, a rename), add a row here instead of letting the board break; runs and digests with the old version are then read as the current route.
--   { inst = <instance id>, wing = <wing or omit>, rv = "<the OLD version>", to = "<current route id>", bosses = { "<the OLD route's boss names>" } }
-- `bosses` must be the old route's complete boss list (the kill positions in a message are indexes into it, sorted A-Z). The current route's bosses must
-- all be among them (an old run has to contain every boss of the new route). Get the old version and list from the snapshot in
-- tools/test/fixtures/route_versions.csv before you change the data: the test fails and names the row when a version disappears without a row here.
local _, ns = ...
ns.RouteAliases = {
    -- Rebuilt from the release tags (0.2.0 to 0.3.6, D-073): the routes that changed. Each old route had every regular boss (or one more boss) and the
    -- current route is a subset; the extra bosses were rares / optional bosses / one not yet found, so the times stay comparable.
    -- Upper Blackrock Spire 0.2.0-0.3.0: all regular bosses
    { inst = 229, wing = 2, rv = "91496", to = "main", bosses = { "Pyroguard Emberseer", "Solakar Flamewreath", "Jed Runewatcher", "Warchief Rend Blackhand", "The Beast", "General Drakkisath", "Gyth" } },
    -- Blackrock Depths 0.2.0-0.3.0: all regular bosses
    { inst = 230, rv = "90e44", to = "main", bosses = { "High Interrogator Gerstahn", "Lord Roccor", "Houndmaster Grebmar", "Ring of Law", "Pyromancer Loregrain", "Lord Incendius", "Warder Stilgiss", "Fineous Darkvire", "Bael'Gar", "General Angerforge", "Golem Lord Argelmach", "Hurley Blackbreath", "Phalanx", "Ribbly Screwspigot", "Plugger Spazzring", "Ambassador Flamelash", "The Seven", "Magmus", "Princess Moira Bronzebeard", "Emperor Dagran Thaurissan", "Watchman Doomgrip" } },
    -- Dire Maul West 0.2.0-0.3.0: all regular bosses
    { inst = 429, wing = 2, rv = "91a02", to = "main", bosses = { "Tendris Warpwood", "Illyanna Ravenoak", "Magister Kalendris", "Immol'thar", "Prince Tortheldrin", "Tsu'zee" } },
    -- The Shaper's Terrace 0.2.0-0.3.2: with King Op
    { inst = 3001, rv = "37f9e", to = "main", bosses = { "Titanosaur", "Izha'Rel and Tor'Rel", "Thunderhoof", "Venomridge", "Direhorn Matriarch", "Cinder", "King Op", "Snowtalon", "Bolt", "Vitrix", "Nanaya" } },
}
