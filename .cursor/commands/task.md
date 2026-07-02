# Task
`{desc}`|`#{n}`|`--plan`|`--tdd`

## P1:UNDERSTAND(10%)
```
git remote get-url origin && git rev-parse --show-toplevel
```
GH#→fetch:title,body,labels,comments,linked-PRs
Clarify≤2q

## P2:SPECIFY(15%)
|El|Def|
|In|data/state entering|
|Out|changes|
|Constraints|perf,sec,style|
|Accept|verify-how|
|Edge|fail-how|
|OOS|NOT doing|

Constraints:MUST≤7|SHOULD|MUST-NOT|Security(no-secrets,input-val,safe-err)

## P3:PLAN(--plan)
|#|Approach|Eff|Risk|Trade|
|1|{n}|L/M/H|L/M/H|{+/-}|
|2|{n}|L/M/H|L/M/H|{+/-}|
Selected:{approach}∵{why}
→STOP.Await"GO"

## P4:IMPL
--tdd:fail-test→confirm-fail→min-impl→refactor→repeat
Progress:|#|Task|Status[TODO/WIP/DONE]|
Update AGENTS.md(preserve existing)

## P5:VERIFY
✓compile|✓tests|✓acceptance|✓edges

## Reflect
Logic:contradict?|Complete:all-req?|Correct:match-accept?|Edge:bounds?|Ext:tools?

## Budget
Trivial:1|Simple:2|Mod:3|Complex:4→escalate

## Commit
`git commit -s -S -m "type(scope): desc"`

## PR
`gh pr create --title "type(scope): desc" --body "Fixes #N"`
⚠no-auto-merge
