#!/usr/bin/env python3
"""Compare host-collected synthetic pre/post artifacts after real OS termination.

Usage: python3 tool/compare_process_evidence.py PRE POST HOST
HOST is a private JSON evidence record with run, case, oldPid, newPid,
killSucceeded, oldPidAbsent, noReinstallBetweenKillAndRelaunch, and actual platform/build/date. It must be filled
from observed host commands, not inferred from the app's report.
"""
import base64
import hashlib
import json
import sys
from pathlib import Path


def compare(pre, post, host):
    for field in ('run', 'case'):
        if not pre[field] == post[field] == host[field]:
            raise ValueError('Mismatched run/case')
    if pre['case'] not in ('before', 'committed', 'visible'):
        raise ValueError('Unknown process case')
    if host['killSucceeded'] is not True or host['oldPidAbsent'] is not True:
        raise ValueError('OS termination not established')
    if host.get('noReinstallBetweenKillAndRelaunch') is not True:
        raise ValueError('Same-install relaunch not established')
    if not host['oldPid'] or not host['newPid'] or host['oldPid'] == host['newPid']:
        raise ValueError('Distinct old/new app processes required')
    for field in ('platform', 'build', 'date'):
        if not host.get(field):
            raise ValueError(f'Missing host evidence: {field}')
    if pre['operationId'] != post['operationId']:
        raise ValueError('Draft operation identity changed')
    if post['result'] != 'verified-after-relaunch':
        raise ValueError('Post-relaunch verification missing')
    if post['eventCount'] != 1 or post['outboxCount'] != 1:
        raise ValueError('Event/outbox count mismatch')
    if pre['case'] != 'before' and (pre['eventCount'] != 1 or pre['outboxCount'] != 1):
        raise ValueError('Pre-termination commit count mismatch')
    for field in ('transportBase64', 'payloadBase64'):
        actual = base64.b64decode(post[field], validate=True)
        if pre['case'] != 'before' and actual != base64.b64decode(pre[field], validate=True):
            raise ValueError(f'Exact signed bytes changed: {field}')
    if pre['case'] != 'before' and pre['eventId'] != post['eventId']:
        raise ValueError('Committed event identity changed')
    if pre['case'] == 'visible' and pre.get('savedVisible') is not True:
        raise ValueError('Visible saved receipt not established')
    return {
        'run': post['run'], 'case': post['case'], 'platform': host['platform'],
        'build': host['build'], 'date': host['date'],
        'operationId': post['operationId'], 'eventId': post['eventId'],
        'transportSha256': hashlib.sha256(base64.b64decode(post['transportBase64'])).hexdigest(),
        'payloadSha256': hashlib.sha256(base64.b64decode(post['payloadBase64'])).hexdigest(),
        'eventCount': 1, 'outboxCount': 1, 'result': 'passed',
        'scope': 'logical stores on the recorded device; not two-phone camera acceptance',
    }


if __name__ == '__main__':
    if len(sys.argv) != 4:
        raise SystemExit(__doc__)
    print(json.dumps(compare(*(json.loads(Path(p).read_text()) for p in sys.argv[1:])), indent=2))
