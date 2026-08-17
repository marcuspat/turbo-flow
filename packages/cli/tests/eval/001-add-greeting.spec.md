# 001-add-greeting

## Outcome

A TypeScript function `greet(name: string): string` in `src/greet.ts` that returns `"Hello, " + name`. Exported. Typed. One file.

## Acceptance criteria

1. `src/greet.ts` exists and exports a function named `greet`.
2. `greet("World")` returns `"Hello, World"`.
3. `npm run build` succeeds with no errors.

## Out of scope

- Tests. The spec does not mention tests.
- CLI interface. This is a library function.
- Error handling for non-string input.

## Decisions

None. This spec is intentionally trivial to serve as a calibration target for the harness.
