#!/usr/bin/env node
//
// workflow-harness.js — RUN a workflow script with stubbed agents and observe
// its behaviour. `check-workflow-syntax.sh` only PARSES a workflow; a parse
// check cannot catch a broken abort guard, so a test built on it is theater.
// This harness compiles the same AsyncFunction body that the Workflow tool
// executes, injects deterministic stubs for every global, and prints what the
// workflow returned, which agents it launched, and what it logged.
//
// Usage:  node scripts/workflow-harness.js <workflow.js> <scenario.json>
//
// Exit codes: 0 the workflow returned; 1 the workflow threw, or the harness
// could not run it (usage or scenario error). The JSON report prints on stdout
// in both of those cases; harness diagnostics go to stderr.
//
// ---------------------------------------------------------------------------
// Scenario schema (a JSON object)
// ---------------------------------------------------------------------------
//   {
//     "args":   <any>,          // becomes the workflow's `args` global
//     "budget": <any>,          // becomes the workflow's `budget` global
//     "agent": {
//       "default":       <any>, // result for a label with no better match;
//                               // omit it (or set null) for the death case,
//                               // where every agent() resolves to null
//       "byLabel":       { "<exact label>":  <any> },
//       "byLabelPrefix": { "<label prefix>": <any> }
//     }
//   }
//
// Result resolution for one agent() call, first match wins:
//   1. agent.byLabel[label]               — exact label
//   2. agent.byLabelPrefix[p], longest p  — label.startsWith(p)
//   3. agent.default                      — otherwise (defaults to null)
//
// A resolved result is deep-copied per call, so a workflow that mutates one
// agent's result cannot change what a later call receives.
//
// ---------------------------------------------------------------------------
// Report schema (one JSON object on stdout)
// ---------------------------------------------------------------------------
//   {
//     "return": <workflow return value, or null when it threw>,
//     "threw":  <error message, present only when the workflow threw>,
//     "agents": ["<label>", ...],   // in call order
//     "phases": ["<name>", ...],    // in call order
//     "logs":   ["<line>", ...]     // in call order
//   }
//
// ---------------------------------------------------------------------------
// Stub semantics — these mirror what the Workflow tool documents
// ---------------------------------------------------------------------------
//   agent(prompt, opts)   resolves to the scenario's result and NEVER throws.
//                         A dead agent is a resolved `null`, which is exactly
//                         how the real tool reports agent death.
//   pipeline(items, ...stages)
//                         runs each item through all stages independently,
//                         with no barrier between stages. A stage that throws
//                         drops that one item to null; other items continue.
//                         Stage signature: (value, originalItem, index).
//   parallel(thunks)      runs every thunk concurrently and resolves a failing
//                         thunk to null instead of rejecting the whole batch.
//   log(msg)              records a line. It never writes to stdout, which
//                         carries the single JSON report.
//   phase(name)           records a phase transition.
//   workflow(name, args)  records the call and resolves to null. A nested
//                         workflow is out of scope for this harness.

'use strict'

const fs = require('fs')
const path = require('path')

function die(msg) {
  process.stderr.write(`workflow-harness: ${msg}\n`)
  process.exit(1)
}

const [workflowPath, scenarioPath] = process.argv.slice(2)
if (!workflowPath || !scenarioPath) {
  die('usage: node scripts/workflow-harness.js <workflow.js> <scenario.json>')
}
for (const p of [workflowPath, scenarioPath]) {
  if (!fs.existsSync(p)) die(`no such file: ${p}`)
}

let scenario
try {
  scenario = JSON.parse(fs.readFileSync(scenarioPath, 'utf8'))
} catch (e) {
  die(`scenario is not valid JSON (${scenarioPath}): ${e.message}`)
}
if (!scenario || typeof scenario !== 'object' || Array.isArray(scenario)) {
  die(`scenario must be a JSON object, got ${Array.isArray(scenario) ? 'array' : typeof scenario}`)
}

const agentSpec = scenario.agent || {}
const byLabel = agentSpec.byLabel || {}
const byLabelPrefix = agentSpec.byLabelPrefix || {}
// Longest prefix first, so a specific prefix beats a general one.
const prefixes = Object.keys(byLabelPrefix).sort((a, b) => b.length - a.length)

const copy = (v) => (v === undefined || v === null ? null : JSON.parse(JSON.stringify(v)))

function resolveAgentResult(label) {
  if (Object.prototype.hasOwnProperty.call(byLabel, label)) return copy(byLabel[label])
  for (const p of prefixes) {
    if (label.startsWith(p)) return copy(byLabelPrefix[p])
  }
  return copy(agentSpec.default)
}

const agents = []
const phases = []
const logs = []

const agent = async (_prompt, opts) => {
  const label = (opts && opts.label) ? String(opts.label) : '<unlabeled>'
  agents.push(label)
  return resolveAgentResult(label)
}

const pipeline = async (items, ...stages) => Promise.all(
  (items || []).map(async (item, i) => {
    let value = item
    for (const stage of stages) {
      try {
        value = await stage(value, item, i)
      } catch (_e) {
        return null
      }
    }
    return value
  }),
)

const parallel = async (thunks) => Promise.all(
  (thunks || []).map(async (t) => {
    try {
      return await t()
    } catch (_e) {
      return null
    }
  }),
)

const log = (msg) => { logs.push(String(msg)) }
const phase = (name) => { phases.push(String(name)) }
const nestedWorkflow = async (name) => { agents.push(`workflow:${name}`); return null }

const src = fs.readFileSync(workflowPath, 'utf8')
if (!/^export const meta = \{/m.test(src)) {
  die(`${path.basename(workflowPath)}: missing \`export const meta = {\` literal`)
}
// Same transform as scripts/check-workflow-syntax.sh: strip the ESM export so
// the body compiles as an AsyncFunction, which makes top-level await and
// top-level return legal — exactly the Workflow tool's execution context.
const body = src.replace(/^export const meta/m, 'const meta')
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor

let fn
try {
  fn = new AsyncFunction('agent', 'pipeline', 'parallel', 'log', 'phase', 'args', 'budget', 'workflow', body)
} catch (e) {
  die(`${path.basename(workflowPath)}: failed to compile: ${e.message}`)
}

const emit = (obj) => { process.stdout.write(`${JSON.stringify(obj)}\n`) }

fn(agent, pipeline, parallel, log, phase, scenario.args, scenario.budget, nestedWorkflow)
  .then((ret) => {
    emit({ return: ret === undefined ? null : ret, agents, phases, logs })
  })
  .catch((e) => {
    emit({ return: null, threw: String((e && e.message) || e), agents, phases, logs })
    process.exitCode = 1
  })
