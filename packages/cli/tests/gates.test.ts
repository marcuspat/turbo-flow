import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { runCmdGate } from '../src/engine/gates.js';
import { mkdirSync, writeFileSync, rmSync, chmodSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

describe('runCmdGate', () => {
  const tmpDir = join(tmpdir(), 'tf-gates-test');
  const gateDir = join(tmpDir, 'gates');

  beforeAll(() => {
    mkdirSync(gateDir, { recursive: true });

    // Create a passing gate
    const passGate = join(gateDir, 'pass.sh');
    writeFileSync(passGate, '#!/bin/bash\nexit 0\n');
    chmodSync(passGate, 0o755);

    // Create a failing gate
    const failGate = join(gateDir, 'fail.sh');
    writeFileSync(failGate, '#!/bin/bash\necho "something broke" >&2\nexit 1\n');
    chmodSync(failGate, 0o755);

    // Create a test file for existence check
    writeFileSync(join(tmpDir, 'target.txt'), 'hello');
  });

  afterAll(() => {
    rmSync(tmpDir, { recursive: true, force: true });
  });

  it('passes for exit 0', () => {
    const result = runCmdGate({ id: 'pass', type: 'cmd', run: 'gates/pass.sh' }, tmpDir, '001-test');
    expect(result.passed).toBe(true);
    expect(result.duration_ms).toBeGreaterThanOrEqual(0);
  });

  it('fails for non-zero exit', () => {
    const result = runCmdGate({ id: 'fail', type: 'cmd', run: 'gates/fail.sh' }, tmpDir, '001-test');
    expect(result.passed).toBe(false);
    expect(result.feedback).toContain('something broke');
  });

  it('substitutes SPEC_ID', () => {
    const result = runCmdGate({ id: 'spec-sub', type: 'cmd', run: 'test -f target.txt' }, tmpDir, '001-test');
    expect(result.passed).toBe(true);
  });

  it('skips optional gates when command is absent', () => {
    const result = runCmdGate(
      { id: 'opt', type: 'cmd', run: 'gates/nonexistent.sh', optional_if_absent: true },
      tmpDir, '001-test',
    );
    expect(result.passed).toBe(true);
    expect(result.skipped).toBe(true);
    expect(result.skip_reason).toContain('not found');
  });
});
