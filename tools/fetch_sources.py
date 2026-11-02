#!/usr/bin/env python3
"""Download and check the freshness of the third-party data sources the generators read.

    tools/fetch_sources.py --check                 network check only (one request per source); downloads nothing.
                                                   Prints per source: up to date / NEWER AVAILABLE <id> / ERROR <reason>,
                                                   then one machine-readable line:
                                                   SOURCES cdb=ok|newer|missing|error atlas=ok|newer|missing|error
    tools/fetch_sources.py --fetch [cdb|atlas]     refresh the cache (both sources if none is named) and print the
                                                   paths to pass to tools/update.py --cdb <sql> --atlas <dir>
    options:  --dest <dir>   cache folder (default ~/dungeon-loop/sources; refused if inside this repository)
              --force        --fetch: rebuild even when the stored copy matches upstream

Sources (licences in data/SOURCES.md):
  cdb    CMaNGOS classic-db, https://github.com/cmangos/classic-db (GPL-3.0). Upstream ships a gzip'd mysqldump
         (Full_DB/*.sql.gz, content up to the update named in its db_version table), the EventAI scripts separately
         (ACID/acid_classic.sql, which InstallFullDB.sh loads after the dump with TRUNCATE + INSERT) and SQL update files
         (Updates/, Updates/Instances/) that need a MySQL server to apply. Freshness: `git ls-remote` of master vs the
         stored commit. --fetch makes a shallow sparse clone (Full_DB, ACID, Updates) and builds ONE .sql in the format
         gen_quests.py / gen_abilities.py read: the dump, with the tables ACID truncates (creature_ai_scripts,
         creature_ai_summons) replaced by ACID's rows (one INSERT line per batch, columns in the dump's order).
         The Updates/ files are NOT applied (no MySQL here); their number is reported.
  atlas  AtlasLoot Forever (CurseForge project 1422985, author sliccer, GPL-2.0). There is no key-free route to the
         upstream release: CurseForge's API needs a key, CDN downloads need a key since 2026-07-16, and the Overwolf
         Platform Terms (7.2(iv)) forbid automated access to or monitoring of the CurseForge website. So upstream is NOT
         checked. Instead the copy the maintainer's CurseForge app installed in the game folder is read (never written):
         sha256 of AtlasLootClassic_DungeonsAndRaids/data.lua + droprate.lua tells when its content changed (the TOC
         version string does not change with data updates), and --fetch copies those files into the cache.

Downloaded files are data only: nothing from the cache is executed or imported. --check also writes the last check
time into <dest>/state.json (nothing else). Exit code 1 if any source reported ERROR, else 0.
Run: tools/.venv/bin/python -I -B tools/fetch_sources.py --check
"""
import datetime, gzip, hashlib, json, os, re, shutil, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WOW_DIR = os.environ.get("WOW_DIR", "/Applications/World of Warcraft/_classic_beta_")  # game client folder; set WOW_DIR to override
DEFAULT_DEST = os.path.expanduser("~/dungeon-loop/sources")
CDB_URL = "https://github.com/cmangos/classic-db.git"
CDB_BRANCH = "master"
CDB_SPARSE = ("/Full_DB/", "/ACID/", "/Updates/")
SQL_NAME = "classic-db.sql"
ATLAS_DIR = "AtlasLootClassic_DungeonsAndRaids"
ATLAS_HASHED = ("data.lua", "droprate.lua")          # what gen_loot.py / gen_abilities.py read
ATLAS_COPIED = ATLAS_HASHED + (ATLAS_DIR + ".toc", ATLAS_DIR + "_Forever.toc")
ATLAS_UPSTREAM = "not checked: no key-free route (CurseForge API and CDN need a key; its terms forbid automated access)"
LS_REMOTE_TIMEOUT, CLONE_TIMEOUT = 30, 600
ROWS_PER_INSERT = 500


def now():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def run_git(args, timeout, cwd=None):
    """git with no prompts and no hooks; returns stdout or raises RuntimeError with a short reason."""
    env = {**os.environ, "GIT_TERMINAL_PROMPT": "0", "GIT_ASKPASS": "true"}
    try:
        r = subprocess.run(["git", "-c", "core.hooksPath=/dev/null", *args], cwd=cwd, env=env,
                           capture_output=True, text=True, timeout=timeout)
    except FileNotFoundError:
        raise RuntimeError("git is not installed")
    except subprocess.TimeoutExpired:
        raise RuntimeError(f"git {args[0]} timed out after {timeout}s (offline?)")
    if r.returncode != 0:
        msg = (r.stderr.strip().splitlines() or ["exit code %d" % r.returncode])[-1]
        raise RuntimeError(f"git {args[0]} failed: {msg[:200]}")
    return r.stdout


# ---------------------------------------------------------------- state / cache folder
def resolve_dest(dest):
    dest = os.path.realpath(os.path.expanduser(dest))
    root = os.path.realpath(ROOT)
    if dest == root or dest.startswith(root + os.sep):
        raise SystemExit(f"refusing --dest {dest}: it is inside the repository; the cache must stay outside git")
    return dest


def load_state(dest):
    try:
        with open(os.path.join(dest, "state.json"), encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def save_state(dest, state):
    os.makedirs(dest, exist_ok=True)
    tmp = os.path.join(dest, "state.json.tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(state, f, indent=2, sort_keys=True)
        f.write("\n")
    os.replace(tmp, os.path.join(dest, "state.json"))


# ---------------------------------------------------------------- SQL helpers (data only, never executed)
def split_statements(text):
    """Split SQL text into statements on ';' outside quotes; drops -- and /* */ comments outside quotes."""
    out, buf, i, n = [], [], 0, len(text)
    while i < n:
        c = text[i]
        if c in "'\"`":
            j = i + 1
            while j < n:
                if text[j] == "\\":
                    j += 2; continue
                if text[j] == c:
                    if j + 1 < n and text[j + 1] == c:
                        j += 2; continue
                    break
                j += 1
            buf.append(text[i:j + 1]); i = j + 1; continue
        if c == "-" and text.startswith("--", i):
            j = text.find("\n", i)
            i = n if j < 0 else j + 1; buf.append("\n"); continue
        if c == "/" and text.startswith("/*", i):
            j = text.find("*/", i + 2)
            i = n if j < 0 else j + 2; buf.append(" "); continue
        if c == ";":
            stmt = "".join(buf).strip()
            if stmt:
                out.append(stmt)
            buf = []; i += 1; continue
        buf.append(c); i += 1
    stmt = "".join(buf).strip()
    if stmt:
        out.append(stmt)
    return out


def parse_tuples(s):
    """'(1,'a\\'b',NULL),(2,...)' -> [['1', "a'b", None], ...] (values as strings, NULL as None)."""
    rows, row, i, n = [], None, 0, len(s)
    while i < n:
        c = s[i]
        if c == "(" and row is None:
            row = []; i += 1; continue
        if c == ")" and row is not None:
            rows.append(row); row = None; i += 1; continue
        if c in ", \t\r\n":
            i += 1; continue
        if row is None:
            raise ValueError(f"unexpected {c!r} between rows at {i}")
        if c in "'\"":
            j, buf = i + 1, []
            while True:
                if j >= n:
                    raise ValueError("unterminated string")
                if s[j] == "\\":
                    buf.append({"n": "\n", "r": "\r", "t": "\t", "0": "\0"}.get(s[j + 1], s[j + 1])); j += 2; continue
                if s[j] == c:
                    if j + 1 < n and s[j + 1] == c:
                        buf.append(c); j += 2; continue
                    break
                buf.append(s[j]); j += 1
            row.append("".join(buf)); i = j + 1; continue
        j = i
        while j < n and s[j] not in ",)":
            j += 1
        v = s[i:j].strip()
        row.append(None if v.upper() == "NULL" else v)
        i = j
    if row is not None:
        raise ValueError("unterminated row")
    return rows


def sql_value(v):
    if v is None:
        return "NULL"
    if re.fullmatch(r"-?\d+(\.\d+)?", v):
        return v
    return "'" + v.replace("\\", "\\\\").replace("'", "\\'").replace("\n", "\\n").replace("\r", "\\r") + "'"


INSERT_RE = re.compile(r"(?:INSERT|REPLACE)\s+INTO\s+`?(\w+)`?\s*\(([^)]*)\)\s*VALUES\s*(.*)\Z", re.S | re.I)


def parse_acid(text):
    """ACID file -> (truncated tables, {table: (columns, rows)}, [ignored statement summaries])."""
    truncated, inserts, ignored = [], {}, []
    for st in split_statements(text):
        m = re.match(r"TRUNCATE\s+(?:TABLE\s+)?`?(\w+)`?\s*\Z", st, re.I)
        if m:
            truncated.append(m.group(1)); continue
        m = INSERT_RE.match(st)
        if m:
            table = m.group(1)
            cols = [c.strip().strip("`") for c in m.group(2).split(",")]
            rows = parse_tuples(m.group(3))
            bad = [r for r in rows if len(r) != len(cols)]
            if bad:
                raise ValueError(f"ACID {table}: a row has {len(bad[0])} values for {len(cols)} columns")
            prev = inserts.setdefault(table, (cols, []))
            if prev[0] != cols:
                raise ValueError(f"ACID {table}: INSERT statements with different column lists")
            prev[1].extend(rows)
            continue
        if re.match(r"(INSERT|REPLACE)\b", st, re.I):
            raise ValueError(f"ACID: INSERT without a column list is not supported: {st[:80]}")
        ignored.append(" ".join(st.split())[:90])
    return truncated, inserts, ignored


def build_sql(dump_gz, acid_path, out_path, header=""):
    """Write out_path = dump with the tables ACID truncates replaced by ACID's rows. Returns a summary dict."""
    with open(acid_path, encoding="utf-8", errors="replace") as f:
        truncated, inserts, ignored = parse_acid(f.read())
    replace = [t for t in truncated if t in inserts]
    emptied = [t for t in truncated if t not in inserts]
    tmp = out_path + ".tmp"
    done, content_version, dump_rows_dropped = set(), None, 0
    in_create, create_cols = None, []
    try:
        with gzip.open(dump_gz, "rt", encoding="utf-8", errors="surrogateescape") as src, \
                open(tmp, "w", encoding="utf-8", errors="surrogateescape", newline="\n") as out:
            if header:
                out.write("".join(f"-- {line}\n" for line in header.splitlines()))
            for line in src:
                m = re.match(r"INSERT INTO `(\w+)` ", line)
                if m and m.group(1) in truncated:
                    dump_rows_dropped += 1
                    continue
                out.write(line)
                if line.startswith("CREATE TABLE `"):
                    in_create, create_cols = re.match(r"CREATE TABLE `(\w+)`", line).group(1), []
                    continue
                if in_create:
                    cm = re.match(r"\s+`([^`]+)`", line)
                    if cm:
                        create_cols.append(cm.group(1))
                        if in_create == "db_version":
                            vm = re.match(r"content_(\d+)_", cm.group(1))
                            if vm:
                                content_version = int(vm.group(1))
                        continue
                    if line.rstrip().endswith(";"):            # end of CREATE TABLE: emit ACID rows for this table here
                        if in_create in replace:
                            acols, rows = inserts[in_create]
                            if set(acols) != set(create_cols):
                                raise ValueError(f"{in_create}: ACID columns {sorted(set(acols) ^ set(create_cols))} "
                                                 "differ from the dump's table definition")
                            order = [acols.index(c) for c in create_cols]
                            for k in range(0, len(rows), ROWS_PER_INSERT):
                                vals = ",".join("(" + ",".join(sql_value(r[i]) for i in order) + ")"
                                                for r in rows[k:k + ROWS_PER_INSERT])
                                out.write(f"INSERT INTO `{in_create}` VALUES {vals};\n")
                            done.add(in_create)
                        in_create = None
        missing = [t for t in replace if t not in done]
        if missing:
            raise ValueError(f"tables {missing} from ACID have no CREATE TABLE in the dump")
    except BaseException:
        if os.path.exists(tmp):
            os.remove(tmp)
        raise
    os.replace(tmp, out_path)
    return {"replaced": {t: len(inserts[t][1]) for t in replace}, "emptied": emptied, "ignored": ignored,
            "dump_insert_lines_dropped": dump_rows_dropped, "content_version": content_version}


def count_updates(repo, content_version):
    """Update files InstallFullDB.sh would apply after the dump (we cannot, without MySQL)."""
    upd = os.path.join(repo, "Updates")
    files = sorted(f for f in os.listdir(upd) if f.endswith(".sql")) if os.path.isdir(upd) else []
    num = lambda f: int(re.match(r"\d+", f).group())
    newer = [f for f in files if re.match(r"\d+", f) and (content_version is None or num(f) > content_version)]
    content = [f for f in newer if num(f) < 9999]          # 9999_* is a cleanup script, not a content update
    inst = os.path.join(upd, "Instances")
    n_inst = len([f for f in os.listdir(inst) if f.endswith(".sql")]) if os.path.isdir(inst) else 0
    return {"updates_newer_than_dump": len(newer), "instance_scripts": n_inst,
            "last_update_file": max(content, key=num) if content else None}


# ---------------------------------------------------------------- cdb
def cdb_upstream():
    out = run_git(["ls-remote", CDB_URL, f"refs/heads/{CDB_BRANCH}"], LS_REMOTE_TIMEOUT)
    m = re.match(r"([0-9a-f]{40})\s", out)
    if not m:
        raise RuntimeError(f"no {CDB_BRANCH} branch in ls-remote output")
    return m.group(1)


def cdb_local_ok(dest, st):
    sql = os.path.join(dest, "classic-db", SQL_NAME)
    return bool(st.get("commit")) and os.path.isfile(sql) and os.path.getsize(sql) == st.get("sql_bytes")


def check_cdb(dest, state):
    st = state.get("cdb", {})
    try:
        up = cdb_upstream()
    except RuntimeError as e:
        return "error", f"ERROR {e}"
    if not cdb_local_ok(dest, st):
        return "missing", f"not in the cache (upstream {up[:10]}); run --fetch cdb"
    if up != st["commit"]:
        return "newer", f"NEWER AVAILABLE commit {up[:10]} (have {st['commit'][:10]} from {st.get('commit_date', '?')})"
    return "ok", f"up to date (commit {up[:10]} from {st.get('commit_date', '?')})"


def fetch_cdb(dest, state, force=False):
    st = state.get("cdb", {})
    base = os.path.join(dest, "classic-db")
    sql = os.path.join(base, SQL_NAME)
    up = cdb_upstream()
    if not force and cdb_local_ok(dest, st) and st["commit"] == up:
        print(f"cdb: up to date (commit {up[:10]}), nothing downloaded")
        return sql
    os.makedirs(base, exist_ok=True)
    new = os.path.join(base, "repo.new")
    shutil.rmtree(new, ignore_errors=True)
    print(f"cdb: shallow sparse clone of {CDB_URL} ({', '.join(CDB_SPARSE)}) ...", flush=True)
    run_git(["clone", "--quiet", "--depth", "1", "--filter=blob:none", "--sparse", "--single-branch",
             "--branch", CDB_BRANCH, CDB_URL, new], CLONE_TIMEOUT)
    run_git(["sparse-checkout", "set", "--no-cone", *CDB_SPARSE], CLONE_TIMEOUT, cwd=new)
    commit, date = run_git(["log", "-1", "--format=%H %cI"], 30, cwd=new).split()
    dumps = sorted(f for f in os.listdir(os.path.join(new, "Full_DB")) if f.endswith(".sql.gz"))
    acid = os.path.join(new, "ACID", "acid_classic.sql")
    if len(dumps) != 1 or not os.path.isfile(acid):
        raise RuntimeError(f"unexpected upstream layout: Full_DB dumps {dumps}, ACID file present: {os.path.isfile(acid)}"
                           " (InstallFullDB.sh may have changed; update this tool)")
    dump = os.path.join(new, "Full_DB", dumps[0])
    inputs = {"full_db": dumps[0], "full_db_sha256": sha256(dump), "acid_sha256": sha256(acid)}
    repo = os.path.join(base, "repo")
    shutil.rmtree(repo, ignore_errors=True)
    os.replace(new, repo)
    dump, acid = os.path.join(repo, "Full_DB", dumps[0]), os.path.join(repo, "ACID", "acid_classic.sql")
    same_inputs = all(st.get(k) == v for k, v in inputs.items()) and cdb_local_ok(dest, st)
    if same_inputs and not force:
        print(f"cdb: upstream moved to {commit[:10]} but Full_DB and ACID are unchanged: {SQL_NAME} kept (inputs changed: no)")
        summary = {k: st[k] for k in ("replaced", "emptied", "ignored_acid_statements", "content_version") if k in st}
    else:
        print(f"cdb: building {sql} from {dumps[0]} + ACID/acid_classic.sql ...", flush=True)
        header = (f"Built by tools/fetch_sources.py from {CDB_URL} commit {commit} ({date}).\n"
                  f"Full_DB/{dumps[0]} with the tables ACID/acid_classic.sql truncates replaced by ACID's rows.\n"
                  "Updates/ files are NOT applied (they need MySQL). Data only; GPL-3.0 (CMaNGOS).")
        b = build_sql(dump, acid, sql, header)
        summary = {"replaced": b["replaced"], "emptied": b["emptied"], "ignored_acid_statements": b["ignored"],
                   "content_version": b["content_version"]}
        print(f"cdb: built (inputs changed: yes); ACID rows: {b['replaced']}; ACID statements ignored: {len(b['ignored'])}")
    upd = count_updates(repo, summary.get("content_version"))
    state["cdb"] = {"repo": CDB_URL, "commit": commit, "commit_date": date, "fetched": now(), "last_check": now(),
                    **inputs, **summary, **upd, "sql": sql, "sql_bytes": os.path.getsize(sql), "sql_sha256": sha256(sql)}
    save_state(dest, state)
    print(f"cdb: {sql} ({os.path.getsize(sql) / 1e6:.1f} MB, sha256 {state['cdb']['sql_sha256'][:16]}), commit {commit[:10]} ({date})")
    print(f"cdb: dump content version {summary.get('content_version')}; NOT applied: {upd['updates_newer_than_dump']} "
          f"Updates/*.sql files (last {upd['last_update_file']}) and {upd['instance_scripts']} Updates/Instances scripts")
    return sql


# ---------------------------------------------------------------- atlas
def atlas_installed():
    return os.path.join(WOW_DIR, "Interface", "AddOns", ATLAS_DIR)


def atlas_hashes(folder):
    return {f: sha256(os.path.join(folder, f)) for f in ATLAS_HASHED}


def toc_version(folder):
    toc = os.path.join(os.path.dirname(folder), "AtlasLootClassic", "AtlasLootClassic.toc")
    try:
        with open(toc, encoding="utf-8", errors="replace") as f:
            m = re.search(r"^## Version:\s*(.+?)\s*$", f.read(), re.M)
        return m.group(1) if m else None
    except OSError:
        return None


def atlas_cache(dest):
    return os.path.join(dest, "atlasloot", ATLAS_DIR)


def check_atlas(dest, state):
    st = state.get("atlas", {})
    inst = atlas_installed()
    if not all(os.path.isfile(os.path.join(inst, f)) for f in ATLAS_HASHED):
        return "error", f"ERROR installed AtlasLoot not found in {inst} (set WOW_DIR)"
    cache = atlas_cache(dest)
    stored = st.get("sha256", {})
    if not stored or not all(os.path.isfile(os.path.join(cache, f)) for f in ATLAS_HASHED) or atlas_hashes(cache) != stored:
        return "missing", "not in the cache; run --fetch atlas"
    now_h = atlas_hashes(inst)
    if now_h != stored:
        changed = ", ".join(f for f in ATLAS_HASHED if now_h[f] != stored.get(f))
        return "newer", f"NEWER AVAILABLE installed copy changed ({changed}; TOC version {toc_version(inst)})"
    return "ok", f"up to date (installed copy unchanged since {st.get('fetched', '?')}; TOC version {toc_version(inst)})"


def fetch_atlas(dest, state, force=False):
    inst = atlas_installed()
    if not all(os.path.isfile(os.path.join(inst, f)) for f in ATLAS_HASHED):
        raise RuntimeError(f"installed AtlasLoot not found in {inst} (set WOW_DIR)")
    cache = atlas_cache(dest)
    st = state.get("atlas", {})
    hashes = atlas_hashes(inst)
    if not force and st.get("sha256") == hashes and os.path.isdir(cache) and atlas_hashes(cache) == hashes:
        print("atlas: cache already matches the installed copy, nothing copied")
        return cache
    tmp = cache + ".new"
    shutil.rmtree(tmp, ignore_errors=True)
    os.makedirs(tmp)
    for f in ATLAS_COPIED:                       # read from the game folder, write only into the cache
        if os.path.isfile(os.path.join(inst, f)):
            shutil.copyfile(os.path.join(inst, f), os.path.join(tmp, f))
    if atlas_hashes(tmp) != hashes:
        shutil.rmtree(tmp, ignore_errors=True)
        raise RuntimeError("installed AtlasLoot changed while copying; try again when the CurseForge app is idle")
    shutil.rmtree(cache, ignore_errors=True)
    os.replace(tmp, cache)
    previous = st.get("sha256")
    state["atlas"] = {"source": "installed copy (read-only)", "installed": inst, "toc_version": toc_version(inst),
                      "sha256": hashes, "bytes": {f: os.path.getsize(os.path.join(cache, f)) for f in ATLAS_HASHED},
                      "fetched": now(), "last_check": now(), "upstream": ATLAS_UPSTREAM,
                      "curseforge_project": 1422985}
    save_state(dest, state)
    print(f"atlas: copied {', '.join(ATLAS_HASHED)} from the installed copy to {cache} "
          f"({'content changed' if previous and previous != hashes else 'first copy' if not previous else 'forced'})")
    for f in ATLAS_HASHED:
        print(f"atlas:   {f}: {state['atlas']['bytes'][f]} bytes, sha256 {hashes[f][:16]}")
    print(f"atlas: upstream {ATLAS_UPSTREAM}")
    return cache


# ---------------------------------------------------------------- main
def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    dest = resolve_dest(argv[argv.index("--dest") + 1]) if "--dest" in argv else resolve_dest(DEFAULT_DEST)
    state = load_state(dest)
    if "--check" in argv:
        res = {}
        for name, fn in (("cdb", check_cdb), ("atlas", check_atlas)):
            try:
                res[name], msg = fn(dest, state)
            except Exception as e:  # report, never retry
                res[name], msg = "error", f"ERROR {type(e).__name__}: {e}"
            print(f"{name}: {msg}")
            if name in state:
                state[name]["last_check"] = now()
        print(f"atlas upstream: {ATLAS_UPSTREAM}; the CurseForge app shows when a newer AtlasLoot Forever is out")
        if state:
            save_state(dest, state)
        print(f"SOURCES cdb={res['cdb']} atlas={res['atlas']}")
        return 1 if "error" in res.values() else 0
    if "--fetch" in argv:
        i = argv.index("--fetch")
        which = [argv[i + 1]] if i + 1 < len(argv) and argv[i + 1] in ("cdb", "atlas") else ["cdb", "atlas"]
        force, paths, failed = "--force" in argv, {}, False
        for name in which:
            try:
                paths[name] = (fetch_cdb if name == "cdb" else fetch_atlas)(dest, state, force)
            except Exception as e:
                print(f"{name}: ERROR {type(e).__name__}: {e}")
                failed = True
        st = load_state(dest)
        sql = paths.get("cdb") or st.get("cdb", {}).get("sql")
        atlas = paths.get("atlas") or (atlas_cache(dest) if st.get("atlas") else None)
        print("\nPaths for tools/update.py:")
        print(f"  --cdb {sql}" if sql else "  --cdb (not fetched)")
        print(f"  --atlas {atlas}" if atlas else "  --atlas (not fetched)")
        if sql and atlas:
            print(f"  tools/.venv/bin/python -B tools/update.py --cdb '{sql}' --atlas '{atlas}'")
        return 1 if failed else 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
