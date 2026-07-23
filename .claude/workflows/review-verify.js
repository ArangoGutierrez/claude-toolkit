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

// Model routing v3 (2026-07-08): sonnet finders, opus refuters (gates keep their tier). Override via args.finderModel / args.verifierModel.
const results = await pipeline(
  dimensions,
  (dim) => agent(
    `You are a code reviewer focused exclusively on: ${dim}.\n` +
    `Review target: ${target}.\n` +
    'Inspect the target directly (git commands for diffs, Read/Grep for files). ' +
    'Report only defects you can anchor to a specific file and line, each with a concrete failure scenario in `detail`. ' +
    'No style nits unless the dimension explicitly asks. ' +
    'If you find nothing real, return an empty findings array — never invent findings.',
    { label: `review:${dim.split(/[\s:]/)[0]}`, phase: 'Review', schema: FINDINGS_SCHEMA, model: (input && input.finderModel) || 'sonnet' },
  ),
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
return { target, dimensions, confirmed, refutedCount: flat.length - confirmed.length }
