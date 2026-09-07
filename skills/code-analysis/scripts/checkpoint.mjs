#!/usr/bin/env node
// Zero dependencies. Snapshots explicit files; does not judge analysis correctness.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const roles = new Set(['source', 'requirement', 'deliverable', 'evidence', 'asset', 'review']);
const statuses = new Set(['running', 'paused', 'blocked', 'done']);
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
const canonical = value => JSON.stringify(normalize(value));
function normalize(value) {
  if (Array.isArray(value)) return value.map(normalize);
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.keys(value).sort().map(key => [key, normalize(value[key])]));
  }
  return value;
}
const fail = message => { throw new Error(message); };
const object = value => value && typeof value === 'object' && !Array.isArray(value);
const nonempty = value => typeof value === 'string' && value.trim().length > 0;
const digest = value => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
function stringList(value, name) {
  if (!Array.isArray(value) || value.some(x => !nonempty(x)) || new Set(value).size !== value.length) fail(`INVALID_${name}`);
}
function relativeName(value) {
  if (!nonempty(value) || value.includes('\\') || value.includes(':') || path.posix.isAbsolute(value)
      || value.split('/').some(x => ['', '.', '..'].includes(x))) fail('INVALID_RELATIVE_PATH');
  return value;
}
function contained(root, target) {
  const rel = path.relative(root, target);
  if (path.isAbsolute(rel) || rel === '..' || rel.startsWith(`..${path.sep}`)) fail('PATH_OUTSIDE_ROOT');
  return target;
}
function actualFile(root, name) {
  const target = contained(root, fs.realpathSync(path.join(root, relativeName(name))));
  if (!fs.statSync(target).isFile()) fail('NOT_A_FILE');
  return target;
}
function validate(data, snapshot = false) {
  if (!object(data) || data.schema_version !== 1 || !nonempty(data.run_id) || !nonempty(data.target)
      || !statuses.has(data.status)) fail('INVALID_STATE');
  stringList(data.completed, 'COMPLETED');
  stringList(data.pending, 'PENDING');
  if (data.completed.some(x => data.pending.includes(x))) fail('WORK_OVERLAP');
  if (data.status === 'done' && data.pending.length) fail('DONE_WITH_PENDING_WORK');
  if (data.status === 'running' && !data.pending.length) fail('RUNNING_WITHOUT_NEXT_WORK');
  if (typeof data.partial_note !== 'string' || typeof data.invalidation_reason !== 'string') fail('INVALID_NOTES');
  if (!Array.isArray(data.files) || !data.files.length) fail('EMPTY_FILE_LIST');
  const names = new Set();
  for (const file of data.files) {
    if (!object(file) || !roles.has(file.role)) fail('INVALID_FILE_ROLE');
    relativeName(file.path);
    if (names.has(file.path)) fail('DUPLICATE_FILE');
    names.add(file.path);
    if (snapshot && !digest(file.sha256)) fail('INVALID_FILE_HASH');
  }
  if (!data.files.some(x => x.role !== 'review')) fail('NO_ANALYSIS_FILES');
}
function contentHash(files) {
  // A review refers to this hash; excluding the review avoids a circular hash dependency.
  return hash(canonical(files.filter(x => x.role !== 'review')));
}
function readState(file) {
  const raw = fs.readFileSync(file, 'utf8');
  const state = JSON.parse(raw);
  validate(state, true);
  const { state_sha256, ...payload } = state;
  if (!Number.isSafeInteger(state.revision) || state.revision < 1 || !digest(state_sha256)
      || hash(canonical(payload)) !== state_sha256) fail('STATE_INTEGRITY_MISMATCH');
  if (state.next_action !== (state.pending[0] ?? null)
      || state.snapshot_sha256 !== contentHash(state.files)) fail('SNAPSHOT_INTEGRITY_MISMATCH');
  return { state, raw };
}
function save(root, runName, inputPath, expected) {
  relativeName(runName);
  if (!/^\d+$/.test(expected ?? '') || !Number.isSafeInteger(Number(expected))) fail('INVALID_EXPECTED_REVISION');
  const parent = contained(root, fs.realpathSync(path.dirname(path.join(root, runName))));
  const destination = path.join(parent, path.basename(runName));
  if (fs.existsSync(destination) && fs.lstatSync(destination).isSymbolicLink()) fail('RUN_SYMLINK_REJECTED');
  const lock = `${destination}.lock`;
  const fd = fs.openSync(lock, 'wx'); // Cooperating writers serialize; a stale lock fails visibly.
  const temp = `${destination}.${crypto.randomUUID()}.tmp`;
  try {
    const prior = fs.existsSync(destination) ? readState(destination) : null;
    if ((prior?.state.revision ?? 0) !== Number(expected)) fail('REVISION_CONFLICT');
    const input = JSON.parse(fs.readFileSync(inputPath, 'utf8'));
    validate(input);
    if (prior && (input.run_id !== prior.state.run_id || input.target !== prior.state.target)) fail('RUN_IDENTITY_CHANGED');
    if (prior && !input.invalidation_reason.trim()) {
      if (prior.state.completed.some(x => !input.completed.includes(x))) fail('COMPLETED_WORK_REGRESSION');
      if (prior.state.files.some(old => !input.files.some(x => x.path === old.path && x.role === old.role))) fail('TRACKED_FILE_REMOVED');
    }
    const realNames = new Set();
    const files = input.files.map(file => {
      if (file.path === runName || file.path === `${runName}.lock`) fail('SELF_REFERENCE');
      const actual = actualFile(root, file.path);
      if (actual === destination || actual === lock) fail('SELF_REFERENCE');
      if (realNames.has(actual)) fail('DUPLICATE_FILE_ALIAS');
      realNames.add(actual);
      return { path: file.path, role: file.role, sha256: hash(fs.readFileSync(actual)) };
    }).sort((a, b) => a.path < b.path ? -1 : a.path > b.path ? 1 : 0);
    const state = {
      schema_version: 1, run_id: input.run_id, target: input.target,
      revision: Number(expected) + 1, status: input.status,
      completed: input.completed, pending: input.pending, next_action: input.pending[0] ?? null,
      partial_note: input.partial_note, invalidation_reason: input.invalidation_reason,
      files, snapshot_sha256: contentHash(files), updated_at: new Date().toISOString(),
    };
    state.state_sha256 = hash(canonical(state));
    const tempFd = fs.openSync(temp, 'wx');
    try { fs.writeFileSync(tempFd, JSON.stringify(state, null, 2) + '\n'); fs.fsyncSync(tempFd); }
    finally { fs.closeSync(tempFd); }
    if (prior ? fs.readFileSync(destination, 'utf8') !== prior.raw : fs.existsSync(destination)) fail('CONCURRENT_STATE_CHANGE');
    fs.renameSync(temp, destination); // One canonical state file, no multi-file transaction claim.
    return { valid: true, revision: state.revision, snapshot_sha256: state.snapshot_sha256, next_action: state.next_action };
  } finally {
    if (fs.existsSync(temp)) fs.unlinkSync(temp);
    fs.closeSync(fd);
    fs.unlinkSync(lock);
  }
}
function check(root, runName) {
  const { state } = readState(actualFile(root, runName));
  const changed = [];
  for (const file of state.files) {
    try {
      if (hash(fs.readFileSync(actualFile(root, file.path))) !== file.sha256) changed.push({ path: file.path, reason: 'changed' });
    } catch { changed.push({ path: file.path, reason: 'missing_or_unreadable' }); }
  }
  return { valid: changed.length === 0, revision: state.revision, status: state.status,
    snapshot_sha256: state.snapshot_sha256, next_action: state.next_action,
    completed: state.completed, pending: state.pending, partial_note: state.partial_note, changed };
}
try {
  const [command, rootArg, runName, inputPath, expected, ...extra] = process.argv.slice(2);
  if (!rootArg || !runName || extra.length || !['save', 'check'].includes(command)
      || (command === 'save' && (!inputPath || expected === undefined))
      || (command === 'check' && (inputPath !== undefined || expected !== undefined))) {
    fail('USAGE: checkpoint.mjs save ROOT RUN_RELATIVE INPUT_JSON EXPECTED_REVISION | check ROOT RUN_RELATIVE');
  }
  const root = fs.realpathSync(rootArg);
  const result = command === 'save' ? save(root, runName, inputPath, expected) : check(root, runName);
  process.stdout.write(JSON.stringify(result, null, 2) + '\n');
  if (!result.valid) process.exitCode = 1;
} catch (error) {
  process.stdout.write(JSON.stringify({ valid: false, error: error.message }) + '\n');
  process.exitCode = 1;
}
