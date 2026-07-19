export const meta = {
  name: 'weekly-audit',
  description: 'Parallel repo hygiene sweep — config audit, eval suite, docs drift, dead references — synthesized into one report',
  whenToUse: 'Recurring (cron) or on-demand health check of a Claude Code configuration repo',
  phases: [
    { title: 'Sweep', detail: 'four parallel auditors' },
    { title: 'Synthesize', detail: 'one prioritized report' },
  ],
}

const AUDIT_SCHEMA = {
  type: 'object',
  required: ['area', 'ok', 'issues'],
  properties: {
    area: { type: 'string' },
    ok: { type: 'boolean' },
    issues: {
      type: 'array',
      items: {
        type: 'object',
        required: ['severity', 'title', 'detail'],
        properties: {
          severity: { type: 'string', enum: ['critical', 'warning', 'info'] },
          title: { type: 'string' },
          detail: { type: 'string' },
        },
      },
    },
  },
}

const AREAS = [
  {
    key: 'config',
    prompt: 'Audit this repository Claude Code config surface (.claude/): permissions for over-broad allows, ' +
      'hooks for injection sinks and unquoted variables, settings hygiene. ' +
      'If the repo ships a config-audit skill (.claude/skills/config-audit/scripts/scan-config.sh), run it against .claude and include its findings.',
  },
  {
    key: 'evals',
    prompt: 'If this repository has an eval suite (.claude/evals/ or scripts/run-evals.sh), run it and report every failure with its real output. ' +
      'If no eval suite exists, report ok=true with a single info issue noting the absence.',
  },
  {
    key: 'docs-drift',
    prompt: 'Check documentation drift: if mkdocs.yml exists, verify every nav entry resolves to an existing file under docs/. ' +
      'First run git status --porcelain and note which generated outputs are already locally modified. ' +
      'Re-run every docs generator the repo ships (scripts/gen-*.sh) ONLY for outputs that were UNMODIFIED before the run; report a warning per file that changes (git diff --stat after each run), then restore just those with git checkout -- <file>. ' +
      'A generated file with pre-existing uncommitted modifications must NOT be regenerated or restored — report it as a warning ("drift-unknown: file locally modified") instead of touching it.',
  },
  {
    key: 'dead-refs',
    prompt: 'Scan .claude/ for dead references: hooks listed in settings.json whose script files do not exist, ' +
      'skills whose SKILL.md references missing files, commands invoking skills that do not exist. Report each as a warning.',
  },
]

phase('Sweep')
const sweeps = (await parallel(AREAS.map((a) => () =>
  agent(
    `${a.prompt}\nSet area="${a.key}". Set ok=true ONLY if you actually ran the relevant checks and they passed — absence of evidence is not a pass.`,
    { label: `audit:${a.key}`, phase: 'Sweep', schema: AUDIT_SCHEMA },
  ),
))).filter(Boolean)

if (sweeps.length === 0) {
  return { ok: false, areas: 0, issues: [], report: 'weekly-audit: every sweep agent failed — no results' }
}

const issues = sweeps.flatMap((s) => (s.issues || []).map((i) => ({ area: s.area, ...i })))

phase('Synthesize')
const report = await agent(
  'Write a short prioritized hygiene report (markdown, critical first, one line per issue, ' +
  'end with a one-paragraph overall assessment) from this audit sweep JSON:\n' +
  JSON.stringify({ sweeps, issues }, null, 2),
  { label: 'synthesize', phase: 'Synthesize' },
)

const ok = sweeps.length === AREAS.length && sweeps.every((s) => s.ok) && issues.every((i) => i.severity === 'info')
log(`weekly-audit: ${sweeps.length}/4 sweeps completed, ${issues.length} issue(s), ok=${ok}`)
return { ok, areas: sweeps.length, issues, report }
