"""Disposable preservation fixture; not a historical client or business replay."""
import ctypes
import hashlib
import json
import os
from pathlib import Path
import sqlite3
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]
BANK = ROOT / '.uat/phase17-update-final-bank'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def native_query(library, database, sql):
    library.sqlite3_open_v2.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_void_p), ctypes.c_int, ctypes.c_char_p]
    library.sqlite3_prepare_v2.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int, ctypes.POINTER(ctypes.c_void_p), ctypes.c_void_p]
    library.sqlite3_step.argtypes = [ctypes.c_void_p]
    library.sqlite3_column_text.argtypes = [ctypes.c_void_p, ctypes.c_int]
    library.sqlite3_column_text.restype = ctypes.c_char_p
    library.sqlite3_finalize.argtypes = [ctypes.c_void_p]
    library.sqlite3_close.argtypes = [ctypes.c_void_p]
    handle = ctypes.c_void_p()
    statement = ctypes.c_void_p()
    assert library.sqlite3_open_v2(str(database).encode(), ctypes.byref(handle), 1, None) == 0
    try:
        assert library.sqlite3_prepare_v2(handle, sql.encode(), -1, ctypes.byref(statement), None) == 0
        try:
            assert library.sqlite3_step(statement) == 100
            return library.sqlite3_column_text(statement, 0).decode()
        finally:
            library.sqlite3_finalize(statement)
    finally:
        library.sqlite3_close(handle)


def main():
    assert len(sys.argv) == 2 and len(sys.argv[1]) == 32
    nonce = sys.argv[1]
    database = BANK / 'databases/fulltech_offline.db'
    assert BANK.is_dir() and not database.exists()
    source = ROOT / '.uat/phase13-update-bench/phase11-flutter-client-update/databases/fulltech_offline.db'
    original = sqlite3.connect(source.as_uri() + '?mode=ro', uri=True)
    db = sqlite3.connect(database)
    original.backup(db)
    original.close()
    assert db.execute('pragma integrity_check').fetchone()[0] == 'ok'
    assert db.execute('select count(*) from pending_actions').fetchone()[0] == 2
    db.execute('pragma journal_mode=wal')
    db.execute('pragma synchronous=full')
    db.execute('pragma wal_autocheckpoint=0')
    company, user, product, turn = [str(uuid.uuid4()) for _ in range(4)]
    now = int(time.time() * 1000)
    types = ['catalog.products.create', 'catalog.products.stock', 'sales.create',
             'quotes.create', 'catalog.products.update', 'sales.attempt']
    ids = [str(uuid.uuid4()) for _ in types]
    for index, kind in enumerate(types):
        payload = dict(fixtureOnly=True, productId=product, operationId=ids[index],
                       clientRequestId=ids[index], originCashSessionId=turn,
                       companyId=company, userId=user, dependsOn=ids[:index],
                       delta=20 if index == 1 else 0, qty=4 if index == 2 else 0)
        status = 'requires_action' if index == 5 else 'failed' if index == 4 else 'pending'
        db.execute('''insert into pending_actions
          (id,type,scope,company_id,user_id,terminal_id,entity_id,idempotency_key,
           payload,status,attempts,permanent,created_at,updated_at,next_attempt_at)
          values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)''',
          (ids[index], kind, 'phase17-disposable', company, user, 'phase17-terminal',
           product, ids[index], json.dumps(payload), status, 1 if index == 4 else 0,
           0, now, now, now + 60000 if index == 4 else None))
    db.execute('insert into cache_entries values (?,?,?)', ('phase17-live-wal', json.dumps({'committed': True}), now))
    db.commit()
    expected = sorted(db.execute('select * from pending_actions').fetchall(), key=repr)
    assert len(expected) == 8
    files = [database, Path(str(database) + '-wal'), Path(str(database) + '-shm')]
    assert all(file.exists() for file in files) and files[1].stat().st_size > 32
    ready = dict(pid=os.getpid(), nonce=nonce, pending=8,
                 source='Synthetic fixture only; no manual/customer rows',
                 files={file.name: dict(sha256=digest(file), size=file.stat().st_size) for file in files})
    partial = BANK / 'fixture-ready.partial'
    partial.write_text(json.dumps(ready, indent=2))
    partial.rename(BANK / 'fixture-ready.json')
    try:
        deadline = time.monotonic() + 180
        while not (BANK / 'fixture-stop.marker').exists():
            if time.monotonic() > deadline:
                raise TimeoutError('Installer fixture owner timed out')
            time.sleep(.1)
        assert sorted(db.execute('select * from pending_actions').fetchall(), key=repr) == expected
        assert db.execute('pragma integrity_check').fetchone()[0] == 'ok'
        assert db.execute("select count(*) from cache_entries where cache_key='phase17-live-wal'").fetchone()[0] == 1
    finally:
        db.close()
    # Read through the final candidate's actual DLL after WAL owner closes.
    native = ctypes.CDLL(str(BANK / 'app/sqlite3.dll'))
    native.sqlite3_libversion.restype = ctypes.c_char_p
    assert native.sqlite3_libversion().decode() == '3.52.0'
    assert native_query(native, database, 'pragma integrity_check') == 'ok'
    assert native_query(native, database, 'select count(*) from pending_actions') == '8'
    (BANK / 'fixture-result.json').write_text(json.dumps(dict(status='PASS', exactPendingRowsUnchanged=8,
      liveWalCommittedRowPreserved=True, candidateNativeVersion='3.52.0', candidateNativeIntegrity='ok',
      scope='Native DLL read, not Flutter GUI or synchronization of these synthetic payloads'), indent=2))


if __name__ == '__main__':
    main()
