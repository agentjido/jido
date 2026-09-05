"""Verify migration planning records against local immutable Git inputs.

Run from any directory with Python 3. This command does not run Mix or change
source code. It writes evidence/plan-checks.json after all checks pass.
"""

import collections
import csv
import hashlib
import io
import json
from pathlib import Path
import re
import subprocess
import tarfile


PLAN = Path(__file__).resolve().parent
CORE = PLAN.parent.parent


def read_json(path):
    return json.loads(path.read_text())


def git(root, *args):
    return subprocess.check_output(['git', *args], cwd=root)


def tree(root, ref):
    with tarfile.open(fileobj=io.BytesIO(git(root, 'archive', ref))) as archive:
        return {entry.name: archive.extractfile(entry).read()
                for entry in archive.getmembers() if entry.isfile()}


def counts(tests):
    return dict(collections.Counter(test['status'] for test in tests))


source = read_json(PLAN / 'sources.json')
donor = Path(source['donor_worktree'])
prepared = tree(donor, source['donor_commit'])
report = tree(donor, source['donor_report_commit'])
core = tree(CORE, source['core_commit'])
old_source = read_json(PLAN / 'evidence/actor-sources.json')
old_tree = tree(donor, source['original_donor_commit'])

for record, files in [(source, prepared), (old_source, old_tree)]:
    for item in record['donor_files']:
        assert hashlib.sha256(files[item['path']]).hexdigest() == item['sha256'], item['path']
assert len({x['path'] for x in source['donor_files']}) == len(source['donor_files'])
assert len({x['proposed_target'] for x in source['donor_files']}) == len(source['donor_files'])
assert all(x['path'] == x['proposed_target'] for x in source['donor_files'])
prepared_hashes = read_json(PLAN / 'evidence/prepared/prepared-source.json')
for item in prepared_hashes['files']:
    assert hashlib.sha256(prepared[item['path']]).hexdigest() == item['sha256'], item['path']

copied = 0
for path in (PLAN / 'evidence/prepared').iterdir():
    if not path.is_file():
        continue
    candidates = ['docs/migration-preparation/' + path.name,
                  'docs/migration-preparation/evidence/' + path.name]
    match = [name for name in candidates if name in report]
    assert len(match) == 1, path
    assert report[match[0]] == path.read_bytes(), path
    copied += 1
changed = git(donor, 'diff', '--name-only', source['donor_commit'], source['donor_report_commit']).decode().splitlines()
assert all(p.startswith('docs/migration-preparation/') for p in changed)

manifest = read_json(PLAN / 'example-manifest.json')
assert manifest['source_commit'] == source['donor_commit']
assert len(manifest['catalog']) == len({x['id'] for x in manifest['catalog']}) == 52
assert len(manifest['integration_scenarios']) == 10
assert len(manifest['research']) == 8
paths = set()
mapped_results = read_json(PLAN / 'evidence/prepared/scoped-final-full-seed-0.results.manifest.json')
selections = {(x['category'], x['id']): x for x in mapped_results}
for category in ['catalog', 'integration_scenarios', 'research']:
    for row in manifest[category]:
        for key in ['source_files', 'donor_tests', 'prepared_tests', 'prepared_files']:
            paths.update(row.get(key, []))
        if 'donor_profile' in row:
            paths.add(row['donor_profile'])
        selected = selections.get((category, row['id']))
        if selected:
            assert counts(selected['tests']) == row['source_test_counts'], row['id']
            assert len(selected['tests']) == row['source_tests_selected'], row['id']
            assert sum(test['status'] not in ['skipped', 'excluded'] for test in selected['tests']) == row['source_tests_executed'], row['id']
            assert len(selected['tests']) >= row['baseline_tests_executed'], row['id']
            if category != 'research':
                assert set(row['source_test_counts']) == {'passed'}, row['id']
        else:
            assert category == 'research' and row['baseline_tests_executed'] == 0
for row in manifest['shared_group_files']:
    paths.update(row['source_files'])
    paths.update(row['test_files'])
for key in ['support_files', 'validation_support_files', 'topology_core_tests',
            'required_regression_tests', 'migration_tools']:
    paths.update(manifest[key])
assert paths <= prepared.keys(), sorted(paths - prepared.keys())
assert paths <= {x['path'] for x in source['donor_files']}

suite_results = {}
for name in ['final-full-seed-0', 'final-coverage', 'final-serial', 'final-regression-repeat']:
    suites = [json.loads(line) for line in (PLAN / 'evidence/prepared' / (name + '.results.jsonl')).read_text().splitlines()]
    summary = [counts(run['tests']) for run in suites]
    if name == 'final-regression-repeat':
        assert summary == [{'passed': 42}] * 5, summary
    else:
        assert summary == [{'passed': 1005, 'failed': 1}], summary
        failed = [t for run in suites for t in run['tests'] if t['status'] == 'failed']
        assert len(failed) == 1
        assert failed[0]['file'] == 'test/jido/agent/distributed_authority_test.exs'
        assert failed[0]['name'] == 'test one logical identity has at most one live cluster owner'
    suite_results[name] = summary

current = read_json(PLAN / 'evidence/prepared/scoped-final-full-seed-0.json')
assert current['revision'] == source['donor_commit']
assert current['exit_code'] == 0
current_runs = [json.loads(line) for line in (PLAN / 'evidence/prepared/scoped-final-full-seed-0.results.jsonl').read_text().splitlines()]
assert len(current_runs) == 1
assert counts(current_runs[0]['tests']) == {'passed': 1005, 'excluded': 1}
allowed = manifest['allowed_skips']
assert len(allowed) == 1
assert allowed[0]['file'] == 'test/jido/agent/distributed_authority_test.exs'
assert allowed[0]['name'] == 'test one logical identity has at most one live cluster owner'
skipped = [test for test in current_runs[0]['tests'] if test['status'] in ['skipped', 'excluded']]
assert [(test['file'], test['name']) for test in skipped] == [(allowed[0]['file'], allowed[0]['name'])]
suite_results['scoped-final-full-seed-0'] = [counts(current_runs[0]['tests'])]

rows = list(csv.DictReader((PLAN / 'file-inventory.csv').open()))
core_files = {p for p in core if p.startswith(('lib/', 'test/'))}
donor_files = {p for p in prepared if p.startswith(('lib/', 'test/'))}
assert core_files <= {r['core_path'] for r in rows}
assert donor_files == {r['donor_path'] for r in rows if r['donor_path']}
assert len(rows) == len({(r['core_path'], r['donor_path']) for r in rows})
assert all(r['core_path'] in core or r['core_path'] in prepared for r in rows)

links = 0
documents = list(PLAN.glob('*.md')) + [PLAN / 'evidence/prepared/serialized-formats.md']
for document in documents:
    for raw in re.findall(r'\[[^\]\n]*\]\(([^)\n]+)\)', document.read_text()):
        target = raw.strip('<>').split('#', 1)[0]
        if not target or re.match(r'^[a-z]+://', target):
            continue
        path = Path(target) if target.startswith('/') else document.parent / target
        assert path.exists(), (document.name, target)
        links += 1

assert git(donor, 'rev-parse', 'HEAD').decode().strip() == source['donor_report_commit']
assert git(donor, 'status', '--porcelain').decode() == ''
original_checkout = CORE.parent / 'jido_v3'
assert git(original_checkout, 'rev-parse', 'HEAD').decode().strip() == source['original_donor_commit']
assert git(original_checkout, 'status', '--porcelain').decode() == ''
git(CORE, 'merge-base', '--is-ancestor', source['core_commit'], 'HEAD')
# M00 adds this plan above the fixed implementation baseline. During M01,
# separate this input audit from checks of the evolving migration target.
assert git(CORE, 'diff', source['core_commit'], '--name-only', '--', '.',
           ':(exclude)docs/migration/**').decode() == ''

result = dict(status='pass', prepared_source_commit=source['donor_commit'],
              report_commit=source['donor_report_commit'],
              source_hashes_checked=len(source['donor_files']),
              original_source_hashes_checked=len(old_source['donor_files']),
              donor_report_hashes_checked=len(prepared_hashes['files']),
              copied_evidence_files_checked=copied,
              catalog_fixtures=52, integration_scenarios=10, research_items=8,
              manifest_paths_checked=len(paths), core_files_accounted_for=len(core_files),
              donor_files_accounted_for=len(donor_files), inventory_rows=len(rows),
              markdown_documents=len(documents), local_links_checked=links,
              test_results=suite_results, new_mix_commands=3,
              allowed_skips=allowed,
              prepared_working_tree='clean', original_donor_working_tree='clean',
              core_tracked_files='unchanged outside docs/migration', errors=[])
(PLAN / 'evidence/plan-checks.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result, indent=2))
