export const meta = {
  name: 'review-verify',
  description: 'Review a diff or path across dimensions, then adversarially verify every finding',
  whenToUse: 'Reviewing a branch, diff, or directory when findings must survive an adversarial verification pass before being reported',
  phases: [
    { title: 'Review', detail: 'one finder agent per dimension' },
    { title: 'Verify', detail: 'one adversarial refuter per finding' },
  ],
}

const FINDINGS_SCHEMA = {
  type: 'object',
  required: ['findings'],
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        required: ['file', 'line', 'title', 'detail', 'severity'],
        properties: {
          file: { type: 'string' },
          line: { type: 'integer' },
          title: { type: 'string' },
          detail: { type: 'string' },
          severity: { type: 'string', enum: ['critical', 'major', 'minor'] },
        },
      },
    },
  },
}

const VERDICT_SCHEMA = {
  type: 'object',
  required: ['refuted', 'reason'],
  properties: {
    refuted: { type: 'boolean' },
    reason: { type: 'string' },
  },
}

const DEFAULT_DIMENSIONS = [
  'correctness bugs and logic errors',
  'security vulnerabilities, injection risks, and secret exposure',
  'test quality: theater tests, tautological assertions, missing coverage of changed behavior',
]

// args can arrive as a JSON-encoded string on some invocation paths
// (observed live, scriptPath invocation 2026-07-19) — normalize first.
let input = args
if (typeof input === 'string') {
  try { input = JSON.parse(input) } catch (_e) {
    log('review-verify: args arrived as an unparseable string — using defaults')
    input = null
  }
}

const target = (input && input.target)
  ? String(input.target)
  : 'the uncommitted working diff of the current repository (git diff HEAD; fall back to the last commit if the working tree is clean)'
const dimensions = (input && Array.isArray(input.dimensions) && input.dimensions.length > 0)
  ? input.dimensions.map(String)
  : DEFAULT_DIMENSIONS

log(`review-verify: ${dimensions.length} dimension(s) over: ${target}`)

// Abort guard (2026-07-31). `agent()` resolves to null when an agent dies — it does not throw —
// so without this counter a run where every finder died is indistinguishable from a clean review.
// INVARIANT:
//   1. when EVERY finder returns null, the return value carries a truthy `error` plus
//      `deadFinders` and `attemptedFinders`;
//   2. when at least one finder RETURNS A RESULT, the return value carries no `error`, even if
//      that result has zero findings, and even if every finding is later refuted.
// `liveFinders` counts finders that returned an object, NOT finders that found something. That
// distinction is the whole guard: keying on confirmed.length would turn every clean review into
// an error. The count increments in stage 1, where the null originates, so the guard does not
// depend on whether pipeline runs stage 2 for a null-valued item.
let liveFinders = 0

// Model routing v5 (2026-08-05): opus finders, opus refuters. Sonnet left the routing tables by user policy. Override via args.finderModel / args.verifierModel.
const results = await pipeline(
  dimensions,
  (dim) => agent(
    `You are a code reviewer focused exclusively on: ${dim}.\n` +
    `Review target: ${target}.\n` +
    'Inspect the target directly (git commands for diffs, Read/Grep for files). ' +
    'Report only defects you can anchor to a specific file and line, each with a concrete failure scenario in `detail`. ' +
    'No style nits unless the dimension explicitly asks. ' +
    'If you find nothing real, return an empty findings array — never invent findings.',
    { label: `review:${dim.split(/[\s:]/)[0]}`, phase: 'Review', schema: FINDINGS_SCHEMA, model: (input && input.finderModel) || 'opus' },
  ).then((review) => { if (review) liveFinders++; return review }),
  (review, dim) => {
    if (!review || !Array.isArray(review.findings) || review.findings.length === 0) return []
    return parallel(review.findings.map((f) => () =>
      agent(
        'Adversarially verify one code-review finding. Your default position: the finding is WRONG.\n' +
        `Finding [${f.severity}] at ${f.file}:${f.line} — ${f.title}\n` +
        `Claimed detail: ${f.detail}\n` +
        'Read the actual code at that location and try to REFUTE it: is the claimed defect reachable, ' +
        'actually incorrect, and actually at that location? ' +
        'Set refuted=true unless the finding survives your best attempt to kill it; explain in `reason`.',
        { label: `verify:${f.file}:${f.line}`, phase: 'Verify', schema: VERDICT_SCHEMA, model: (input && input.verifierModel) || 'opus' },
      ).then((v) => ({ ...f, dimension: dim, verdict: v })),
    ))
  },
)

const flat = (results || []).filter(Boolean).flat().filter(Boolean)
const confirmed = flat.filter((f) => f.verdict && f.verdict.refuted === false)
const rankOf = (s) => (s === 'critical' ? 0 : s === 'major' ? 1 : s === 'minor' ? 2 : 3)
confirmed.sort((a, b) => rankOf(a.severity) - rankOf(b.severity))
log(`review-verify: ${confirmed.length}/${flat.length} finding(s) survived adversarial verification`)

const out = { target, dimensions, confirmed, refutedCount: flat.length - confirmed.length }
// `dimensions.length > 0` is DEFENSIVE ONLY — it cannot be false today. The
// DEFAULT_DIMENSIONS fallback above yields 3 entries for an empty, absent or
// non-array `args.dimensions`, so `dimensions` is never empty here. Keep the
// check so a future path that legitimately runs zero finders cannot report
// "all 0 of 0 finder agent(s) died", but do not read it as reachable today.
if (dimensions.length > 0 && liveFinders === 0) {
  const deadFinders = dimensions.length - liveFinders
  out.error = `review-verify: all ${deadFinders} of ${dimensions.length} finder agent(s) died; no review ran`
  out.deadFinders = deadFinders
  out.attemptedFinders = dimensions.length
  log(out.error)
}
return out
