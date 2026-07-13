# Python Review Checklist

Each item names a concrete signal to look for in the diff, why it bites, and what
right looks like. Prefer edge cases and error paths over happy paths. Flag only
what you can point at in the changed lines.

## 1. Core Python correctness & typing

- [ ] **Mutable default arguments** (`def f(x=[])`, `def f(cfg={})`). The default is
  created once and shared across calls, so mutations leak between callers.
  Right: default to `None`, build the container inside the body.
- [ ] **Swallowed errors** — bare `except:` or `except Exception: pass` (or
  `except ...: continue` that discards the error). Hides real failures and makes
  the loop above look healthy. Right: catch the narrowest type, log with context,
  re-raise or handle deliberately.
- [ ] **Resources without context managers** — files, sockets, locks, DB sessions,
  or CUDA streams opened without `with`. On an exception the handle leaks.
  Right: `with open(...) as f:` / `contextlib.closing` / an async context manager.
- [ ] **Implicit `Any` at public API boundaries** — a new public function, method,
  or return value with no annotation (pyright strict flags `reportMissingParameterType`
  / `reportUnknownParameterType`). Callers lose all type safety at the seam.
  Right: annotate params and returns on public surfaces; private helpers can wait.
- [ ] **pydantic: validation must run where data enters.** `Model.model_construct()`
  / `.construct()` skips validation — correct only for already-trusted data. At any
  boundary that ingests external/model/user data, use `model_validate` /
  `model_validate_json`. Flag `construct` on untrusted input.
- [ ] **pydantic alias vs field-name init trap.** A model with per-field
  `validation_alias` (or `populate_by_name=False`) plus `extra="ignore"` silently
  DROPS kwargs passed by field name — the field keeps its default and nothing errors.
  Right: pass by alias, or set `populate_by_name=True`; a test that constructs by
  field name proves it round-trips.
- [ ] **Eager logging in hot paths** — `logger.debug(f"... {expensive()}")`
  evaluates the f-string (and `expensive()`) even when the level is disabled.
  Right: lazy `logger.debug("... %s", value)`; the arg is formatted only if emitted.
- [ ] **Function-level imports without a stated reason.** Imports inside a function
  re-run on every call and hide dependencies (ruff PLC0415). Right: module-level
  imports; a deferred import is acceptable only to break a cycle or gate an optional
  dep — and says so in a comment.
- [ ] **`is` / `is not` on literals** (`x is "y"`, `n is 0`). Identity, not equality;
  works by CInterpreter caching accident and breaks on other values. Right: `==` /
  `!=`. Reserve `is` for `None`, `True`, `False`, and sentinels.
- [ ] **Timezone-naive datetimes crossing a boundary.** `datetime.now()` /
  `utcnow()` (no tzinfo) serialized, compared, or stored against aware values
  produces silent off-by-hours bugs and `TypeError` on mixed comparison.
  Right: `datetime.now(timezone.utc)`; keep everything aware end to end.

## 2. Async correctness

- [ ] **Blocking calls inside `async def`** — `requests.*`, `time.sleep`, a sync DB
  driver, or heavy CPU work. They stall the entire event loop, not just one task.
  Right: `httpx.AsyncClient`, `asyncio.sleep`, an async driver, or push the blocking
  call to `asyncio.to_thread(...)`.
- [ ] **Forgotten `await`.** A coroutine called without `await` never runs and
  returns a coroutine object that is often silently truthy. pyright surfaces this
  only under strict `reportUnusedCoroutine`. Right: `await` it, or schedule with a
  kept task reference.
- [ ] **`asyncio.gather` without `return_exceptions`.** The default cancels every
  sibling on the first exception, dropping partial results you meant to keep.
  Right: `gather(..., return_exceptions=True)` and inspect each result when partial
  failure is tolerable; leave the default only when fail-fast is intended.
- [ ] **Fire-and-forget tasks with no reference.** `asyncio.create_task(...)` whose
  result is not stored can be garbage-collected mid-flight, and its exception is
  swallowed. Right: keep the task in a set (discard on done) and attach a
  `add_done_callback` / `try/except` that surfaces failures.
- [ ] **Cancellation not handled around cleanup.** A `CancelledError` raised through
  a naive `except Exception` (which does NOT catch it in 3.8+, but a bare `except:`
  does) or during teardown can leave resources half-closed. Right: cleanup in
  `finally`; re-raise `CancelledError`; use `asyncio.shield` for must-finish work.
- [ ] **Event-loop-per-thread confusion.** `asyncio.run()` inside an already-running
  loop, or sharing one loop/`AsyncClient` across threads, raises at runtime or
  corrupts state. Right: one loop per thread; `run_coroutine_threadsafe` to hand
  work to another loop.

## 3. Agent-building invariants (LLM tool-use loops)

Each item is a detectable code signal — not "the agent should be safe."

- [ ] **Iteration bound present AND realistic.** The tool-use `while` loop has an
  explicit max-iterations guard. Bug both ways: no bound (runaway/cost blowout),
  or a bound so low the loop always hits it before convergence — a silent failure
  that looks like a bad answer. Right: a named bound sized to observed convergence,
  logged when reached.
- [ ] **Separate budget / cost guard.** Beyond the iteration count, a token-or-
  wall-clock budget that stops the loop. Iterations alone don't bound cost when one
  step balloons context. Right: accumulate token/time and break when the budget
  trips.
- [ ] **Tool-call arguments validated before execution.** Arguments the model
  produced are checked against the tool's schema (pydantic / jsonschema) before the
  tool runs. Right: parse-and-validate; reject and feed the error back rather than
  calling with malformed args.
- [ ] **Model output parsed strictly — never `eval`/`exec`.** `eval(`, `exec(`,
  `pickle.loads`, or `subprocess(..., shell=True)` on model output is remote code
  execution — must-fix. Right: `json.loads` + schema validation + a bounded retry on
  parse failure.
- [ ] **Tool results treated as untrusted (prompt-injection surface).** A retrieved
  document, web page, or tool output must not be concatenated into a shell command,
  used to overwrite the system prompt, or auto-approved as an instruction. Right:
  keep tool output as data; quote/escape before any shell; never let it redirect the
  loop's control flow.
- [ ] **Retry/backoff with jitter on provider calls, honoring rate limits.** Bare
  retries with no delay hammer a rate-limited endpoint; fixed delay causes thundering
  herds. Right: exponential backoff + jitter; read `Retry-After` / the 429 response
  before retrying.
- [ ] **Context-window overflow handled explicitly.** A stated truncation or
  summarization strategy when history grows, not an unbounded list appended every
  turn (which eventually 400s or silently drops the system prompt). Right: measure
  tokens and truncate/summarize on a rule.
- [ ] **Streaming partial output assembled safely.** Streamed deltas accumulated and
  the terminal/error chunk checked before the result is used; a dropped final chunk
  or ignored error event yields truncated output treated as complete.
- [ ] **Secrets never interpolated into prompts or logged.** An API key / token in
  the prompt string or in a trace/`logger` call leaks it to the provider and the log
  sink — must-fix. Right: keep credentials in the client/transport layer, never in
  message content or traces.
- [ ] **Deterministic replay hooks where evals depend on them.** When a run is
  replayed or graded, the seed and `temperature` (and model id) are recorded.
  Otherwise the eval is not reproducible. Right: log the sampling params with the
  transcript.

## 4. ML pipeline reproducibility & serialization safety

- [ ] **`torch.load` without `weights_only=True` on any non-self-produced artifact —
  must-fix.** The default unpickles arbitrary objects → code execution from a
  malicious checkpoint. Right: `torch.load(path, weights_only=True)`, or load
  `safetensors` for weights.
- [ ] **Prefer `safetensors` for weights.** A `.pt`/`.pth`/`.bin` weight file shared
  or downloaded is a pickle; `safetensors` cannot execute code. Flag new pickle-based
  weight IO on untrusted paths.
- [ ] **`pickle.load` / `pickle.loads` of untrusted data — must-fix.** Same RCE
  surface as above for any externally sourced pickle. Right: a data format that does
  not execute code (JSON, parquet, safetensors, msgpack with a schema).
- [ ] **Seeds set and recorded where results are compared.** `random`, `numpy`, and
  the framework (`torch.manual_seed` / `torch.cuda.manual_seed_all`) all seeded, and
  the seed logged. A missing framework seed makes a "reproducible" run drift.
- [ ] **Dataset version / hash recorded for training & eval.** The data identity
  (hash, version tag, or snapshot id) is captured so a result maps back to its
  inputs. Right: record it alongside metrics; don't rely on a mutable path.
- [ ] **Train/eval leakage.** Dedup before splitting; split BEFORE fitting
  transforms (scaler/encoder/vectorizer fit on the full set leaks test statistics);
  no test rows in `fit`. Any of these inflates metrics.
- [ ] **Checkpoint resume restores optimizer & scheduler.** Reloading only model
  weights (not optimizer momentum / LR-scheduler / scaler state) silently changes
  the trajectory on resume. Right: save and restore all of them together.
- [ ] **Nondeterminism flagged when reproducibility is claimed.** Multi-worker
  `DataLoader` without a `worker_init_fn`/generator seed, or nondeterministic CUDA
  ops, breaks bit-exact repro. Right: seed workers, set
  `torch.use_deterministic_algorithms(True)` when the claim requires it.
- [ ] **Eval loop uses `no_grad` / `inference_mode`, and no retained graph.** Missing
  `torch.no_grad()` in eval retains the autograd graph and leaks GPU memory; holding
  a loss tensor (not `.item()`/`.detach()`) or an unbounded cache does the same.

## 5. Packaging & environment

- [ ] **Applications pin; libraries range.** An application/service commits a
  lockfile (`uv.lock`, `poetry.lock`, or `requirements.txt` with hashes); a library
  declares compatible ranges. A pinned library over-constrains its consumers; an
  unpinned app is not reproducible.
- [ ] **New heavyweight dependency questioned.** A large or transitive-heavy dep
  added for a small need (pulling `torch`/`pandas` for one helper) inflates images
  and attack surface. Right: justify it or use the stdlib / a lighter package.
- [ ] **Optional deps guarded with an actionable message.** An `import optional_pkg`
  in a rarely-used path should raise an ImportError that names the extra to install,
  not a bare `ModuleNotFoundError` deep in a stack trace.
- [ ] **`python_requires` consistent with syntax used.** Match statements, `X | Y`
  unions, `tomllib`, etc. used while `requires-python` still allows an older version
  breaks that interpreter at import time.
- [ ] **No `sys.path` hacks.** `sys.path.insert(...)` / `sys.path.append(...)` to
  reach a sibling package hides packaging problems and breaks under installation.
  Right: a proper package/entry-point or editable install.
- [ ] **Editable-install shadowing awareness.** With multiple checkouts of one
  package, an editable install on `sys.meta_path` shadows `PYTHONPATH`, so imports
  may load a different checkout than intended. Flag test/setup code that assumes
  `PYTHONPATH` wins.

## Review discipline

- Review only changed lines unless a full-file review is explicitly requested.
- Don't flag formatting that black/ruff already normalize.
- Don't demand annotations on private helpers in an untyped codebase — boundaries
  first.
- Every finding cites the checklist item that flagged it and a concrete `file:line`.
