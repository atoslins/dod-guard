---
name: stub-detection-patterns
description: Use when scanning code for incomplete implementations across multiple languages. A reference of the "tells" — surface patterns that signal a stub even when the function compiles and the test passes.
---

# Stub-Detection Patterns

Detectors catch the easy cases. Subagents and reviewers should know the rest. This is the language-by-language cheat sheet.

## What counts as a stub?

Any function whose body does not produce the behavior the contract implies, including:

- Empty body (`pass`, `return`, `{}`).
- Body that only acknowledges its arguments (`return args`, `return input`).
- Body that returns a structurally-correct but logically-empty value (`return []`, `return {}`, `return ""`).
- Body that raises "not implemented" of any flavor.
- Body that delegates to a callee that itself returns one of the above.

## Python — `.py`

| Pattern | Why it's a stub |
|---|---|
| `def f(): pass` | Empty body |
| `def f(): ...` | Empty body |
| `def f(): return` | Returns None implicitly |
| `def f(): return None` | Returns None explicitly |
| `def f(): raise NotImplementedError` | Marker |
| `def f(): """docstring only"""` | Docstring with no real body |
| `def f(x): return x` | Identity — almost always a stub when the name promised more |
| `def fetch_users(): return []` | Action-name + empty literal |
| `def create_user(name): return {}` | Action-name + empty literal |

Exemptions: `@abstractmethod`, `@typing.overload`, Protocol/ABC method declarations.

## JavaScript / TypeScript — `.js .jsx .ts .tsx .mjs .cjs`

| Pattern | Why |
|---|---|
| `function f() {}` | Empty body |
| `const f = () => {}` | Empty arrow |
| `const f = () => null` | Returns null only |
| `function f() { return null; }` | Returns null only |
| `function f() { throw new Error("not implemented"); }` | Marker |
| `async function f() { return null; }` | Async stub |
| `class C { method() {} }` | Empty class method |
| `function f(x: T): T | null { return null; }` | Type allows but body never produces non-null |
| `try { ... } catch { /* */ }` | Silent error swallow |

Tells in tests: `expect(x).toBeDefined()`, `.not.toBeNull()`, `.toBeTruthy()` on a literal, `expect(f()).toEqual(f())` (tautology), `test.skip`, `xit`.

## Go — `.go`

| Pattern | Why |
|---|---|
| `func F() { }` | Empty body |
| `func F() error { return nil }` | Action-named func always returning nil |
| `func F() (T, error) { return T{}, nil }` | Zero values only |
| `panic("not implemented")` | Marker |
| `panic("unimplemented")` | Marker |
| `func F() { _ = x }` | Acknowledges argument, does nothing |

Tells in tests: `t.Skip("TODO")`, `// TODO:` above the test func, `if true { return }` to skip a test body.

## Rust — `.rs`

| Pattern | Why |
|---|---|
| `fn f() {}` | Empty body |
| `fn f() -> T { todo!() }` | Marker (built-in) |
| `fn f() -> T { unimplemented!() }` | Marker (built-in) |
| `fn f() -> Option<T> { None }` | Action-named fn returning None only |
| `fn f() -> Result<T, E> { Ok(Default::default()) }` | Action-named fn returning default only |

Tells in tests: `#[ignore]` added in this diff, `assert!(true)`, `assert_eq!(x, x)`.

## Ruby — `.rb`

| Pattern | Why |
|---|---|
| `def f\nend` | Empty body |
| `def f; nil; end` | Returns nil |
| `def f; raise NotImplementedError; end` | Marker |
| `def f; []; end` (action name) | Empty array |

Tells in tests: `skip "TODO"`, `pending`, RSpec `xit`.

## Bash — `.sh .bash`

| Pattern | Why |
|---|---|
| `f() { :; }` | No-op body |
| `f() { true; }` | No-op body |
| `f() { return 0; }` | Always-success |
| `f() { echo "TODO" >&2; }` | Marker disguised as output |

Tells in tests: `[[ true ]]`, `: # placeholder`.

## Universal markers (any language)

- `TODO`, `FIXME`, `XXX`, `HACK` — comment-style markers.
- `placeholder`, `dummy`, `stub`, `mock` in variable / function names (with caveats: a `MockRepository` test double is legitimate).
- Hardcoded sentinel values: `"localhost"`, `"127.0.0.1"`, `"changeme"`, `"REPLACE_ME"`, `"YOUR_API_KEY_HERE"`.
- Loops that iterate but do nothing: `for x in xs: pass`, `for _ in 0..n {}`.
- `if false:` / `if (false)` blocks that look intentional but are dead.

## False-positive guardrails

Some patterns are intentional and should NOT be flagged:

- `@abstractmethod def f(): ...` — abstract base class method.
- `class FooProtocol(Protocol): def f(self) -> int: ...` — Python typing protocol.
- `func F() error { return nil }` inside a test helper named `Noop*` — explicitly a no-op.
- `it.skip` left in upstream library code that is vendored.

When in doubt, include the finding but mark severity as `warn`, not `high`. The reviewer can downgrade further.

See also: [[adversarial-verification]] for how subagents consume these patterns.
