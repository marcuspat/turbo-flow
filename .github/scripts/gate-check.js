// gate-check.js — reconciles the gate's commit status with the PR's visible check.
//
// Loaded by .github/workflows/gate-check.yml via actions/github-script's require().
// Kept out of the YAML so rig-lite/self-test.sh can drive it under plain node with a
// mocked GitHub (no network) — including the in-progress race on the comment path.
//
// Return values are for the tests; the job's pass/fail is core.setFailed().
//   'skipped'      comment on a plain issue — no PR to check
//   'missing'      no gate-verdict status on the PR head SHA (fails the job)
//   'not-approved' gate-verdict exists but is not success (fails the job)
//   'approved'     gate-verdict is success; nothing needed re-running
//   'rerun'        comment path re-ran the PR's own pull_request run(s)
//   'timeout'      a PR run never completed inside waitMs (fails the job, says how to finish by hand)
//   'unattributed' stale run(s) at this SHA belong to no PR we can name (fails the job, lists the manual reruns)
module.exports = async function gateCheck({ github, context, core, sleep, waitMs = 120000, pollMs = 10000 }) {
  const repo = { owner: context.repo.owner, repo: context.repo.repo };

  // A VERDICT-bearing comment on a plain issue has no PR to check.
  if (context.eventName === 'issue_comment' && !context.payload.issue.pull_request) {
    core.info('Comment is on an issue, not a PR — nothing to check.');
    return 'skipped';
  }

  const pr = context.payload.pull_request ||
    (await github.rest.pulls.get({ ...repo, pull_number: context.issue.number })).data;
  const sha = pr.head.sha;
  core.info(`Checking gate-verdict status for SHA: ${sha}`);

  // The gate sets this status directly on the head SHA.
  const statuses = await github.rest.repos.listCommitStatusesForRef({ ...repo, ref: sha });
  const gateStatus = statuses.data.find(s => s.context === 'gate-verdict');

  if (!gateStatus) {
    core.setFailed(`No gate-verdict commit status found — run rig-lite/gate.sh --pr ${pr.number}. Merge blocked until the gate sets APPROVED.`);
    return 'missing';
  }

  core.info(`Gate status: ${gateStatus.state} (set by @${gateStatus.creator.login})`);
  core.info(`Description: ${gateStatus.description}`);

  if (gateStatus.state !== 'success') {
    core.setFailed(`Gate verdict: ${gateStatus.state} — fix the findings and re-gate. Merge blocked until APPROVED.`);
    return 'not-approved';
  }

  core.info('✓ Gate APPROVED on this commit SHA — merge is allowed (by a human).');
  if (context.eventName !== 'issue_comment') return 'approved';

  // Comment path: GitHub ran this workflow against the default branch, so this run's
  // green attaches to main. The PR displays only its own pull_request run — which fired
  // seconds after the push, before the gate, and failed. Re-run that one so it flips.
  //
  // Checks are keyed by SHA and two PRs can share a head SHA (one branch, two bases),
  // so a SHA-only lookup can pick the other PR's run. Attribute runs to THIS PR through
  // the run's own pull_requests list, and walk every page. GitHub leaves pull_requests
  // EMPTY on fork-PR runs, so fall back to head branch + head repository for those —
  // forks are the normal contribution path and must not be left red.
  const all = await github.paginate(github.rest.actions.listWorkflowRuns, {
    ...repo, workflow_id: 'gate-check.yml', event: 'pull_request', head_sha: sha, per_page: 100,
  });
  const listed = r => (r.pull_requests || []).some(p => p.number === pr.number);
  const forkMatch = r => (r.pull_requests || []).length === 0
    && r.head_branch === pr.head.ref
    && !!pr.head.repo && r.head_repository?.full_name === pr.head.repo.full_name;
  const mine = all.filter(r => listed(r) || forkMatch(r));

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
