# Matwork — BJJ instructor income platform (POC)

Multi-tenant Phoenix/Ash platform: gym instructors publish video curriculum behind a
Stripe Connect paywall to their own student roster. The authoritative spec is
`docs/design.md` — read it before any multi-file change. If code and design doc
disagree, say so; don't silently pick one.

## Stack

Elixir 1.18+ / OTP 27 · Phoenix 1.8 + LiveView · Ash 3.x + ash_postgres (Postgres 16)
· ash_authentication (magic link ONLY — no passwords) · ash_oban/Oban · Tailwind
· Stripe Connect (Express, destination charges) · Mux (direct upload, signed playback)
· Fly.io

## Iron rules

**Tenancy & authorization**
- Global resources: `User`, `Token`, `Gym`, `WebhookEvent`. Everything else is
  attribute-multitenant on `gym_id`. Never add a tenant-scoped resource without the
  `multitenancy` block.
- Every Ash call passes `actor:`; every call on a tenant-scoped resource passes
  `tenant:`. No `authorize?: false` outside seeds, migrations, and system-actor
  webhook jobs — and flag it in the diff summary when used.
- Authorization lives in resource policies, never in LiveViews or controllers.
  LiveViews call domain code interfaces; they do not build raw queries.
- Mux playback JWTs are minted ONLY inside `Lesson.request_playback_token`. No other
  code path may produce a watchable URL.

**Money & external services**
- Money is integer cents. Never floats, never Decimal for storage.
- All Stripe and Mux API calls go through the `Platform.Stripe` / `Platform.Mux`
  behaviours. No direct HTTP/SDK calls elsewhere.
- Webhooks: verify signature → insert `WebhookEvent` (idempotent on provider +
  external_id) → process in an Oban job that invokes a named Ash action with the
  system actor. Never process inline in the controller.
- `Subscription.status` is a mirror of Stripe. Only webhook/reconciliation actions
  write it. Feature code reads it, never writes it.

**UI components**
- Reusable components live in `lib/stalwart_ui/` and may depend only on
  Phoenix.Component, Tailwind, and their own JS hooks — never on resources, domains,
  or route helpers. They take plain assigns.
- When you create or materially change a `StalwartUI` component, add/update its entry
  in `COMPONENTS.md`.

**Migrations & codegen**
- After changing resources, run `mix ash.codegen <descriptive_name>`. Don't hand-write
  migrations for Ash-managed tables.

## Workflow

- Plan mode before any multi-file change; wait for approval.
- Before every commit: `mix format`, `mix credo --strict`, `mix test` — all green.
- Prefer official generators/igniter installers over hand-writing boilerplate.
- Use Tidewave MCP tools (eval, logs, SQL, schema introspection) to verify runtime
  behavior — especially policy and tenancy checks — instead of asserting from reading
  code alone.
- Small commits, one concern each, imperative subject lines.

## Testing

- Every policy gets tests for allow AND deny paths. The deny paths are the product.
- Test tenancy isolation explicitly: a user in gym A must not read gym B's rows.
- Stripe/Mux: use Mox against the `Platform.*` behaviours in unit tests; use real
  test-mode keys only in dedicated integration tests.
- LiveView tests for the two critical flows: invite → join, subscribe → watch.

<!-- usage_rules-start -->
## usage_rules usage
_A config-driven dev tool for Elixir projects to manage AGENTS.md files and agent skills from dependencies_

## Using Usage Rules

Many packages have usage rules, which you should *thoroughly* consult before taking any
action. These usage rules contain guidelines and rules *directly from the package authors*.
They are your best source of knowledge for making decisions.

## Modules & functions in the current app and dependencies

When looking for docs for modules & functions that are dependencies of the current project,
or for Elixir itself, use `mix usage_rules.docs`

```
# Search a whole module
mix usage_rules.docs Enum

# Search a specific function
mix usage_rules.docs Enum.zip

# Search a specific function & arity
mix usage_rules.docs Enum.zip/1
```


## Searching Documentation

You should also consult the documentation of any tools you are using, early and often. The best
way to accomplish this is to use the `usage_rules.search_docs` mix task. Once you have
found what you are looking for, use the links in the search results to get more detail. For example:

```
# Search docs for all packages in the current application, including Elixir
mix usage_rules.search_docs Enum.zip

# Search docs for specific packages
mix usage_rules.search_docs Req.get -p req

# Search docs for multi-word queries
mix usage_rules.search_docs "making requests" -p req

# Search only in titles (useful for finding specific functions/modules)
mix usage_rules.search_docs "Enum.zip" --query-by title
```


<!-- usage_rules:elixir-start -->
## usage_rules:elixir usage
# Elixir Core Usage Rules

## Pattern Matching
- Use pattern matching over conditional logic when possible
- Prefer to match on function heads instead of using `if`/`else` or `case` in function bodies
- `%{}` matches ANY map, not just empty maps. Use `map_size(map) == 0` guard to check for truly empty maps

## Error Handling
- Use `{:ok, result}` and `{:error, reason}` tuples for operations that can fail
- Avoid raising exceptions for control flow
- Use `with` for chaining operations that return `{:ok, _}` or `{:error, _}`

## Common Mistakes to Avoid
- Elixir has no `return` statement, nor early returns. The last expression in a block is always returned.
- Don't use `Enum` functions on large collections when `Stream` is more appropriate
- Avoid nested `case` statements - refactor to a single `case`, `with` or separate functions
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Lists and enumerables cannot be indexed with brackets. Use pattern matching or `Enum` functions
- Prefer `Enum` functions like `Enum.reduce` over recursion
- When recursion is necessary, prefer to use pattern matching in function heads for base case detection
- Using the process dictionary is typically a sign of unidiomatic code
- Only use macros if explicitly requested
- There are many useful standard library functions, prefer to use them where possible

## Function Design
- Use guard clauses: `when is_binary(name) and byte_size(name) > 0`
- Prefer multiple function clauses over complex conditional logic
- Name functions descriptively: `calculate_total_price/2` not `calc/2`
- Predicate function names should not start with `is` and should end in a question mark.
- Names like `is_thing` should be reserved for guards

## Data Structures
- Use structs over maps when the shape is known: `defstruct [:name, :age]`
- Prefer keyword lists for options: `[timeout: 5000, retries: 3]`
- Use maps for dynamic key-value data
- Prefer to prepend to lists `[new | list]` not `list ++ [new]`

## Mix Tasks

- Use `mix help` to list available mix tasks
- Use `mix help task_name` to get docs for an individual task
- Read the docs and options fully before using tasks

## Testing
- Run tests in a specific file with `mix test test/my_test.exs` and a specific test with the line number `mix test path/to/test.exs:123`
- Limit the number of failed tests with `mix test --max-failures n`
- Use `@tag` to tag specific tests, and `mix test --only tag` to run only those tests
- Use `assert_raise` for testing expected exceptions: `assert_raise ArgumentError, fn -> invalid_function() end`
- Use `mix help test` to for full documentation on running tests

## Debugging

- Use `dbg/1` to print values while debugging. This will display the formatted value and other relevant information in the console.

<!-- usage_rules:elixir-end -->
<!-- usage_rules:otp-start -->
## usage_rules:otp usage
# OTP Usage Rules

## GenServer Best Practices
- Keep state simple and serializable
- Handle all expected messages explicitly
- Use `handle_continue/2` for post-init work
- Implement proper cleanup in `terminate/2` when necessary

## Process Communication
- Use `GenServer.call/3` for synchronous requests expecting replies
- Use `GenServer.cast/2` for fire-and-forget messages.
- When in doubt, use `call` over `cast`, to ensure back-pressure
- Set appropriate timeouts for `call/3` operations

## Fault Tolerance
- Set up processes such that they can handle crashing and being restarted by supervisors
- Use `:max_restarts` and `:max_seconds` to prevent restart loops

## Task and Async
- Use `Task.Supervisor` for better fault tolerance
- Handle task failures with `Task.yield/2` or `Task.shutdown/2`
- Set appropriate task timeouts
- Use `Task.async_stream/3` for concurrent enumeration with back-pressure

<!-- usage_rules:otp-end -->
<!-- usage-rules-end -->
