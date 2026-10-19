import importlib.util
from contextlib import closing
import json
import pathlib
import sqlite3
import subprocess
import sys
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('legacy_case', pathlib.Path(__file__).with_name('phase14-legacy-case.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class LegacyCaseTest(unittest.TestCase):
    def row(self, **changes):
        row = dict(id='sales.create:original', type='sales.create', company_id='company-a',
                   user_id='user-a', idempotency_key='sale_req_original', status='failed',
                   attempts=4, payload=json.dumps(dict(clientRequestId='sale_req_original',
                   saleOccurredAt='2026-10-13T12:00:00Z', items=[dict(productId='p', qty=4)])))
        return row | changes

    def test_original_preserved_without_selecting_session(self):
        row = self.row()
        before = row.copy()
        case = module.make_case(row, 'company-a', 'user-a')
        self.assertEqual(row, before)
        self.assertEqual(case['originalRow'], before)
        self.assertIsNone(case['proposedOriginCashSessionId'])
        self.assertEqual(case['clientRequestId'], 'sale_req_original')
        self.assertEqual(case['status'], 'BLOCKED_PENDING_INDEPENDENT_EVIDENCE')

    def test_cross_tenant_and_user_rejected(self):
        for row in [self.row(company_id='company-b'), self.row(user_id='user-b'),
                    self.row(payload=json.dumps(dict(clientRequestId='sale_req_original', companyId='company-b')))]:
            with self.assertRaises(ValueError):
                module.make_case(row, 'company-a', 'user-a')

    def test_quotes_missing_identity_and_existing_origin_rejected(self):
        for row in [self.row(type='quotes.create'), self.row(idempotency_key='different'),
                    self.row(payload='{}'), self.row(payload=json.dumps(dict(
                        clientRequestId='sale_req_original', originCashSessionId='session')))]:
            with self.assertRaises(ValueError):
                module.make_case(row, 'company-a', 'user-a')

    def test_payload_changes_alter_evidence_hash(self):
        first = module.make_case(self.row(), 'company-a', 'user-a')
        second = module.make_case(self.row(payload=self.row()['payload'] + ' '), 'company-a', 'user-a')
        self.assertNotEqual(first['originalPayloadSha256'], second['originalPayloadSha256'])

    def test_secret_bearing_rows_are_rejected_without_exporting_values(self):
        cases = [
            self.row(payload=json.dumps(dict(clientRequestId='sale_req_original',
                                            metadata=dict(refreshToken='fixture-secret')))),
            self.row(error='Authorization: Bearer fixture-secret'),
            self.row(error='postgresql://fixture:fixture@localhost/fixture'),
            self.row(payload=json.dumps(dict(clientRequestId='sale_req_original',
                                            note='-----BEGIN PRIVATE KEY-----'))),
        ]
        for row in cases:
            with self.subTest(type=list(row.keys())):
                with self.assertRaisesRegex(ValueError, 'Secret-bearing'):
                    module.make_case(row, 'company-a', 'user-a')

    def test_cli_reads_sqlite_without_mutation_and_never_overwrites_case(self):
        uat = pathlib.Path(__file__).resolve().parents[2] / '.uat'
        with tempfile.TemporaryDirectory(prefix='phase14-case-test-', dir=uat) as directory:
            database = pathlib.Path(directory) / 'fixture.db'
            output = pathlib.Path(directory) / 'case.json'
            row = self.row()
            with closing(sqlite3.connect(database)) as connection:
                connection.execute('create table pending_actions (id text, type text, company_id text, '
                                   'user_id text, idempotency_key text, status text, attempts integer, payload text)')
                connection.execute('insert into pending_actions values (?,?,?,?,?,?,?,?)', tuple(row.values()))
                connection.commit()
            before = database.read_bytes()
            command = [sys.executable, str(pathlib.Path(__file__).with_name('phase14-legacy-case.py')),
                       '--database', str(database), '--action-id', row['id'], '--company-id', 'company-a',
                       '--user-id', 'user-a', '--output', str(output)]
            first = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(first.returncode, 0, first.stderr)
            exported = output.read_bytes()
            second = subprocess.run(command, capture_output=True, text=True)
            self.assertNotEqual(second.returncode, 0)
            self.assertEqual(output.read_bytes(), exported)
            self.assertEqual(database.read_bytes(), before)

    def test_cli_secret_rejection_creates_no_output_and_prints_no_secret(self):
        uat = pathlib.Path(__file__).resolve().parents[2] / '.uat'
        with tempfile.TemporaryDirectory(prefix='phase15-secret-test-', dir=uat) as directory:
            database = pathlib.Path(directory) / 'fixture.db'
            output = pathlib.Path(directory) / 'must-not-exist.json'
            sentinel = 'phase15-fake-credential-sentinel'
            row = self.row(payload=json.dumps(dict(clientRequestId='sale_req_original',
                                                 metadata={'X-API-Key': sentinel})))
            with closing(sqlite3.connect(database)) as connection:
                connection.execute('create table pending_actions (id text, type text, company_id text, '
                                   'user_id text, idempotency_key text, status text, attempts integer, payload text)')
                connection.execute('insert into pending_actions values (?,?,?,?,?,?,?,?)', tuple(row.values()))
                connection.commit()
            before = database.read_bytes()
            command = [sys.executable, str(pathlib.Path(__file__).with_name('phase14-legacy-case.py')),
                       '--database', str(database), '--action-id', row['id'], '--company-id', 'company-a',
                       '--user-id', 'user-a', '--output', str(output)]
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Secret-bearing', result.stderr)
            self.assertNotIn(sentinel, result.stdout + result.stderr)
            self.assertFalse(output.exists())
            self.assertEqual(database.read_bytes(), before)


if __name__ == '__main__':
    unittest.main()
