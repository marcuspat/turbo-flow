// gate-check.js — the COMMENT-path reconciler for .github/workflows/gate-check.yml.
//
// GitHub runs issue_comment workflows against the default branch, so this file is always
// main's code when it executes — that is why the reconcile job may hold actions: write.
// The pull_request path is a separate, read-only job with no checkout; it never loads
// this (or any PR-controlled) code. Kept out of the YAML so rig-lite/self-test.sh can
// drive it under plain node with a mocked GitHub (no network).
//
// Return values are for the tests; the job's pass/fail is core.setFailed().
//   'skipped'      comment on a plain issue — no PR to reconcile
//   'not-approved' gate-verdict missing or not success on the PR head SHA (fails the job)
//   'approved'     gate-verdict is success; nothing needed re-running
//   'rerun'        re-ran the PR's own pull_request run(s)
//   'timeout'      a PR run never completed inside waitMs (fails the job, says how to finish by hand)
//   'ambiguous'    fork runs match, but >1 open PR shares this head (fails the job, lists the manual reruns)
//   'unattributed' stale run(s) at this SHA belong to no PR we can name (fails the job, lists the manual reruns)
module.exports = async function reconcile({ github, context, core, sleep, waitMs = 120000, pollMs = 10000 }) {
  if (context.eventName !== 'issue_comment') {
    throw new Error(`gate-check.js reconciles the gate's verdict comment; it was wired to a ${context.eventName} event`);
  }
  const repo = { owner: context.repo.owner, repo: context.repo.repo };

  // A VERDICT-bearing comment on a plain issue has no PR to reconcile.
  if (!context.payload.issue.pull_request) {
    core.info('Comment is on an issue, not a PR — nothing to reconcile.');
    return 'skipped';
  }

  const pr = (await github.rest.pulls.get({ ...repo, pull_number: context.issue.number })).data;
  const sha = pr.head.sha;
  core.info(`Checking gate-verdict status for SHA: ${sha}`);

  // The gate sets this status directly on the head SHA.
  const statuses = await github.rest.repos.listCommitStatusesForRef({ ...repo, ref: sha });
  const gateStatus = statuses.data.find(s => s.context === 'gate-verdict');

  if (!gateStatus) {
    core.setFailed(`No gate-verdict commit status found — run rig-lite/gate.sh --pr ${pr.number}. Merge blocked until the gate sets APPROVED.`);
    return 'not-approved';
  }
  core.info(`Gate status: ${gateStatus.state} (set by @${gateStatus.creator.login})`);
  core.info(`Description: ${gateStatus.description}`);
  if (gateStatus.state !== 'success') {
    core.setFailed(`Gate verdict: ${gateStatus.state} — fix the findings and re-gate. Merge blocked until APPROVED.`);
    return 'not-approved';
  }
  core.info('✓ Gate APPROVED on this commit SHA — merge is allowed (by a human).');

  // This run's green attaches to main. The PR displays only its own pull_request run —
  // which fired seconds after the push, before the gate, and failed. Re-run that one.
  //
  // Checks are keyed by SHA and two PRs can share a head SHA (one branch, two bases),
  // so a SHA-only lookup can pick the other PR's run. Attribute runs to THIS PR through
  // the run's own pull_requests list, and walk every page.
  const all = await github.paginate(github.rest.actions.listWorkflowRuns, {
    ...repo, workflow_id: 'gate-check.yml', event: 'pull_request', head_sha: sha, per_page: 100,
  });
  const listed = r => (r.pull_requests || []).some(p => p.number === pr.number);
  let mine = all.filter(listed);

  // GitHub leaves pull_requests EMPTY on fork-PR runs — forks are the normal contribution
  // path and must not be left red. Branch + head repository is all such a run carries,
  // and that cannot separate one fork branch opened against two bases: so when a fork
  // run matches, ask GitHub how many open PRs share this head. One → it's ours. More →
  // ambiguous: stop and say how to finish by hand rather than re-run the wrong PR.
  const forkMatch = r => (r.pull_requests || []).length === 0
    && r.head_branch === pr.head.ref
    && !!pr.head.repo && r.head_repository?.full_name === pr.head.repo.full_name;
  const forkRuns = all.filter(forkMatch);
  if (forkRuns.length) {
    const open = await github.paginate(github.rest.pulls.list, { ...repo, state: 'open', head: pr.head.label, per_page: 100 });
    if (open.length > 1) {
      core.setFailed(`PR #${pr.number} shares its head ${pr.head.label} with ${open.length - 1} other open PR(s); fork runs can't be attributed — finish by hand: ${forkRuns.map(r => `gh run rerun ${r.id}`).join(' ; ')}`);
      return 'ambiguous';
    }
    mine = mine.concat(forkRuns);
  }

  if (mine.length === 0) {
    // Stale runs here that belong to no PR we can name: don't guess, don't go green.
    const stray = all.filter(r => (r.pull_requests || []).length === 0 && r.status === 'completed' && r.conclusion !== 'success');
    if (stray.length) {
      core.setFailed(`Could not attribute the stale check run(s) at this SHA to PR #${pr.number} — finish by hand: ${stray.map(r => `gh run rerun ${r.id}`).join(' ; ')}`);
      return 'unattributed';
    }
    core.info(`No pull_request run attributable to PR #${pr.number} at this SHA — nothing to re-run.`);
    return 'approved';
  }

  // A run may still be in flight (queued/in_progress). Re-running a live run is
  // rejected, and giving up would leave it to finish red with no event to retry —
  // so wait for it to settle, bounded.
  const deadline = Date.now() + waitMs;
  let rerun = 0;
  for (let run of mine) {
    while (run.status !== 'completed' && Date.now() < deadline) {
      core.info(`PR run ${run.id} is ${run.status} — waiting for it to finish before reconciling.`);
      await sleep(pollMs);
      run = (await github.rest.actions.getWorkflowRun({ ...repo, run_id: run.id })).data;
    }
    if (run.status !== 'completed') {
      core.setFailed(`PR run ${run.id} still ${run.status} after ${Math.round(waitMs / 1000)}s — finish by hand: gh run rerun ${run.id}`);
      return 'timeout';
    }
    if (run.conclusion === 'success') {
      core.info(`PR run ${run.id} is already green — nothing to re-run.`);
      continue;
    }
    await github.rest.actions.reRunWorkflow({ ...repo, run_id: run.id });
    core.info(`Re-ran pull_request run ${run.id} so the PR's check reflects APPROVED.`);
    rerun++;
  }
  return rerun ? 'rerun' : 'approved';
};
