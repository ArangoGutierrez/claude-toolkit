# Issue
`#{n}`→analyze+task-plan

## 1.Fetch
`git remote get-url origin`→owner/repo
GH:title,body,labels,state,comments,linked-PRs,related

## 2.Classify
Type:bug/feat/refactor/docs/perf/sec
Scope:local/cross/arch
Complex:trivial/simple/mod/complex

## 3.Research
Files/pkgs mentioned|traces→src|tests?|similar patterns

## 4.Design
|#|Approach|Eff|Risk|Trade|
|1|{n}|L/M/H|L/M/H|{+/-}|
|2|{n}|L/M/H|L/M/H|{+/-}|
Rec:best effort/impact

## 5.Atomic Tasks
1task=1change=1test=1commit

## 6.Verify
Files exist?→read|Behavior match?→trace|Current?→latest comments

## Output
Console:`## #{n}:{title}`+Type+Complex+Branch+Tasks
AGENTS.md:create/update(preserve existing)
```
# AGENTS.md
## Current Task
Issue #{n}:{title}
## Status:IN_PROGRESS
## Branch
`{type}/issue-{n}-{slug}`
## Tasks
|#|Task|Status|Commit|
|1|{desc}|[TODO]||
## Files
## Acceptance
## Notes
```

## Branch
`git checkout main && git pull && git checkout -b {type}/issue-{n}-{slug}`
