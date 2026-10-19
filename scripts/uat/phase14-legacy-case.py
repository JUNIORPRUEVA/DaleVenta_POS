"""Export a supervised legacy case. Read-only SQLite; no network or apply mode."""
import argparse
from contextlib import closing
import hashlib
import json
import pathlib
import re
import sqlite3


def digest(value):
    return hashlib.sha256(value.encode('utf-8')).hexdigest()


def reject_secrets(value):
    """Fail closed, preserving the source rather than redacting its evidence."""
    forbidden_keys = {
        'password', 'passwd', 'pwd', 'accesstoken', 'refreshtoken', 'authorization',
        'apikey', 'xapikey', 'clientsecret', 'jwtsecret', 'privatekey',
        'databaseurl', 'connectionstring', 'cookie', 'setcookie',
    }
    if isinstance(value, dict):
        for key, item in value.items():
            if re.sub(r'[^a-z0-9]', '', str(key).lower()) in forbidden_keys:
                raise ValueError('Secret-bearing operation cannot be exported')
            reject_secrets(item)
    elif isinstance(value, list):
        for item in value:
            reject_secrets(item)
    elif isinstance(value, str):
        patterns = (
            r'\bbearer\s+\S+', r'-----BEGIN [A-Z ]*PRIVATE KEY-----',
            r'\bpostgres(?:ql)?://', r'\b[a-z][a-z0-9+.-]*://[^\s/:]+:[^\s@]+@',
            r'\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+',
            r'\b(?:password|passwd|access[_-]?token|refresh[_-]?token|api[_-]?key|jwt[_-]?secret)\s*[:=]',
        )
        if any(re.search(pattern, value, re.IGNORECASE) for pattern in patterns):
            raise ValueError('Secret-bearing operation cannot be exported')
        try:
            structured = json.loads(value)
        except (ValueError, TypeError):
            return
        if isinstance(structured, (dict, list)):
            reject_secrets(structured)


def make_case(row, company_id, user_id):
    reject_secrets(row)
    if row['type'] != 'sales.create':
        raise ValueError('Only sales.create is supported; quotes are excluded')
    if row['company_id'] != company_id or row['user_id'] != user_id:
        raise ValueError('Company/user scope mismatch')
    payload = json.loads(row['payload'])
    operation = payload.get('clientRequestId')
    if not operation or row['idempotency_key'] != operation:
        raise ValueError('Missing or divergent immutable operation identity')
    if payload.get('originCashSessionId') or payload.get('cashSessionId'):
        raise ValueError('Explicit session present; use the normal conflict workflow')
    for field, expected in [('companyId', company_id), ('userId', user_id)]:
        if field in payload and payload[field] != expected:
            raise ValueError('Payload scope mismatch')
    return {
        'format': 'fullpos.legacy-supervised-case.v1',
        'status': 'BLOCKED_PENDING_INDEPENDENT_EVIDENCE',
        'companyId': company_id, 'userId': user_id,
        'clientRequestId': operation,
        'originalRow': row, 'originalPayloadSha256': digest(row['payload']),
        'originalRowSha256': digest(json.dumps(row, sort_keys=True, ensure_ascii=False)),
        'proposedOriginCashSessionId': None,
        'supervisorReview': {
            'reviewer': None, 'independentEvidenceReference': None,
            'evidenceSha256': None, 'decision': None,
            'requiredChecks': [
                'Prove a per-operation link to the ORIGINAL session using independent evidence',
                'Do not select the current open session or match solely by time',
                'Reconcile company + clientRequestId remotely before any send; compare full economics',
                'Verify selected session belongs to the same company and user',
                'Closed original session requires a separate supervised accounting decision',
                'Preserve this row, payload and idempotency key; never create a replacement sale identity',
                'Re-read and compare original row hash immediately before an authorized recovery',
            ],
        },
        'execution': 'NONE: this exporter cannot authorize, requeue, rewrite or send a sale',
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--database', required=True, type=pathlib.Path)
    parser.add_argument('--action-id', required=True)
    parser.add_argument('--company-id', required=True)
    parser.add_argument('--user-id', required=True)
    parser.add_argument('--output', required=True, type=pathlib.Path)
    args = parser.parse_args()
    uat = pathlib.Path(__file__).resolve().parents[2] / '.uat'
    database = args.database.resolve(strict=True)
    output = args.output.resolve()
    if not database.is_relative_to(uat) or not output.is_relative_to(uat):
        raise ValueError('Only isolated .uat paths are allowed')
    if 'windows-app-root' in [part.casefold() for part in database.parts]:
        raise ValueError('Manual UAT is protected: use a consistent backup')
    with closing(sqlite3.connect(database.as_uri() + '?mode=ro', uri=True)) as connection:
        connection.row_factory = sqlite3.Row
        connection.execute('pragma query_only=on')
        rows = connection.execute('select * from pending_actions where id=?', (args.action_id,)).fetchall()
        if len(rows) != 1:
            raise ValueError('Exactly one original operation is required')
        case = make_case(dict(rows[0]), args.company_id, args.user_id)
    # Exclusive creation prevents replacing a reviewed case or any source database.
    with output.open('x', encoding='utf-8') as stream:
        json.dump(case, stream, ensure_ascii=False, indent=2)
    print(json.dumps({'status': case['status'], 'originalPayloadSha256': case['originalPayloadSha256'],
                      'networkRequests': 0, 'mutations': 0}))


if __name__ == '__main__':
    main()
