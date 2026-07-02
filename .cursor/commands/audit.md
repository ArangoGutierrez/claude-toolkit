# Audit
(no args)→diff|`--full`→codebase|`--fix`→gen fixes

## Scope
P0:`git diff --name-only`(default)|P1:handlers,db,auth(always)|P2:full(--full)

## Categories
A.EffectiveGo:race|chan-misuse|goroutine-leak|err-swallow(_=f())|panic-misuse|no-wrap
B.Defensive:input-val@public|nil-safety@chains|timeout+ctx|defer-Close
C.K8sReady:graceful-shutdown|json-log|probes|no-secrets
D.Security:no-tokens|injection-prevent|sanitize|safe-err|authz

## Balance(NO flag)
Style-as-critical|premature-opt|arch-rewrite|mitigated|test-patterns

## Verify
Each finding:1."Does file:line contain pattern?"2.Re-read INDEPENDENTLY 3.✓confirm/✗drop

## Output→AUDIT_REPORT.md
```
## [Critical] {cat}
- File:`path:line`
- Issue:{desc}
- Fix:{code}
## [Major]
## [Minor]
## Summary
Generated:N|Confirmed:X|Dropped:Y
```

## Fix(--fix)
Each Crit/Major:verify→fix→test→re-audit
Commit:`fix({scope}): {desc} - Audit finding`
