# JS / TypeScript / Node Review Checklist

Each item: **what to look for** → *why it bites* → what right looks like.
Category tags map to the report schema: correctness / security / performance / maintainability.

## 1. Async correctness

- [ ] **Floating promises** — a promise created but never `await`ed and with no `.catch()`,
  especially in event handlers and fire-and-forget calls.
  *Why it bites:* the rejection becomes an unhandled rejection; the error is invisible and
  ordering is nondeterministic. Right: `await` it, or `.catch(handler)`, or explicitly
  `void promise` only when the fire-and-forget is intentional and self-handling. (correctness)
- [ ] **`async` callbacks passed to non-awaiting APIs** — `array.forEach(async …)`,
  `emitter.on('x', async …)`, `setTimeout(async …)`.
  *Why it bites:* the caller ignores the returned promise, so errors are swallowed and the
  loop does not wait. Right: `for…of` with `await`, or `Promise.all(array.map(async …))`. (correctness)
- [ ] **Sequential awaits that are independent** — `const a = await f(); const b = await g();`
  where `f`/`g` don't depend on each other.
  *Why it bites:* needless latency (serial round-trips). Right: `const [a, b] = await Promise.all([f(), g()])`. (performance)
- [ ] **`Promise.all` where partial failure must not abort the rest** — batch work where one
  rejection should not cancel siblings. Right: `Promise.allSettled` and inspect each result. (correctness)
- [ ] **No process-level rejection/exception handler** in an entrypoint — missing
  `process.on('unhandledRejection', …)` / `'uncaughtException'`. Right: log and exit or route
  to the observability path; don't leave the default. (correctness)
- [ ] **Race on shared state across an `await`** — read-modify-write of a shared variable/map
  spanning an `await` boundary. *Why it bites:* interleaving corrupts state (check-then-act).
  Right: capture the value before awaiting, or serialize with a lock/queue. (correctness)
- [ ] **Long-running fetch with no cancelation** — `fetch`/network calls with no
  `AbortController` / timeout. Right: pass `signal`, wire a timeout, cancel on teardown. (correctness)
- [ ] **Async constructor anti-pattern** — a constructor that kicks off async work and leaves
  the object half-initialized. Right: a static async factory (`static async create()`). (maintainability)
- [ ] **Error swallowing** — `try { … } catch { return [] }` / returning a default on error
  with no log or rethrow. *Why it bites:* failures masquerade as empty success. Right: log
  and rethrow, or return a typed error result the caller must handle. (correctness)

## 2. TypeScript strictness

- [ ] **`any` at API boundaries** — explicit `any`, or implicit via untyped dependency return
  values crossing a public function signature. *Why it bites:* disables checking transitively.
  Right: `unknown` + narrowing, or a precise type / declaration. (maintainability)
- [ ] **`as` casts that bypass narrowing** — especially `as unknown as T` and double casts.
  *Why it bites:* asserts a shape the compiler can't verify; wrong at runtime. Right: a type
  guard (`x is T`) or schema parse that proves the shape. (correctness)
- [ ] **Non-null assertion (`!`) where a guard belongs** — `value!.field`.
  *Why it bites:* throws at runtime when the value really is null/undefined. Right: an explicit
  check with a handled branch. (correctness)
- [ ] **Missing discriminated union for variant types** — a wide object with optional fields
  standing in for distinct cases. Right: a `type` field union so the compiler enforces
  exhaustive handling (with a `never` default). (maintainability)
- [ ] **`@ts-ignore` / `@ts-expect-error` without justification** — suppression with no comment
  explaining why and no narrowing scope. *Why it bites:* hides real regressions. Right: prefer
  `@ts-expect-error` (fails when the error goes away) plus a one-line reason. (maintainability)
- [ ] **Strict flags disabled in a tsconfig change** — `strict`, `noImplicitAny`,
  `strictNullChecks`, `noUncheckedIndexedAccess` turned off. Flag any loosening; it weakens the
  whole project, not one file. (maintainability)
- [ ] **Type-only imports mixed with value imports** — matters under `verbatimModuleSyntax` /
  `isolatedModules`. Right: `import type { T }` for types so emit and bundlers stay correct. (maintainability)

## 3. Node runtime patterns

- [ ] **Sync calls on a request/hot path** — `fs.readFileSync`, `crypto.*Sync`,
  `zlib.*Sync`, `child_process.execSync` inside a request handler.
  *Why it bites:* blocks the event loop, stalling every concurrent request. Right: the async
  (`fs/promises`) or streaming variant. (performance)
- [ ] **Stream backpressure ignored** — ignoring `write()`'s `false` return, or manual
  `readable.pipe(writable)` without error propagation. Right: `stream.pipeline()` (or
  `pipeline` from `stream/promises`), which handles backpressure and cleanup. (correctness)
- [ ] **Listener leaks** — `emitter.on(...)` with no matching `off`/`removeListener`, or a
  `MaxListenersExceededWarning`. *Why it bites:* memory growth and duplicate handling over
  time. Right: remove on teardown, or `once` when single-shot. (performance)
- [ ] **Missing graceful shutdown** — no `SIGTERM`/`SIGINT` handler to `server.close()`, drain
  in-flight requests, and close pools. *Why it bites:* dropped connections and leaked resources
  on deploy/restart. Right: trap the signal, stop accepting, drain, then exit. (correctness)
- [ ] **Env config read at import time without validation** — `const url = process.env.DB_URL`
  at module top with no check. *Why it bites:* a missing/typo'd var fails deep and late as
  `undefined`. Right: validate at startup (schema) and fail fast with a clear message. (maintainability)
- [ ] **ESM/CJS interop traps** — default-importing a CJS module that has no default export;
  using `__dirname`/`__filename`/`require` in ESM. Right: named imports or interop-aware
  import; in ESM derive dir from `import.meta.url` (`fileURLToPath`). (correctness)
- [ ] **`process.exit()` in library code** — a reusable module calling `process.exit`.
  *Why it bites:* kills the host process and skips cleanup/flush. Right: throw or return an
  error; let the entrypoint decide to exit. (maintainability)

## 4. Dependency hygiene

- [ ] **Lockfile out of sync with package.json** — a manifest change with no lockfile change
  (or vice versa). *Why it bites:* non-reproducible installs; CI resolves differently. Right:
  regenerate and commit the lockfile together, and only the intended entries move. (correctness)
- [ ] **New runtime dependency justified** — is it maintained, and does the stdlib or an
  existing dep already cover it? Prefer not adding surface for a one-liner. (maintainability)
- [ ] **Install scripts in new deps** — a new dependency with `postinstall`/`preinstall`/
  `install` scripts. *Why it bites:* arbitrary code at install time is a supply-chain vector.
  Right: scrutinize, pin, and consider `--ignore-scripts` with an allowlist. (security)
- [ ] **pnpm ≥ 10 override location** — `overrides` and `onlyBuiltDependencies` belong in
  `pnpm-workspace.yaml`, not `package.json`. *Why it bites:* a package.json-only edit is a
  silent no-op, and a lockfile regen drops any override not mirrored in the workspace file.
  Right: edit `pnpm-workspace.yaml`, then confirm the intended rows actually moved in the lockfile. (correctness)
- [ ] **Version pinning consistency** — new deps follow the project's existing policy (exact
  pins vs. ranges); don't mix a loose `^` into an exact-pinned tree. (maintainability)
- [ ] **Duplicate dependencies across workspace packages** — the same lib pulled at diverging
  versions across a monorepo. *Why it bites:* bundle bloat and version-skew bugs. Right:
  hoist/dedupe or align on one version. (maintainability)

## 5. JS security

- [ ] **Shell injection via `child_process`** — template/string concat into `exec`/`execSync`
  with any external value. *Why it bites:* arbitrary command execution. Right: `execFile`/`spawn`
  with an args array and no shell. (security)
- [ ] **`eval` / `new Function` on external input** — dynamic code from any request/config/file
  value. Right: remove it; parse data with `JSON.parse` or a real parser. (security)
- [ ] **Prototype pollution** — `Object.assign`/deep-merge of untrusted JSON into an object, or
  accepting `__proto__` / `constructor` / `prototype` keys. *Why it bites:* attacker mutates
  `Object.prototype`, corrupting every object. Right: null-prototype objects, `Map`, key
  allowlists, or a merge helper that rejects those keys. (security)
- [ ] **Path traversal on user-supplied paths** — joining request input into a filesystem path
  without containment. Right: `path.resolve(base, input)` then verify the result stays under the
  base prefix; reject otherwise. (security)
- [ ] **ReDoS-prone regex on untrusted input** — nested quantifiers / catastrophic backtracking
  (e.g. `(a+)+`) applied to user data. *Why it bites:* a crafted string pins the event loop.
  Right: a linear-time pattern, an input length cap, or a RE2-style engine. (security)
- [ ] **Secrets in client-side code** — real secrets behind `NEXT_PUBLIC_` / `VITE_` /
  `REACT_APP_` prefixes. *Why it bites:* those are inlined into the browser bundle by design and
  are public. Right: keep secrets server-side; expose only non-sensitive config to the client. (security)
- [ ] **Missing input validation at API boundaries** — request bodies/params consumed without a
  schema check. Right: validate/parse at the edge (zod/valibot or equivalent) and reject
  malformed input before it reaches business logic. (security)
