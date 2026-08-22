# READ-ONLY: find 'FullPOS Cloud' in local data + auth snapshot + all company_settings caches
import json, os, sqlite3

base = r"C:\Users\pc\AppData\Roaming\FullPOS Cloud\FullPOS Cloud - Sistema de facturacion"

def redact_company(obj):
    if not isinstance(obj, dict):
        return obj
    out = {}
    for k, v in obj.items():
        kl = k.lower()
        if any(s in kl for s in ['password', 'token', 'hash', 'pin', 'secret', 'apikey', 'api_key']):
            out[k] = '[REDACTED]'
        else:
            out[k] = redact_company(v) if isinstance(v, (dict, list)) else v
    return out

# 1) auth snapshot company fields
sp_path = os.path.join(base, "shared_preferences.json")
with open(sp_path, "r", encoding="utf-8", errors="replace") as f:
    sp = json.load(f)
snap = sp.get("flutter.authUserSnapshot")
print("AUTH SNAPSHOT type:", type(snap).__name__)
if isinstance(snap, str):
    try:
        snap = json.loads(snap)
    except Exception:
        pass
if isinstance(snap, dict):
    keys = [k for k in snap.keys() if any(s in k.lower() for s in ['company', 'name', 'role', 'email', 'id', 'tenant'])]
    print("AUTH SNAPSHOT company-related:", json.dumps({k: snap[k] for k in keys}, ensure_ascii=False)[:1200])
    print("AUTH SNAPSHOT full (redacted):", json.dumps(redact_company(snap), ensure_ascii=False)[:2500])
else:
    print("AUTH SNAPSHOT value:", str(snap)[:600])

# 2) search ALL cache entries for 'FullPOS Cloud' and company_settings keys
db_path = os.path.join(base, "databases", "fulltech_offline.db")
con = sqlite3.connect(db_path)
cur = con.cursor()
rows = cur.execute("SELECT cache_key, payload, updated_at FROM cache_entries").fetchall()
print("--- company_settings_cache entries ---")
for k, p, ts in rows:
    if 'company_settings_cache' in k:
        print("KEY:", k)
        try:
            d = json.loads(p)
            print("  companyName:", d.get('companyName'), "| rnc:", d.get('rnc'), "| phone:", d.get('phone'), "| ts:", ts)
        except Exception as e:
            print("  (payload parse err)", str(p)[:200])
print("--- entries containing 'FullPOS Cloud' ---")
found = 0
for k, p, ts in rows:
    if 'FullPOS Cloud' in p:
        found += 1
        print("KEY:", k, "| ts:", ts, "| payload[:220]:", p[:220])
print("entries with FullPOS Cloud:", found)
print("--- entries containing 'FullPOS Cloud' in company_settings ---")
for k, p, ts in rows:
    if 'company_settings' in k and 'FullPOS Cloud' in p:
        print("KEY:", k, "| ts:", ts)
con.close()
