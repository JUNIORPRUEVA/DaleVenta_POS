"""Bounded SQLite primitive bench on disposable copies. No host power/disk faults."""
from contextlib import closing
import ctypes
from ctypes import wintypes
import hashlib
import json
import os
import pathlib
import shutil
import sqlite3
import statistics
import time

ROOT = pathlib.Path(__file__).resolve().parents[2]
BANK = ROOT / '.uat/phase16-storage-chaos'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    if BANK.exists():
        raise RuntimeError('Refusing to overwrite storage evidence')
    BANK.mkdir()
    results = []
    source = BANK / 'source.db'
    with closing(sqlite3.connect(source)) as db:
        db.execute('pragma journal_mode=wal'); db.execute('pragma synchronous=full')
        db.execute('pragma wal_autocheckpoint=0')
        db.execute('create table economic(id text primary key, amount integer, payload text)')
        db.execute('insert into economic values (?,?,?)', ('original',400,'x'*12000)); db.commit()
        db.execute('pragma wal_checkpoint(truncate)')
        db.execute('insert into economic values (?,?,?)', ('live-wal',400,'y'*12000)); db.commit()
        assert pathlib.Path(str(source)+'-wal').stat().st_size > 0
        backup = BANK / 'verified-backup.db'
        with closing(sqlite3.connect(backup)) as copy:
            db.backup(copy)
            assert copy.execute('pragma integrity_check').fetchone()[0] == 'ok'
            assert copy.execute('select count(*) from economic').fetchone()[0] == 2
        manifest = dict(sha256=sha(backup), rows=2, method='SQLite Backup API')
        (BANK / 'backup-manifest.json').write_text(json.dumps(manifest))
        results.append(dict(id='backup-live-wal',status='PASS', rows=2))
        for kind in ['header','page','truncate']:
            target = BANK / f'corrupt-{kind}.db'
            shutil.copy2(backup,target)
            with target.open('r+b') as stream:
                if kind == 'header': stream.write(b'NOT A DATABASE!!')
                elif kind == 'page': stream.seek(4096); stream.write(b'\xff'*128)
                else: stream.truncate(1024)
            damaged = sha(target)
            try:
                with closing(sqlite3.connect(target.as_uri()+'?mode=ro',uri=True)) as broken:
                    integrity = broken.execute('pragma integrity_check').fetchall()
                detected = integrity != [('ok',)]
                code = 'integrity_check failed'
            except sqlite3.DatabaseError as error:
                detected = True; code = error.sqlite_errorname
            assert detected and sha(target)==damaged
            results.append(dict(id='corruption-'+kind,status='PASS_DETECTED', sqliteResult=code, originalCopyPreserved=True))
        # Corrupt only a separate WAL clone. This is arbitrary media corruption,
        # not a claim that FULL acknowledged an unflushed physical commit.
        torn = BANK / 'torn-wal.db'
        shutil.copy2(source,torn)
        wal = pathlib.Path(str(torn)+'-wal'); shutil.copy2(pathlib.Path(str(source)+'-wal'),wal)
        with wal.open('r+b') as stream: stream.truncate(max(32,wal.stat().st_size-2048))
        with closing(sqlite3.connect(torn)) as recovered:
            rows = recovered.execute('select count(*) from economic').fetchone()[0]
            integrity = recovered.execute('pragma integrity_check').fetchone()[0]
        results.append(dict(id='torn-wal',status='LIMIT_DOCUMENTED', recoveredRows=rows, knownOriginalRows=2,
            integrityCheck=integrity, conclusion='A coherent older state can pass integrity_check; arbitrary WAL destruction needs independent verified evidence/backup'))
        assert sha(backup)==manifest['sha256']
        invalid = BANK / 'incomplete-backup.db'; shutil.copy2(backup,invalid)
        with invalid.open('r+b') as stream: stream.truncate(1024)
        assert sha(invalid)!=manifest['sha256']
        results.append(dict(id='incomplete-backup',status='PASS_REJECTED_BY_MANIFEST'))
        reader = sqlite3.connect(source)
        reader.execute('begin'); reader.execute('select count(*) from economic').fetchone()
        before_wal = pathlib.Path(str(source)+'-wal').stat().st_size
        latencies = []
        started_cpu = time.process_time()
        for i in range(500):
            start=time.perf_counter()
            db.execute('insert into economic values (?,?,?)',(f'load-{i}',100,'fixture'))
            db.commit(); latencies.append((time.perf_counter()-start)*1000)
        pinned = db.execute('pragma wal_checkpoint(passive)').fetchone()
        assert pinned[1]>pinned[2]
        peak_wal = pathlib.Path(str(source)+'-wal').stat().st_size
        assert peak_wal<16*1024*1024
        reader.rollback(); reader.close()
        completed = db.execute('pragma wal_checkpoint(truncate)').fetchone()
        assert completed[0]==0
        assert db.execute('select count(*) from economic').fetchone()[0]==502
        results.append(dict(id='reader-pinned-checkpoint',status='PASS',beforeWalBytes=before_wal,peakWalBytes=peak_wal,
            pinnedCheckpoint=list(pinned),completedCheckpoint=list(completed),
            fullCommitMilliseconds=dict(p50=statistics.median(latencies),p95=sorted(latencies)[474],max=max(latencies)),cpuSeconds=time.process_time()-started_cpu,
            scope='500 primitive FULL commits, Python driver; not POS throughput or power-loss proof'))
        db.execute('begin immediate')
        with closing(sqlite3.connect(source,timeout=.15)) as contender:
            start=time.perf_counter()
            try: contender.execute("insert into economic values ('busy',1,'fixture')")
            except sqlite3.OperationalError as error:
                assert error.sqlite_errorcode==sqlite3.SQLITE_BUSY
                results.append(dict(id='busy-timeout',status='PASS',sqliteResult=error.sqlite_errorname,elapsedMilliseconds=(time.perf_counter()-start)*1000))
            else: raise AssertionError('Expected SQLITE_BUSY')
        db.rollback()
        cursor=db.execute('select * from economic'); cursor.fetchone()
        try: db.execute('drop table economic')
        except sqlite3.OperationalError as error:
            assert error.sqlite_errorcode==sqlite3.SQLITE_LOCKED
            results.append(dict(id='locked-cursor',status='PASS',sqliteResult=error.sqlite_errorname))
        else: raise AssertionError('Expected SQLITE_LOCKED')
        cursor.close()
    with closing(sqlite3.connect(source.as_uri()+'?mode=ro',uri=True)) as read_only:
        try: read_only.execute("insert into economic values ('readonly',1,'fixture')")
        except sqlite3.OperationalError as error:
            assert error.sqlite_errorcode==sqlite3.SQLITE_READONLY
            results.append(dict(id='readonly',status='PASS',sqliteResult=error.sqlite_errorname))
        else: raise AssertionError('Expected SQLITE_READONLY')
    if os.name=='nt':
        locked=BANK/'blocked.dll'; locked.write_bytes(b'disposable rename fixture')
        replacement=BANK/'replacement.dll'; replacement.write_bytes(b'replacement fixture')
        api=ctypes.WinDLL('kernel32',use_last_error=True)
        api.CreateFileW.argtypes=[wintypes.LPCWSTR,wintypes.DWORD,wintypes.DWORD,ctypes.c_void_p,wintypes.DWORD,wintypes.DWORD,wintypes.HANDLE]
        api.CreateFileW.restype=wintypes.HANDLE; api.CloseHandle.argtypes=[wintypes.HANDLE]
        handle=api.CreateFileW(str(locked),0x80000000,0,None,3,0,None)
        assert handle!=ctypes.c_void_p(-1).value
        try:
            try: os.replace(replacement,locked)
            except PermissionError as error:
                results.append(dict(id='win32-rename-blocked',status='PASS',winerror=error.winerror,scope='Real file sharing lock on disposable DLL-named file, not Defender/quarantine simulation'))
            else: raise AssertionError('Expected sharing violation')
        finally: api.CloseHandle(handle)
        assert locked.read_bytes()==b'disposable rename fixture'
    result=dict(status='PASS_WITH_DOCUMENTED_LIMIT', sqliteVersion=sqlite3.sqlite_version,
        level='SQLite primitives and disposable corruption, not a physical outage',results=results)
    (ROOT/'.uat/evidence/phase16-storage-chaos.json').write_text(json.dumps(result,indent=2))
    print(json.dumps(result,indent=2))


if __name__=='__main__': main()
