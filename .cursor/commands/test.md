# Test
(no args)→full|`--quick`→changed|`--file {p}`→specific

## Detect
go.mod→`go test ./...`
package.json→`npm test`
pyproject.toml|requirements.txt→`pytest`
Cargo.toml→`cargo test`

## Run
{cmd}→Status:PASS/FAIL|Tests:{pass}/{total}|Duration

## Fail
|Test|Error|+Suggested fix
→/code→/test

## Update AGENTS.md
pass→[DONE]|fail→[BLOCKED:tests failing]

## Quick
`git diff --name-only HEAD~1`→targeted tests

## Troubleshoot
|Issue|Fix|
|no-framework|run manually: `go test`|`npm test`|`pytest`|`cargo test`|
|pass-local-fail-here|check env vars|DB running?|port conflicts|clear cache|
|flaky|run `-count=10`|check races|time-deps|shared state|
|hanging|check loops/I/O|add timeout|verbose mode|missing mocks|
|compile-error|fix build first|check imports|type errors|
