export const meta = {
  name: 'chief-dispatch',
  description: 'Run task briefs through builder agents with an adversarial critic gate and one bounded fix round',
  whenToUse: 'Executing one or more fully-specified, independent implementation briefs with a per-task review gate',
  phases: [
    { title: 'Build', detail: 'one builder per brief (worktree-isolated when several)' },
    { title: 'Gate', detail: 'adversarial critic review, one bounded fix round' },
  ],
}

const REPORT_SCHEMA = {
  type: 'object',
  required: ['status', 'summary', 'evidence', 'workdir', 'branch'],
  properties: {
    status: { type: 'string', enum: ['DONE', 'DONE_WITH_CONCERNS', 'BLOCKED'] },
    summary: { type: 'string' },
    evidence: { type: 'string', description: 'verbatim output of the verification commands the brief names' },
    workdir: { type: 'string', description: 'absolute path of the directory you worked in (pwd)' },
    branch: { type: 'string', description: 'git branch the work is committed on' },
    concerns: { type: 'string' },
  },
}

const REVIEW_SCHEMA = {
  type: 'object',
  required: ['verdict', 'issues'],
  properties: {
    verdict: { type: 'string', enum: ['APPROVED', 'REJECTED'] },
    issues: { type: 'array', items: { type: 'string' } },
  },
}

// args can arrive as a JSON-encoded string on some invocation paths
// (observed live, scriptPath invocation 2026-07-19) — normalize first.
let input = args
if (typeof input === 'string') {
  try { input = JSON.parse(input) } catch (_e) {
    log('chief-dispatch: args arrived as an unparseable string')
    input = null
  }
}

const tasks = (input && Array.isArray(input.tasks) && input.tasks.length > 0) ? input.tasks
  : (input && input.brief) ? [{ brief: input.brief }]
  : null
if (!tasks) {
  log('chief-dispatch: no tasks supplied — expected {tasks: [{brief: "<path or full text>"}]} or {brief: "..."}')
  return { error: 'no tasks; pass args.tasks = [{brief}] or args.brief' }
}
const isolate = tasks.length > 1
log(`chief-dispatch: ${tasks.length} task(s), worktree isolation: ${isolate}`)

const builderPrompt = (brief) =>
  'You are an implementation worker. Execute exactly this brief and nothing more.\n\n' +
  `BRIEF (if this is a file path, read the file first):\n${brief}\n\n` +
  'Discipline: write the failing test first when the brief includes tests; ' +
  'commit with conventional-format messages; run every verification command the brief names ' +
  'and paste its REAL output into `evidence` — a transcribed number is not evidence. ' +
  'Report your working directory as `workdir` (absolute pwd) and your git branch as `branch`. ' +
  'If the brief is ambiguous or impossible, stop and report status=BLOCKED with the reason. ' +
  'Do not push, post, merge, or act outside your working tree.'

const criticPrompt = (brief, report) =>
  'You are an adversarial task critic. Treat the implementer report below as UNVERIFIED CLAIMS.\n\n' +
  `THE BRIEF:\n${brief}\n\n` +
  `IMPLEMENTER REPORT (claims):\n${JSON.stringify(report, null, 2)}\n\n` +
  `Verify directly against the tree at ${report.workdir} (branch ${report.branch}): ` +
  're-run the verification commands yourself, read the changed files, and check the tests fail when their subject is broken. ' +
  'REJECT with concrete, actionable issues if anything material fails the brief; otherwise APPROVE. ' +
  'Read-only plus running tests: do not fix, commit, push, or post anything.'

// Model routing v3 (2026-07-08): sonnet builders (briefs are fully-specified), opus gates. Per-task override via tasks[i].model.
const results = await pipeline(
  tasks,
  (t, _orig, i) => {
    const opts = { label: `build:${i}`, phase: 'Build', schema: REPORT_SCHEMA, model: t.model || 'sonnet' }
    if (isolate) opts.isolation = 'worktree'
    return agent(builderPrompt(t.brief), opts)
  },
  async (report, t, i) => {
    if (!report) return { task: i, status: 'BLOCKED', issues: ['builder died or was skipped'], summary: '' }
    if (report.status === 'BLOCKED') {
      return { task: i, status: 'BLOCKED', issues: [], summary: report.summary, workdir: report.workdir, branch: report.branch }
    }
    let review = await agent(criticPrompt(t.brief, report), { label: `gate:${i}`, phase: 'Gate', schema: REVIEW_SCHEMA, model: 'opus' })
    if (review && review.verdict === 'REJECTED') {
      log(`chief-dispatch task ${i}: REJECTED (${review.issues.length} issue(s)) — one fix round`)
      const fixed = await agent(
        'You are an implementation worker fixing review issues on existing work. ' +
        `Work in ${report.workdir} on branch ${report.branch} — do NOT start over.\n\n` +
        `ORIGINAL BRIEF:\n${t.brief}\n\n` +
        `REVIEW ISSUES TO FIX (fix these and only these):\n- ${review.issues.join('\n- ')}\n\n` +
        'Same discipline: real verification output in `evidence`, conventional signed commits, no pushing or posting.',
        { label: `fix:${i}`, phase: 'Gate', schema: REPORT_SCHEMA, model: t.model || 'sonnet' },
      )
      review = fixed
        ? await agent(criticPrompt(t.brief, fixed), { label: `regate:${i}`, phase: 'Gate', schema: REVIEW_SCHEMA, model: 'opus' })
        : { verdict: 'REJECTED', issues: ['fix round produced no report'] }
    }
    const approved = review && review.verdict === 'APPROVED'
    return {
      task: i,
      status: approved ? report.status : 'BLOCKED',
      issues: approved ? [] : ((review && review.issues) || ['critic unavailable']),
      summary: report.summary,
      workdir: report.workdir,
      branch: report.branch,
    }
  },
)

const finished = (results || []).filter(Boolean)
log(`chief-dispatch: ${finished.filter((r) => r.status !== 'BLOCKED').length}/${tasks.length} task(s) passed the gate`)
return { tasks: finished }
