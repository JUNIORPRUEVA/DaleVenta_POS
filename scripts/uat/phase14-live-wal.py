"""Hold a committed WAL while the Phase14 isolated native fixture is installed."""
import hashlib
import json
import pathlib
import sqlite3
import time

bank = pathlib.Path(__file__).resolve().parents[2] / '.uat/phase14-native-bank'
db = bank / 'databases/phase14-live-wal.db'
if db.exists() or (bank / 'wal-finish.signal').exists():
    raise RuntimeError('Refusing to reuse an existing WAL test')
connection = sqlite3.connect(db)
connection.execute('pragma journal_mode=wal')
connection.execute('create table proof (id text primary key, amount integer)')
connection.execute('insert into proof values (?, ?)', ('original', 400))
connection.commit()
paths = [db, pathlib.Path(str(db) + '-wal'), pathlib.Path(str(db) + '-shm')]
hashes = lambda: {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
before = hashes()
(bank / 'wal-ready.json').write_text(json.dumps(before))
for attempt in range(1200):
    if (bank / 'wal-finish.signal').exists():
        break
    time.sleep(0.25)
else:
    raise TimeoutError('Installer completion signal absent')
after = hashes()
assert before == after, 'Installer changed live DB/WAL/SHM'
assert connection.execute('select amount from proof where id=?', ('original',)).fetchone()[0] == 400
(bank / 'wal-result.json').write_text(json.dumps(dict(status='PASS', before=before, after=after, committedAmount=400), indent=2))
connection.close()
print('PASS: committed WAL/SHM unchanged through interrupted install and reinstall')
