#!/usr/bin/env python3
"""Confirm the exact upload and existing internal tester access; fail closed."""
import json
import os
from pathlib import Path
import time
from urllib.parse import urlencode
from urllib.request import Request, urlopen
from urllib.error import HTTPError

BASE = 'https://api.appstoreconnect.apple.com/v1/'


def main():
    headers = {'Authorization': 'Bearer ' + os.environ['CA_ASC_TOKEN'],
               'Content-Type': 'application/json'}
    bundle = os.environ['CA_BUNDLE']
    version = os.environ['CA_BUILD']
    output = Path(os.environ['RUNNER_TEMP']) / 'ct-arcade-testflight-status.json'
    status = {'bundle': bundle, 'version': version, 'commit': os.environ['CA_SOURCE'],
              'processing_state': 'NOT_INDEXED', 'internal_tester_access': False}

    def save():
        output.write_text(json.dumps(status, indent=2) + '\n')

    def apple(path, filters=None, data=None):
        url = BASE + path + ('?' + urlencode(filters) if filters else '')
        payload = json.dumps({'data': data}).encode() if data is not None else None
        try:
            with urlopen(Request(url, data=payload, headers=headers), timeout=30) as response:
                return json.load(response) if response.status != 204 else {}
        except HTTPError as error:
            # Keep authentication and tester identities out of logs/artifacts.
            raise RuntimeError(f'Apple status/assignment request failed: HTTP {error.code}, {path}') from None

    def records(path, filters=None):
        filters = {**(filters or {}), 'limit': 200}
        result = []
        for _ in range(50):
            response = apple(path, filters)
            result.extend(response['data'])
            cursor_url = response.get('links', {}).get('next')
            if not cursor_url:
                return result
            # Apple pagination remains confined to the same endpoint and origin.
            from urllib.parse import urlsplit, parse_qsl
            cursor = urlsplit(cursor_url)
            if cursor.scheme != 'https' or cursor.netloc != 'api.appstoreconnect.apple.com' or cursor.path != '/v1/' + path:
                raise RuntimeError('Unexpected Apple pagination URL')
            filters = dict(parse_qsl(cursor.query))
        raise RuntimeError('Apple pagination exceeded verification limit')

    def internal_access(app_id, build_id):
        groups = records('betaGroups', {'filter[app]': app_id})
        internal = [g for g in groups if g['attributes'].get('isInternalGroup')]
        if not internal:
            status['blocker'] = 'CT Arcade needs an internal tester group in App Store Connect.'
            return False
        candidates = []
        for group in internal:
            group_id = group['id']
            testers = records(f'betaGroups/{group_id}/betaTesters')
            if not testers:
                continue
            members = records(f'betaGroups/{group_id}/relationships/builds')
            if group['attributes'].get('hasAccessToAllBuilds') or any(b['id'] == build_id for b in members):
                status.update(group_id=group_id, internal_tester_count=len(testers))
                return True
            candidates.append((group_id, len(testers)))
        # Reuse the app's existing populated group only when unambiguous.
        if len(candidates) != 1:
            status['blocker'] = 'No unambiguous populated CT Arcade internal tester group.'
            return False
        group_id, count = candidates[0]
        apple(f'builds/{build_id}/relationships/betaGroups', data=[{'type': 'betaGroups', 'id': group_id}])
        for attempt in range(5):
            members = records(f'betaGroups/{group_id}/relationships/builds')
            if any(b['id'] == build_id for b in members):
                status.update(group_id=group_id, internal_tester_count=count)
                return True
            if attempt < 4:
                time.sleep(4)
        status['blocker'] = 'Apple has not confirmed group assignment.'
        return False

    save()
    try:
        apps = records('apps', {'filter[bundleId]': bundle})
        if len(apps) != 1:
            raise RuntimeError('Expected one independent CT Arcade app record')
        app_id = apps[0]['id']
        status['app_id'] = app_id
        for attempt in range(36):
            response = apple('builds', {'filter[app]': app_id, 'filter[version]': version,
                                      'include': 'buildBetaDetail', 'limit': 5})
            builds = response['data']
            if len(builds) > 1:
                raise RuntimeError('Ambiguous CT Arcade build number')
            if builds:
                build = builds[0]
                state = build['attributes']['processingState']
                detail_id = (build.get('relationships', {}).get('buildBetaDetail', {}).get('data') or {}).get('id')
                details = [d for d in response.get('included', [])
                           if d['type'] == 'buildBetaDetails' and d['id'] == detail_id]
                beta = details[0]['attributes']['internalBuildState'] if len(details) == 1 else 'UNKNOWN'
                status.update(build_id=build['id'], processing_state=state, internal_build_state=beta)
                print(f'CT Arcade {version}: processing={state}; internal TestFlight={beta}', flush=True)
                if state in {'INVALID', 'FAILED'} or beta in {'MISSING_EXPORT_COMPLIANCE', 'PROCESSING_EXCEPTION', 'IN_EXPORT_COMPLIANCE_REVIEW', 'EXPIRED'}:
                    raise RuntimeError('Apple build processing or export compliance requires attention')
                if state == 'VALID' and beta in {'READY_FOR_BETA_TESTING', 'IN_BETA_TESTING'}:
                    status['internal_tester_access'] = internal_access(app_id, build['id'])
                    if not status['internal_tester_access']:
                        raise RuntimeError(status.get('blocker', 'Internal tester access unconfirmed'))
                    save()
                    message = f'CT Arcade build **{version}**: Apple processing **VALID**, internal TestFlight **{beta}**, access confirmed for **{status["internal_tester_count"]}** existing internal tester(s).'
                    with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as summary:
                        summary.write(message + '\n')
                    print(message)
                    return
            else:
                print(f'CT Arcade {version}: awaiting Apple indexing', flush=True)
            save()
            if attempt < 35:
                time.sleep(20)
        raise RuntimeError('Apple processing/tester availability not confirmed within verification window')
    except Exception as error:
        status['blocker'] = str(error)
        raise
    finally:
        save()


if __name__ == '__main__':
    main()
