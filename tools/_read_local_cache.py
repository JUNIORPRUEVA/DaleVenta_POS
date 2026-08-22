# READ-ONLY: inspect local cache (shared_preferences + offline db) for company settings
import json, os, sqlite3

base = r"C:\Users\pc\AppData\Roaming\FullPOS Cloud\FullPOS Cloud - Sistema de facturacion"

def safe_print_company(name, d):
    if not isinstance(d, dict):
        print(f"{name}: {d}")
        return
    keep = {}
    for k, v in d.items():
        kl = k.lower()
        if any(s in kl for s in ['company', 'rnc', 'phone', 'address', 'logo', 'business', 'hour', 'desc', 'name']):
            keep[k] = v
        elif kl in ('companyid', 'lastcompany', 'selectedcompany', 'currentcompany'):
            keep[k] = v
    print(f"{name}: {json.dumps(keep, ensure_ascii=False)[:1500]}")

# 1) shared_preferences.json
sp_path = os.path.join(base, "shared_preferences.json")
if os.path.exists(sp_path):
    with open(sp_path, "r", encoding="utf-8", errors="replace") as f:
        sp = json.load(f)
    print("SHARED_PREFS KEYS:", sorted(sp.keys()))
    safe_print_company("SHARED_PREFS company-related", sp)
else:
    print("no shared_preferences.json")

# 2) fulltech_offline.db cache entries
db_path = os.path.join(base, "databases", "fulltech_offline.db")
if os.path.exists(db_path):
    con = sqlite3.connect(db_path)
    cur = con.cursor()
    tables = [r[0] for r in cur.execute("SELECT name FROM sqlite_master WHERE type='table'")]
    print("OFFLINE DB TABLES:", tables)
    # find cache-like tables
    for t in tables:
        if any(s in t.lower() for s in ['cache', 'offline', 'outbox', 'pending', 'sync']):
            try:
                cols = [c[1] for c in cur.execute(f"PRAGMA table_info({t})")]
                print(f"TABLE {t} cols={cols}")
                rows = cur.execute(f"SELECT * FROM {t}").fetchall()
                print(f"TABLE {t} rows={len(rows)}")
                for r in rows[:30]:
                    line = json.dumps([str(x)[:300] for x in r], ensure_ascii=False)[:600]
                    if 'company_settings' in line or 'company' in line.lower() or 'FullPOS' in line or 'FULLTECH' in line:
                        print("  ROW:", line)
            except Exception as e:
                print(f"TABLE {t} ERR {e}")
    con.close()
else:
    print("no fulltech_offline.db")
