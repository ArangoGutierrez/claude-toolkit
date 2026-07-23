export const meta = {
  name: 'pr-review-fanout',
  description: 'Reviewer fan-out + per-finding confidence scoring for the /pr-review skill',
  whenToUse: 'Called by the /pr-review skill to run the reviewer fan-out and confidence scoring; not usually invoked directly.',
  phases: [
    { title: 'Review' },
    { title: 'Score' },
  ],
}

// INVARIANT: this workflow only dispatches reviewer/scorer agents and filters
// their returns. It performs no gh writes, no network, and no filesystem I/O of
// its own — so posting can never happen inside it. The prohibition clause
// (NO_POST_CLAUSE) is embedded verbatim in every reviewer prompt as defence in
// depth; the only outward-mutation string in this file is that prohibition.

const NO_POST_CLAUSE =
  'Do NOT post, comment, submit, push, or take any external action. Your deliverable is a ' +
  'findings report returned as your final message only.'

// False-positive guardrails — transcribed verbatim from the pr-review skill.
const GUARDRAILS = `Ignore likely false positives:
- Pre-existing issues; real issues on lines the PR did not modify.
- Something that looks like a bug but is not.
- Pedantic nitpicks a senior engineer wouldn't raise.
- Issues a linter/typechecker/compiler would catch (imports, type errors, formatting). Assume CI runs these separately; do not build or typecheck yourself.
- General quality gripes (coverage, docs) unless the relevant CLAUDE.md requires them.
- Issues called out in CLAUDE.md but explicitly silenced in code (e.g. a lint-ignore).
- Changes that are likely intentional or directly related to the broader change.`

// Confidence rubric — transcribed verbatim from the pr-review skill (step 6).
const RUBRIC = `- 0: Not confident. False positive under light scrutiny, or pre-existing.
- 25: Somewhat. Might be real, could be a false positive; unverified, or stylistic and not explicitly called out in CLAUDE.md.
- 50: Moderately. Verified real, but a nitpick or rare in practice; not very important.
- 75: Highly. Double-checked; likely hit in practice; current approach insufficient; or directly named in the relevant CLAUDE.md.
- 100: Certain. Confirmed definitely real and frequent; evidence directly confirms it.`

const FINDINGS_SCHEMA = {
  type: 'object',
  required: ['findings', 'degraded'],
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        required: ['file', 'line', 'description', 'category', 'severity', 'reason'],
        properties: {
          file: { type: 'string', description: 'repo-relative path' },
          line: { type: 'integer', description: 'NEW-file (RIGHT-side) line number' },
          description: { type: 'string', description: '1-2 sentences, bare — no (file:line) self-citation' },
          category: { type: 'string' },
          severity: { type: 'string', enum: ['must-fix', 'should-fix', 'consider'] },
          reason: { type: 'string' },
        },
      },
    },
    degraded: { type: 'boolean' },
  },
}

const SCORE_SCHEMA = {
  type: 'object',
  required: ['score', 'rationale'],
  properties: {
    score: { type: 'integer', minimum: 0, maximum: 100 },
    rationale: { type: 'string' },
  },
}

const SPECIALIST_AGENT_TYPE = {
  go: 'principal-engineer',
  k8s: 'principal-engineer',
  js: 'principal-engineer',
  python: 'principal-engineer',
  security: 'principal-engineer',
  test: 'qa-engineer',
}

// args can arrive as a JSON-encoded string on some invocation paths
// (observed live, scriptPath invocation 2026-07-19) — normalize first.
let input = args
if (typeof input === 'string') {
  try { input = JSON.parse(input) } catch (_e) {
    log('pr-review-fanout: args arrived as an unparseable string')
    input = null
  }
}
if (!input || typeof input !== 'object') {
  log('pr-review-fanout: no args object supplied — expected {diffPath, prNumber, ownerRepo, repoCheckout, domains, claudeMdPaths}')
  return { error: 'pr-review-fanout: args missing or unparseable' }
}

const diffPath = input.diffPath
if (!diffPath || typeof diffPath !== 'string') {
  log('pr-review-fanout: diffPath is required but absent')
  return { error: 'pr-review-fanout: diffPath is required' }
}

const prNumber = input.prNumber
const ownerRepo = input.ownerRepo ? String(input.ownerRepo) : '(unknown repo)'
const repoCheckout = input.repoCheckout ? String(input.repoCheckout) : '(no checkout provided)'
const domains = Array.isArray(input.domains) ? Array.from(new Set(input.domains.map(String))) : []
const claudeMdPaths = Array.isArray(input.claudeMdPaths) ? input.claudeMdPaths.map(String) : []

// Shared tail for every reviewer prompt — anchoring rule, the degraded
// convention, the false-positive guardrails, and the prohibition clause.
const reviewerFooter =
  'Report only defects you can anchor to a specific changed file and NEW-file (RIGHT-side) line; ' +
  'return an empty findings array when nothing real is wrong; never invent findings.\n\n' +
  'Set the top-level "degraded" field to false unless a checklist file you were instructed to read is missing (then set it true).\n\n' +
  GUARDRAILS + '\n\n' +
  NO_POST_CLAUSE

const claudeMdList = claudeMdPaths.length ? claudeMdPaths.join('\n') : '(none provided)'

const genericReviewers = [
  {
    name: 'claude-md-adherence',
    prompt:
      'You are reviewing a pull request for CLAUDE.md adherence. Flag ONLY changes that violate something the ' +
      'governing CLAUDE.md files explicitly call out — nothing they do not name.\n' +
      `The CLAUDE.md files that govern this PR are at:\n${claudeMdList}\n` +
      `Read those files and the PR diff at ${diffPath}; flag a changed line only when a CLAUDE.md rule explicitly names the issue.\n\n` +
      reviewerFooter,
  },
  {
    name: 'bug-scan',
    prompt:
      'You are reviewing a pull request with a shallow bug scan of the CHANGED LINES ONLY in the diff at ' +
      `${diffPath}. Look for large, real bugs — logic errors, nil/undefined dereferences, off-by-one, broken ` +
      'control flow, resource leaks — not nitpicks.\n\n' +
      reviewerFooter,
  },
  {
    name: 'git-history',
    prompt:
      'You are reviewing a pull request in light of the git history of the modified code. The repository is ' +
      `checked out at ${repoCheckout}; use read-only git blame and git log there to see how the changed lines ` +
      'evolved, then flag bugs the historical context reveals (e.g. a change that reintroduces a previously fixed ' +
      `bug, or drops a guard added on purpose). The PR diff is at ${diffPath}.\n\n` +
      reviewerFooter,
  },
  {
    name: 'prior-prs',
    prompt:
      'You are reviewing a pull request by mining prior PRs that touched the same files. Using read-only gh ' +
      'commands only (gh pr list and gh pr view are permitted READS — never a write verb), find earlier PRs ' +
      `against the files this PR changes and surface review comments made there that also apply to this change. ` +
      `The current PR is #${prNumber} in ${ownerRepo}; look at OTHER (prior) PRs, not this one. The repository is ` +
      `checked out at ${repoCheckout}; the PR diff is at ${diffPath}.\n\n` +
      reviewerFooter,
  },
  {
    name: 'code-comments',
    prompt:
      'You are reviewing a pull request against the code comments in the modified files. Read the changed files ' +
      `(repository checked out at ${repoCheckout}) and their surrounding comments and docstrings, then flag ` +
      `changes that violate guidance documented in those comments. The PR diff is at ${diffPath}.\n\n` +
      reviewerFooter,
  },
]

const specialistPrompt = (domain) =>
  `You are the ${domain} specialist reviewer in a PR review fan-out.\n` +
  `First read ~/.claude/skills/${domain}-review/SKILL.md (its "Dispatched mode" section) and ` +
  `~/.claude/skills/${domain}-review/references/${domain}-review-checklist.md to load the review checklist.\n` +
  `If the checklist file ~/.claude/skills/${domain}-review/references/${domain}-review-checklist.md is not on ` +
  'disk, proceed using your domain lens from this prompt alone and set the top-level "degraded" field to true in ' +
  'your return.\n' +
  `Review ONLY the changed lines in the PR diff at ${diffPath}. Anchor every finding to a specific changed file ` +
  'and its NEW-file (RIGHT-side) line.\n\n' +
  reviewerFooter

const securityPrompt = () =>
  'You are the security specialist reviewer in a PR review fan-out. You have NO dedicated skill file; seed your ' +
  'review from ~/.claude/rules/security.md.\n' +
  `Review ONLY the changed lines in the PR diff at ${diffPath}. Focus on: secrets or credentials in the diff, ` +
  'injection sinks, authentication/authorization logic changes, unsafe deserialization, supply-chain risk (new ' +
  'dependencies, install scripts), container privilege, and RBAC wildcards. Anchor every finding to a specific ' +
  'changed file and its NEW-file (RIGHT-side) line.\n\n' +
  reviewerFooter

const specialistReviewers = domains
  .filter((d) => SPECIALIST_AGENT_TYPE[d])
  .map((d) => ({
    name: `${d}-specialist`,
    prompt: d === 'security' ? securityPrompt() : specialistPrompt(d),
    agentType: SPECIALIST_AGENT_TYPE[d],
  }))

const reviewers = genericReviewers.concat(specialistReviewers)

const scorePrompt = (f, reviewerName) =>
  'Score, from 0 to 100, your confidence that this PR-review finding is a real defect worth posting. Use this ' +
  'rubric verbatim:\n\n' +
  RUBRIC + '\n\n' +
  'Finding under review:\n' +
  `- file: ${f.file}\n` +
  `- line: ${f.line}\n` +
  `- severity: ${f.severity}\n` +
  `- category: ${f.category}\n` +
  `- description: ${f.description}\n` +
  `- reason flagged: ${f.reason}\n` +
  `- raised by reviewer: ${reviewerName}\n\n` +
  'Apply these false-positive guardrails when scoring:\n' +
  GUARDRAILS + '\n\n' +
  'If this finding was flagged for CLAUDE.md adherence, first confirm the relevant CLAUDE.md actually calls the ' +
  'issue out; if it does not, score it low. Specialist findings get NO special treatment — the same threshold and ' +
  'the same rubric apply to every finding regardless of which reviewer produced it.\n' +
  'Return an integer score (0-100) and a one-line rationale.'

log(`pr-review-fanout: ${reviewers.length} reviewer(s) (${genericReviewers.length} generic + ${specialistReviewers.length} specialist), diff at ${diffPath}`)

const degradedReviewers = []

const results = await pipeline(
  reviewers,
  (r) => {
    const opts = { label: `review:${r.name}`, phase: 'Review', schema: FINDINGS_SCHEMA, model: 'sonnet' }
    if (r.agentType) opts.agentType = r.agentType
    return agent(r.prompt, opts)
  },
  (review, r) => {
    if (review && review.degraded === true) degradedReviewers.push(r.name)
    if (!review || !Array.isArray(review.findings) || review.findings.length === 0) return []
    return parallel(review.findings.map((f) => () =>
      agent(
        scorePrompt(f, r.name),
        { label: `score:${f.file}:${f.line}`, phase: 'Score', schema: SCORE_SCHEMA, model: 'haiku' },
      ).then((s) => ({
        ...f,
        score: (s && typeof s.score === 'number') ? s.score : 0,
        scoreRationale: (s && s.rationale) || '',
        reviewer: r.name,
      })),
    ))
  },
)

const scored = (results || []).filter(Boolean).flat().filter(Boolean)
const survivors = scored.filter((f) => typeof f.score === 'number' && f.score >= 80)
const rankOf = (s) => (s === 'must-fix' ? 0 : s === 'should-fix' ? 1 : s === 'consider' ? 2 : 3)
survivors.sort((a, b) => rankOf(a.severity) - rankOf(b.severity))

log(
  `pr-review-fanout: scored ${scored.length} finding(s), ${survivors.length} survived (score >= 80)` +
  (degradedReviewers.length ? `; degraded reviewers: ${degradedReviewers.join(', ')}` : ''),
)

return {
  findings: survivors,
  degradedReviewers,
  counts: { raw: scored.length, survived: survivors.length },
}
