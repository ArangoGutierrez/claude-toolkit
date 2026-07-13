# Go Review Checklist

## Error Handling

- [ ] All errors wrapped: `fmt.Errorf("what: %w", err)`
- [ ] No bare `return err`
- [ ] Sentinels as package-level vars
- [ ] `errors.Is()`/`errors.As()` for checks

## Concurrency

- [ ] Every goroutine has termination path
- [ ] Channels have clear ownership (who closes?)
- [ ] `defer mu.Unlock()` after Lock
- [ ] No mixed mutex + channel for same resource
- [ ] `errgroup.Group` for concurrent fallible ops
- [ ] `context.Context` in all blocking ops

## Performance

- [ ] Slices pre-allocated: `make([]T, 0, n)`
- [ ] `strings.Builder` for multi-step string building
- [ ] No allocations in hot loops
- [ ] Maps pre-allocated: `make(map[K]V, n)`

## Interfaces

- [ ] Defined at consumer site
- [ ] Accept interfaces, return concrete types
- [ ] No header interfaces mirroring structs
- [ ] Compliance: `var _ Interface = (*Struct)(nil)`

## Testing

- [ ] Table-driven with descriptive subtests
- [ ] `t.Helper()` on helpers
- [ ] `t.Parallel()` where safe
- [ ] Real impls over mocks
- [ ] Error paths tested
