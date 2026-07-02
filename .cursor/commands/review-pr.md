# Review-PR
`#{n}`→specific|no args→branch diff

## Skip
closed|draft|trivial(docs)→"LGTM"

## Passes
1.Security(high-risk):creds?|injection?|input-val?|authz-bypass?|data-in-err?
2.Bugs(CHANGED only):logic-err?|nil-deref?|unhandled-err?|leak?
3.Arch:patterns?|separation?|tests?

## Confidence
Report only≥80
0-50:DROP|51-79:question|80-100:report
Scoring(+20):exact file:line|THIS PR|justified|verified|fix-provided

## Verify
Each:1.gen Q 2.re-read INDEPENDENTLY 3.✓confirm/✗drop/?question

## Output
```
## PR Review: #{n}
### Summary
Files:{N}|Risk:{areas}
### 🔴 Blocking(≥80)
`file:line`(conf:{N}/100)
- Issue:{desc}
- Fix:{code}
### 🟡 Health
### 🔵 Questions
### Verdict
✅Approved/⚠Changes Requested/🚫Blocked
```
