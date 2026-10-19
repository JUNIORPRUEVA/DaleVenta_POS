"""Keep committed WAL/SHM live while the isolated UAT installer replaces app/."""
import hashlib
import json
import pathlib
import sqlite3
import time
import argparse

parser = argparse.ArgumentParser()
parser.add_argument('--run', default='1')
run = parser.parse_args().run
if not run.isalnum():
    raise ValueError('Invalid fixture run identifier')
root = pathlib.Path(__file__).resolve().parents[2]
bench = root / '.uat/phase13-update-bench/phase11-flutter-client-update'
database = bench / f'databases/phase13-wal-proof-{run}.db'
if database.exists():
    raise RuntimeError('WAL proof already exists; refusing to overwrite')
connection = sqlite3.connect(database)
connection.execute('pragma journal_mode=wal')
connection.execute('create table committed_evidence (id text primary key, amount integer)')
connection.execute('insert into committed_evidence values (?, ?)', ('phase13-committed', 400))
connection.commit()
paths = [database, pathlib.Path(str(database) + '-wal'), pathlib.Path(str(database) + '-shm')]
digest = lambda: {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}
before = digest()
print('WAL fixture ready; committed row retained with connection open', flush=True)
signal = root / f'.uat/evidence/phase13-wal-finish-{run}.signal'
for attempt in range(3600):
    if signal.exists():
        break
    time.sleep(0.25)
else:
    raise TimeoutError('Installer verification signal did not arrive')
after = digest()
assert before == after, 'Installer changed live database/WAL/SHM bytes'
assert connection.execute('select amount from committed_evidence where id=?', ('phase13-committed',)).fetchone()[0] == 400
result = {'status': 'PASS', 'committedAmount': 400, 'hashesBefore': before, 'hashesAfter': after,
          'scope': 'Separate live SQLite WAL fixture across real UAT installer; interrupted install is separate evidence'}
(root / '.uat/evidence/phase13-live-wal.json').write_text(json.dumps(result, indent=2))
connection.close()
print(json.dumps(result), flush=True)
