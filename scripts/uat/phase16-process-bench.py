"""Kill only nonce-bound Flutter test descendants at real sqflite boundaries."""
import ctypes
import argparse
from ctypes import wintypes
import json
import os
import pathlib
import signal
import sqlite3
import subprocess
import time

ROOT = pathlib.Path(__file__).resolve().parents[2]
BANK = ROOT / '.uat/phase16-process-bench'
TEST = 'test/core/offline/phase16_process_worker_test.dart'


def parents():
    class Entry(ctypes.Structure):
        _fields_ = [('size', wintypes.DWORD), ('usage', wintypes.DWORD), ('pid', wintypes.DWORD),
                    ('heap', ctypes.c_size_t), ('module', wintypes.DWORD), ('threads', wintypes.DWORD),
                    ('parent', wintypes.DWORD), ('priority', wintypes.LONG), ('flags', wintypes.DWORD),
                    ('exe', wintypes.WCHAR * 260)]
    api = ctypes.WinDLL('kernel32', use_last_error=True)
    api.CreateToolhelp32Snapshot.restype = wintypes.HANDLE
    api.Process32FirstW.argtypes = [wintypes.HANDLE, ctypes.POINTER(Entry)]
    api.Process32NextW.argtypes = [wintypes.HANDLE, ctypes.POINTER(Entry)]
    api.CloseHandle.argtypes = [wintypes.HANDLE]
    handle = api.CreateToolhelp32Snapshot(2, 0)
    if handle == ctypes.c_void_p(-1).value:
        raise OSError('Cannot verify child process ancestry')
    entry = Entry(); entry.size = ctypes.sizeof(entry); result = {}
    try:
        success = api.Process32FirstW(handle, ctypes.byref(entry))
        while success:
            result[entry.pid] = (entry.parent, entry.exe)
            success = api.Process32NextW(handle, ctypes.byref(entry))
    finally:
        api.CloseHandle(handle)
    return result


def run_child(directory, resume=False):
    fixture = json.loads((directory / 'fixture.json').read_text())
    env = os.environ.copy()
    env.update(FULLPOS_PHASE16_CHILD='true', FULLPOS_PHASE16_NONCE=fixture['nonce'],
               DALEVENTAS_POS_ROOT=str(directory))
    if resume:
        env['FULLPOS_PHASE16_RESUME'] = 'true'
    log = directory / ('resume.log' if resume else 'worker.log')
    with log.open('w', encoding='utf-8') as stream:
        process = subprocess.Popen(['cmd.exe', '/d', '/c', r'C:\src\flutter\bin\flutter.bat',
                                    'test', '--no-pub', TEST, '--plain-name', 'phase16 child', '--reporter', 'expanded'],
                                   cwd=ROOT / 'apps/fulltech_app', env=env, stdout=stream, stderr=subprocess.STDOUT)
        if resume:
            if process.wait(timeout=120) != 0:
                raise RuntimeError(f'Resume failed; inspect {log}')
            return
        marker = directory / 'boundary.json'
        deadline = time.monotonic() + 90
        while not marker.exists() and time.monotonic() < deadline and process.poll() is None:
            time.sleep(0.05)
        if not marker.exists():
            raise RuntimeError(f'No verified kill boundary; inspect {log}; parent PID {process.pid}')
        evidence = json.loads(marker.read_text())
        if evidence['nonce'] != fixture['nonce'] or evidence['pid'] in [os.getpid(), os.getppid(), process.pid]:
            raise RuntimeError('Unsafe process identity')
        tree = parents(); current = evidence['pid']; seen = set()
        if tree.get(current, (0,''))[1].lower() not in ('flutter_tester.exe', 'dart.exe'):
            raise RuntimeError('Unexpected child executable')
        while current != process.pid:
            if current in seen or current not in tree:
                raise RuntimeError('Target is not a descendant of this disposable test')
            seen.add(current); current = tree[current][0]
        os.kill(evidence['pid'], signal.SIGTERM)  # Windows TerminateProcess; no host shutdown
        process.wait(timeout=30)


def verify(directory, committed, migration=False, resumed=False):
    fixture = json.loads((directory / 'fixture.json').read_text())
    database = directory / 'databases/fulltech_offline.db'
    connection = sqlite3.connect(database)
    try:
        assert connection.execute('pragma integrity_check').fetchone()[0] == 'ok'
        counts = {table: connection.execute('select count(*) from ' + table).fetchone()[0]
                  for table in ['offline_sales','offline_sale_items','offline_sale_payments','offline_inventory_intents','pending_actions']}
        economic = int(committed and fixture['kind'] == 'sale')
        assert all(counts[t] == economic for t in counts if t != 'pending_actions'), counts
        assert counts['pending_actions'] == int(committed and not resumed), counts
        if committed and not resumed:
            request, payload = connection.execute('select idempotency_key,payload from pending_actions').fetchone()
            assert request == fixture['operationId'] and json.loads(payload) == fixture['payload']
        if migration:
            with sqlite3.connect(directory / 'databases/migration.db') as migration_db:
                assert migration_db.execute('pragma user_version').fetchone()[0] == 1
                assert migration_db.execute('select id from original').fetchall() == [('preserved',)]
                assert [r[1] for r in migration_db.execute('pragma table_info(original)')] == ['id']
        return counts
    finally:
        connection.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--resume', action='store_true', help='Continue retained fixtures; never recreates them')
    args = parser.parse_args()
    if os.name != 'nt' or (BANK.exists() and not args.resume):
        raise RuntimeError('Windows only; refusing to reuse process evidence')
    if args.resume:
        spec = json.loads((BANK / 'spec.json').read_text())
    else:
        BANK.mkdir()
        spec = [dict(name='sale-'+s, kind='sale', stage=s) for s in list('ABCDEFGHIJKL')]
        spec += [dict(name=k+'-'+s, kind=k, stage=s) for k in ['product','stock'] for s in ['A','F','G','I']]
        (BANK / 'spec.json').write_text(json.dumps(spec))
        subprocess.run(['node', 'scripts/uat/phase16-process-fixtures.cjs', 'setup', str(BANK)], cwd=ROOT, check=True)
    results = []
    for item in spec:
        directory = BANK / item['name']
        if not (directory / 'boundary.json').exists():
            run_child(directory)
        committed = item['stage'] in ['G','H','I','J','L']
        resumed = (directory / 'resumed.json').exists()
        counts = verify(directory, committed, migration=item['stage'] == 'K', resumed=resumed)
        if committed and not resumed:
            run_child(directory, resume=True)
        results.append(dict(**item, committed=committed, countsAfterRecovery=counts, status='PASS'))
        print(json.dumps(results[-1]), flush=True)
    subprocess.run(['node', 'scripts/uat/phase16-process-fixtures.cjs', 'audit', str(BANK)], cwd=ROOT, check=True)
    (ROOT / '.uat/evidence/phase16-process-bench.json').write_text(json.dumps(dict(status='PASS', level='A: process termination, not physical power loss',
        checkpointScope='L is after PASSIVE returned; in-flight checkpoint interruption not claimed', results=results), indent=2))


if __name__ == '__main__':
    main()
