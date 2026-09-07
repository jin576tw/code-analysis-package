import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const script = fileURLToPath(new URL('../../skills/code-analysis/scripts/checkpoint.mjs', import.meta.url));
function fixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'analysis-checkpoint-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  fs.mkdirSync(path.join(root, 'run'));
  fs.writeFileSync(path.join(root, 'source.js'), 'export const value = 1;\n');
  fs.writeFileSync(path.join(root, 'ANALYSIS.md'), '# 現況\nValue is 1.\n');
  const input = { schema_version: 1, run_id: 'test', target: 'value analysis', status: 'running',
    completed: ['source-inventory', 'draft'], pending: ['review', 'finalize'], partial_note: '', invalidation_reason: '',
    files: [{ path: 'source.js', role: 'source' }, { path: 'ANALYSIS.md', role: 'deliverable' }] };
  const invoke = (...args) => {
    const result = spawnSync(process.execPath, [script, ...args], { encoding: 'utf8' });
    assert.equal(result.error, undefined);
    return { code: result.status, data: JSON.parse(result.stdout) };
  };
  const save = (revision = 0) => {
    fs.writeFileSync(path.join(root, 'input.json'), JSON.stringify(input));
    return invoke('save', root, 'run/run.json', path.join(root, 'input.json'), String(revision));
  };
  return { root, input, invoke, save, check: () => invoke('check', root, 'run/run.json'),
    state: () => JSON.parse(fs.readFileSync(path.join(root, 'run/run.json'), 'utf8')) };
}

test('snapshot verifies actual source and document bytes; pending determines next action', t => {
  const f = fixture(t);
  assert.equal(f.save().code, 0);
  const result = f.check();
  assert.equal(result.code, 0);
  assert.equal(result.data.next_action, 'review');
  assert.deepEqual(result.data.completed, ['source-inventory', 'draft']);
  assert.equal(f.state().files.length, 2);
});

for (const file of ['source.js', 'ANALYSIS.md']) {
  test(`detects changed content in ${file}, even when progress is unchanged`, t => {
    const f = fixture(t); f.save();
    fs.appendFileSync(path.join(f.root, file), 'changed');
    const result = f.check();
    assert.equal(result.code, 1);
    assert.deepEqual(result.data.changed, [{ path: file, reason: 'changed' }]);
  });
}
test('missing source cannot pass freshness check', t => {
  const f = fixture(t); f.save(); fs.unlinkSync(path.join(f.root, 'source.js'));
  assert.equal(f.check().code, 1);
});
test('revision conflict preserves prior state and removes own lock', t => {
  const f = fixture(t); f.save(); const prior = f.state();
  assert.equal(f.save().data.error, 'REVISION_CONFLICT');
  assert.deepEqual(f.state(), prior);
  assert.equal(fs.existsSync(path.join(f.root, 'run/run.json.lock')), false);
});
test('existing writer lock is not stolen or deleted', t => {
  const f = fixture(t); f.save();
  fs.writeFileSync(path.join(f.root, 'run/run.json.lock'), 'another writer');
  assert.equal(f.save(1).code, 1);
  assert.equal(fs.readFileSync(path.join(f.root, 'run/run.json.lock'), 'utf8'), 'another writer');
});
test('tampering with next work or status is rejected by state hash', t => {
  const f = fixture(t); f.save(); const state = f.state();
  state.pending = ['publish'];
  fs.writeFileSync(path.join(f.root, 'run/run.json'), JSON.stringify(state));
  assert.equal(f.check().data.error, 'STATE_INTEGRITY_MISMATCH');
});
test('malformed state and unsupported schema fail rather than returning ready', t => {
  const f = fixture(t); f.save();
  fs.writeFileSync(path.join(f.root, 'run/run.json'), '{');
  assert.equal(f.check().code, 1);
  f.input.schema_version = 99;
  assert.equal(f.save(1).code, 1);
});
test('completed work cannot silently re-enter pending', t => {
  const f = fixture(t); f.save();
  f.input.completed = ['source-inventory']; f.input.pending.unshift('draft');
  assert.equal(f.save(1).data.error, 'COMPLETED_WORK_REGRESSION');
});
test('partial repair can resume after explicit impact assessment without a new run', t => {
  const f = fixture(t); f.save();
  fs.appendFileSync(path.join(f.root, 'ANALYSIS.md'), '\nPartial correction.');
  assert.equal(f.check().code, 1);
  f.input.completed = ['source-inventory']; f.input.pending = ['finish-repair', 'review', 'finalize'];
  f.input.partial_note = 'D1 updated; D2 still pending. Same repair round.';
  f.input.invalidation_reason = 'Interrupted document edit: draft and review need revalidation.';
  assert.equal(f.save(1).code, 0);
  assert.equal(f.check().data.next_action, 'finish-repair');
  assert.deepEqual(f.check().data.completed, ['source-inventory']);
});
test('review fingerprint is tracked without circularly changing reviewed snapshot', t => {
  const f = fixture(t); const before = f.save().data.snapshot_sha256;
  fs.writeFileSync(path.join(f.root, 'REVIEW.md'), `reviewed_snapshot_sha256: ${before}\nverdict: pass\n`);
  f.input.files.push({ path: 'REVIEW.md', role: 'review' });
  f.input.completed.push('review', 'finalize'); f.input.pending = []; f.input.status = 'done';
  assert.equal(f.save(1).data.snapshot_sha256, before);
  assert.equal(f.check().code, 0);
  fs.appendFileSync(path.join(f.root, 'REVIEW.md'), 'tampered');
  assert.equal(f.check().code, 1);
});
test('tracked evidence cannot disappear from later snapshots silently', t => {
  const f = fixture(t); f.save(); f.input.files.pop();
  assert.equal(f.save(1).data.error, 'TRACKED_FILE_REMOVED');
});
for (const badPath of ['../outside.js', '/etc/hosts', 'C:/data.txt', 'run/../source.js', 'run/run.json']) {
  test(`rejects unsafe or self-referential tracked path ${badPath}`, t => {
    const f = fixture(t); f.save(); f.input.files.push({ path: badPath, role: 'source' });
    assert.equal(f.save(1).code, 1);
    assert.equal(f.state().revision, 1);
  });
}
test('symlink outside root and duplicate aliases cannot enter snapshot', t => {
  const f = fixture(t);
  const outside = fs.mkdtempSync(path.join(os.tmpdir(), 'analysis-outside-'));
  t.after(() => fs.rmSync(outside, { recursive: true, force: true }));
  fs.writeFileSync(path.join(outside, 'secret'), 'do not read');
  fs.symlinkSync(path.join(outside, 'secret'), path.join(f.root, 'escape'));
  f.input.files.push({ path: 'escape', role: 'source' });
  assert.equal(f.save().data.error, 'PATH_OUTSIDE_ROOT');
  f.input.files.pop();
  fs.symlinkSync(path.join(f.root, 'source.js'), path.join(f.root, 'alias'));
  f.input.files.push({ path: 'alias', role: 'source' });
  assert.equal(f.save().data.error, 'DUPLICATE_FILE_ALIAS');
});
test('unknown command, missing files, empty manifest and identity changes fail', t => {
  const f = fixture(t);
  assert.equal(f.invoke('unknown', f.root, 'run/run.json').code, 1);
  f.input.files.push({ path: 'missing.js', role: 'source' });
  assert.equal(f.save().code, 1); f.input.files.pop();
  f.save(); f.input.run_id = 'another-task';
  assert.equal(f.save(1).data.error, 'RUN_IDENTITY_CHANGED');
  f.input.run_id = 'test'; f.input.files = [];
  assert.equal(f.save(1).data.error, 'EMPTY_FILE_LIST');
});
test('inconsistent pending/completed states are rejected', t => {
  const f = fixture(t); f.input.status = 'done';
  assert.equal(f.save().data.error, 'DONE_WITH_PENDING_WORK');
  f.input.status = 'running'; f.input.pending = [];
  assert.equal(f.save().data.error, 'RUNNING_WITHOUT_NEXT_WORK');
  f.input.pending = ['draft'];
  assert.equal(f.save().data.error, 'WORK_OVERLAP');
});
