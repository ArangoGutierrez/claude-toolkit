# Go Conventions

## Errors
- Wrap errors with call-site context: `fmt.Errorf("op: %w", err)`; bare `return err` loses the caller
- `errors.Is()`/`errors.As()` for checks. Sentinels as `var ErrFoo = errors.New("foo")`
- Return early on error

## Signatures
- `context.Context` is the first parameter; thread it through, don't store it in structs
- Accept interfaces, return structs — interfaces at consumer site
- Channel direction in signatures: `chan<-` or `<-chan`

## Style
- Receivers: single letter matching the type (`s` for `Server`), not `this`/`self`
- No `init()`, no globals, no `any` when concrete type exists
- JSON: `json:",omitempty"` default. YAML: explicit `yaml:"name"` tags

## Testing
- Table-driven, `t.Run("descriptive name", ...)`, `testify` assert/require
- `t.Helper()` on helpers. `t.Parallel()` when safe. Real impls over mocks.

## Concurrency
- Guard a given resource with `sync.Mutex` or channels (pick one). Use `defer mu.Unlock()` when locking.
- `errgroup.Group` for concurrent fallible ops. Every goroutine has a termination path.
