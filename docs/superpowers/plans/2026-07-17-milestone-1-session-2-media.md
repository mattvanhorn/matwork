# Milestone 1 · Session 2 — Media / Mux Direct Upload Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An instructor uploads real video to a lesson from the course builder: the browser uploads bytes straight to Mux, a signed webhook drives the `Video` through `pending_upload → processing → ready` via an Oban job, and the builder reflects the status live. No playback yet — that's Session 3.

**Architecture:** A thin `Platform.Mux` behaviour (Req-backed, Mox-stubbed) is the *only* path to the Mux API. A new global `Matwork.Platform` domain holds `WebhookEvent` (idempotent ledger) and a `SystemActor`. A new tenant-scoped `Matwork.Media` domain holds `Video`. The Mux webhook controller verifies the signature over the raw body, idempotently records a `WebhookEvent`, and enqueues an Oban job; the job invokes `Video.mark_ready`/`mark_errored` as the `SystemActor` and broadcasts over `Matwork.PubSub` so the open builder LiveView reloads. `Lesson` gains a nullable `video_id`, attached through a tenant-guarded action.

**Tech Stack:** Elixir 1.18 / Phoenix 1.8 LiveView, Ash 3.x + `ash_postgres`, Oban (already wired via `AshOban.config`), `Req` (already a dep), Mox (new test dep), Mux direct uploads + webhooks, `@mux/upchunk` (new JS dep).

**Spec:** `docs/superpowers/specs/2026-07-16-milestone-1-curriculum-video-design.md` — §5 (Session 2), plus §2.2 (`Media`/`Video`), §2.3 (`Platform`/`WebhookEvent`), §3.4 (system actor), §7 (components).

**Branching:** Session 1 merged to `main` via PR #3 (branch `curriculum-milestone-1-session-1`). Start Session 2 from a fresh branch off `main`: `git switch main && git pull && git switch -c media-milestone-1-session-2`.

## Global Constraints

Copied verbatim from `CLAUDE.md` and the spec — every task implicitly includes these:

- **Consult the `ash-framework` skill before any domain change**; use `mix usage_rules.docs Ash.<Module>` / `mix usage_rules.search_docs` when unsure of an Ash or Oban API.
- **All Mux API calls go through the `Platform.Mux` behaviour. No direct HTTP/SDK calls elsewhere.** (Signature verification is local HMAC, not an API round-trip — it lives in a plain `Platform.Mux.Signature` module, not the behaviour.)
- **Webhooks:** verify signature → insert `WebhookEvent` (idempotent on `provider` + `external_id`) → process in an Oban job that invokes a named Ash action with the **system actor**. Never process inline in the controller.
- **Global resources:** `User`, `Token`, `Gym`, `WebhookEvent`. Everything else is attribute-multitenant on `gym_id`. `Video` is tenant-scoped and MUST have the `multitenancy do strategy :attribute; attribute :gym_id end` block; `WebhookEvent` is global (no such block).
- **Every Ash call passes `actor:`**; every call on a tenant-scoped resource passes `tenant:`. **No `authorize?: false`** outside seeds, migrations, and system-actor webhook jobs — flag it in the commit/diff summary when used. (This session uses it only inside the tenant-guard validation and position/existence reads, matching the Session 1 pattern in `Validations.SectionInTenant`.)
- **Authorization lives in resource policies**, never in LiveViews or controllers.
- **Mux playback JWTs are minted ONLY inside `Lesson.request_playback_token`.** That action is **Session 3** — do **not** create it or mint any token in this session. `Video` stores `mux_playback_id` (signed-policy) but nothing here produces a watchable URL.
- **Primary keys are `uuid_primary_key :id`** (established in Session 1; the spec's `bigserial` note is superseded by the code — keep matching existing resources).
- **`StalwartUI` components** depend only on `Phoenix.Component`, Tailwind/daisyUI, and their own JS hooks — never on a resource, domain, or route helper. Update `COMPONENTS.md` when you add/change one.
- **Migrations:** after each resource change run `mix ash.codegen <descriptive_name>`; never hand-write migrations for Ash-managed tables.
- **Money:** N/A this session.
- **Before every commit:** `mix format`, `mix credo --strict`, `mix test` — all green.
- **Every policy gets allow AND deny tests; test tenant isolation explicitly** (a user/manager in gym A must not read/mutate/attach gym B's rows). Mux is stubbed with Mox in unit tests; real keys only in a `@tag :mux_integration` test (excluded by default).

### ⚠️ Mux external-contract assumptions — verify against docs.mux.com before/while implementing

The code below uses these Mux shapes. They are stable and widely used, but the implementer MUST confirm them against the current Mux docs (they are the only "judgment calls" in this plan):

1. **Create direct upload** — `POST https://api.mux.com/video/v1/uploads`, HTTP Basic auth (`MUX_TOKEN_ID`:`MUX_TOKEN_SECRET`), JSON body `{"cors_origin": "<origin>", "new_asset_settings": {"playback_policy": ["signed"], "passthrough": "<gym_id>"}}`. Response: `{"data": {"id": "<upload_id>", "url": "<one-time PUT url>"}}`.
2. **Webhook signature** — header `Mux-Signature: t=<unix_ts>,v1=<hex_hmac>`; `v1` is `HMAC-SHA256("<t>.<raw_request_body>", MUX_WEBHOOK_SECRET)` hex-encoded.
3. **Webhook payloads** — top-level `{"type": ..., "id": "<event_id>", "data": {...}}`. For `video.asset.ready`: `data.id` = asset id, `data.playback_ids` = `[%{"id" => ..., "policy" => "signed"}]`, `data.duration` = float seconds, `data.upload_id` = the upload id, `data.passthrough` = the gym_id we set. For `video.upload.asset_created`: `data.asset_id` + `data.passthrough`. For `video.asset.errored`: `data.upload_id`/`data.passthrough`.
4. **UpChunk** — `UpChunk.createUpload({endpoint, file})`, events `progress` / `success` / `error`.

---

## File Structure

**Create:**

- `lib/matwork/platform.ex` — `Matwork.Platform` global domain (WebhookEvent interfaces).
- `lib/matwork/platform/mux.ex` — `Platform.Mux` behaviour + dispatch to the configured impl.
- `lib/matwork/platform/mux/http.ex` — `Platform.Mux.HTTP`, the Req-backed real implementation.
- `lib/matwork/platform/mux/signature.ex` — Mux webhook HMAC verification (plain module).
- `lib/matwork/platform/system_actor.ex` — `%Matwork.Platform.SystemActor{}` struct.
- `lib/matwork/platform/checks/system_actor.ex` — policy check matching the system actor.
- `lib/matwork/platform/webhook_event.ex` — `WebhookEvent` global resource.
- `lib/matwork/media.ex` — `Matwork.Media` tenant-scoped domain.
- `lib/matwork/media/video.ex` — `Video` resource.
- `lib/matwork/media/jobs/process_mux_webhook.ex` — Oban worker.
- `lib/matwork/curriculum/validations/video_in_tenant.ex` — cross-tenant FK guard for lesson↔video.
- `lib/matwork_web/controllers/webhook_controller.ex` — Mux webhook endpoint.
- `lib/matwork_web/plugs/cache_raw_body.ex` — raw-body reader for signature verification.
- `lib/stalwart_ui/video_upload_field.ex` — upload affordance + status (plain assigns).
- `assets/js/hooks/mux_upload.js` — UpChunk browser-upload hook.
- `assets/package.json` — declares `@mux/upchunk` (first npm dep in the project).
- Tests: `test/matwork/platform/mux_test.exs`, `test/matwork/platform/mux/signature_test.exs`, `test/matwork/platform/webhook_event_test.exs`, `test/matwork/media/video_test.exs`, `test/matwork/media/jobs/process_mux_webhook_test.exs`, `test/matwork_web/controllers/webhook_controller_test.exs`, `test/matwork/curriculum/lesson_video_test.exs`, `test/stalwart_ui/video_upload_field_test.exs`, `test/matwork_web/live/course_builder_upload_test.exs`.

**Modify:**

- `mix.exs` — add `{:mox, "~> 1.1", only: :test}`.
- `config/config.exs` — `config :matwork, :mux, Matwork.Platform.Mux.HTTP`; add `Matwork.Platform` + `Matwork.Media` to `ash_domains`.
- `config/runtime.exs` — Mux creds + webhook secret from env (all-env block).
- `config/test.exs` — `config :matwork, :mux, Matwork.Platform.MuxMock`; `config :matwork, :mux_webhook_secret, "test_mux_secret"`.
- `test/test_helper.exs` — `Mox.defmock(Matwork.Platform.MuxMock, for: Matwork.Platform.Mux)`.
- `test/support/generator.ex` — add `video/1` generator.
- `.env.example` — document `MUX_TOKEN_ID`, `MUX_TOKEN_SECRET`, `MUX_WEBHOOK_SECRET`, `MUX_SIGNING_KEY_ID`, `MUX_SIGNING_KEY_PRIVATE_KEY`.
- `lib/matwork_web/endpoint.ex` — add `body_reader:` to `Plug.Parsers`.
- `lib/matwork_web/router.ex` — add the Mux webhook route (new unauthenticated pipeline).
- `lib/matwork/curriculum/lesson.ex` — add nullable `video_id` + `attach_video`/`detach_video` actions.
- `lib/matwork/curriculum.ex` — add `attach_lesson_video`/`detach_lesson_video` interfaces; load `:video` in `load_course_tree`.
- `lib/matwork_web/live/course_builder_live.ex` — upload events, PubSub subscription, video status in projection.
- `lib/stalwart_ui/curriculum_tree.ex` — render per-lesson video status + upload field; accept `video_status` in lesson maps.
- `assets/js/app.js` — register the `MuxUpload` hook.
- `COMPONENTS.md` — `VideoUploadField` entry + `CurriculumTree` assigns update.

**Task → file map:** T1 = `Platform.Mux` behaviour + Req impl + Mox + config/deps. T2 = `Platform` domain + `WebhookEvent` + `SystemActor`. T3 = `Media` domain + `Video`. T4 = webhook controller + Oban worker + routing/endpoint + PubSub. T5 = `Lesson.video_id` + attach/detach. T6 = builder upload UI + JS hook + live status.

---

## Task 1: `Platform.Mux` behaviour, Req impl, Mox, config

**Files:**
- Create: `lib/matwork/platform/mux.ex`, `lib/matwork/platform/mux/http.ex`
- Modify: `mix.exs`, `config/config.exs`, `config/runtime.exs`, `config/test.exs`, `test/test_helper.exs`, `.env.example`
- Test: `test/matwork/platform/mux_test.exs`

**Interfaces:**
- Produces (used by T3, T4): behaviour `Matwork.Platform.Mux` with callbacks `create_direct_upload(map) :: {:ok, %{id: String.t(), url: String.t()}} | {:error, term}`, `get_asset(String.t()) :: {:ok, map} | {:error, term}`. Dispatch functions of the same name route to the configured impl. Mock `Matwork.Platform.MuxMock`.
- ⚠️ Do **not** add a `sign_playback` callback here — that is Session 3.

- [ ] **Step 1: Add Mox and configure the impl**

`mix.exs` deps — add alongside the other `only: :test` deps:

```elixir
      {:mox, "~> 1.1", only: :test},
```

Run `mix deps.get`.

`config/config.exs` — after the `config :matwork, Oban, ...` block, add the default (real) Mux impl:

```elixir
config :matwork, :mux, Matwork.Platform.Mux.HTTP
```

`config/test.exs` — add near the other test config:

```elixir
config :matwork, :mux, Matwork.Platform.MuxMock
config :matwork, :mux_webhook_secret, "test_mux_secret"
```

`config/runtime.exs` — add an **all-environments** block (outside the `if config_env() == :dev/:prod` blocks; place it right after the `Dotenvy` block so dev picks up `.env`):

```elixir
config :matwork, Matwork.Platform.Mux.HTTP,
  token_id: System.get_env("MUX_TOKEN_ID"),
  token_secret: System.get_env("MUX_TOKEN_SECRET")

# The webhook secret has a test default in config/test.exs; only override it
# here when a real value is present, so signature tests keep their fixture.
if secret = System.get_env("MUX_WEBHOOK_SECRET") do
  config :matwork, :mux_webhook_secret, secret
end
```

`test/test_helper.exs` — define the mock before `ExUnit.start()`:

```elixir
Mox.defmock(Matwork.Platform.MuxMock, for: Matwork.Platform.Mux)
ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Matwork.Repo, :manual)
```

`.env.example` — replace the trailing example block with the real Session-2 keys:

```
# Mux (Session 2+). Get these from the Mux dashboard (test environment).
# MUX_TOKEN_ID=...
# MUX_TOKEN_SECRET=...
# MUX_WEBHOOK_SECRET=...            # signing secret for the webhook endpoint
# MUX_SIGNING_KEY_ID=...            # Session 3 (signed playback)
# MUX_SIGNING_KEY_PRIVATE_KEY=...   # Session 3 (signed playback)
```

- [ ] **Step 2: Write the behaviour + dispatch module**

Create `lib/matwork/platform/mux.ex`:

```elixir
defmodule Matwork.Platform.Mux do
  @moduledoc """
  The single boundary for the Mux API (per CLAUDE.md — no direct HTTP/SDK
  calls to Mux anywhere else). Defines the behaviour and dispatches to the
  configured implementation (`Platform.Mux.HTTP` in dev/prod, `MuxMock` in
  tests).

  Signature verification is NOT here — it is local HMAC, see
  `Matwork.Platform.Mux.Signature`. Signed-playback JWT minting is Session 3.
  """

  @doc "Create a Mux direct upload. `params` may include `:passthrough` and `:cors_origin`."
  @callback create_direct_upload(params :: map()) ::
              {:ok, %{id: String.t(), url: String.t()}} | {:error, term()}

  @doc "Fetch a Mux asset by id (used to reconcile state if needed)."
  @callback get_asset(asset_id :: String.t()) :: {:ok, map()} | {:error, term()}

  def create_direct_upload(params \\ %{}), do: impl().create_direct_upload(params)
  def get_asset(asset_id), do: impl().get_asset(asset_id)

  defp impl, do: Application.get_env(:matwork, :mux, Matwork.Platform.Mux.HTTP)
end
```

- [ ] **Step 3: Write the Req-backed implementation**

Create `lib/matwork/platform/mux/http.ex`:

```elixir
defmodule Matwork.Platform.Mux.HTTP do
  @moduledoc """
  Req-backed `Platform.Mux` implementation. Talks to the Mux Video API over
  HTTP Basic auth. Never called directly by feature code — always reached via
  `Matwork.Platform.Mux`.
  """
  @behaviour Matwork.Platform.Mux

  @base_url "https://api.mux.com"

  @impl true
  def create_direct_upload(params) do
    body = %{
      cors_origin: Map.get(params, :cors_origin, "*"),
      new_asset_settings: %{
        playback_policy: ["signed"],
        passthrough: Map.get(params, :passthrough)
      }
    }

    case Req.post(req(), url: "/video/v1/uploads", json: body) do
      {:ok, %{status: status, body: %{"data" => data}}} when status in 200..299 ->
        {:ok, %{id: data["id"], url: data["url"]}}

      {:ok, resp} ->
        {:error, {:mux_http, resp.status, resp.body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def get_asset(asset_id) do
    case Req.get(req(), url: "/video/v1/assets/#{asset_id}") do
      {:ok, %{status: status, body: %{"data" => data}}} when status in 200..299 ->
        {:ok, data}

      {:ok, resp} ->
        {:error, {:mux_http, resp.status, resp.body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp req do
    config = Application.get_env(:matwork, __MODULE__, [])
    token_id = Keyword.get(config, :token_id)
    token_secret = Keyword.get(config, :token_secret)

    Req.new(base_url: @base_url, auth: {:basic, "#{token_id}:#{token_secret}"})
  end
end
```

- [ ] **Step 4: Write the behaviour/dispatch test (Mox)**

Create `test/matwork/platform/mux_test.exs`:

```elixir
defmodule Matwork.Platform.MuxTest do
  use ExUnit.Case, async: true

  import Mox

  setup :verify_on_exit!

  test "create_direct_upload/1 dispatches to the configured impl" do
    Matwork.Platform.MuxMock
    |> expect(:create_direct_upload, fn params ->
      assert params.passthrough == "gym-123"
      {:ok, %{id: "upload_abc", url: "https://storage.example/put"}}
    end)

    assert {:ok, %{id: "upload_abc", url: "https://storage.example/put"}} =
             Matwork.Platform.Mux.create_direct_upload(%{passthrough: "gym-123"})
  end
end
```

- [ ] **Step 5: Run tests, format, lint, commit**

Run: `mix test test/matwork/platform/mux_test.exs` (expect PASS).

```bash
mix format
mix credo --strict
git add mix.exs mix.lock config/ test/test_helper.exs .env.example lib/matwork/platform/mux.ex lib/matwork/platform/mux/http.ex test/matwork/platform/mux_test.exs
git commit -m "Add Platform.Mux behaviour, Req impl, and Mox test double"
```

---

## Task 2: `Platform` domain, `WebhookEvent`, `SystemActor`

**Files:**
- Create: `lib/matwork/platform/system_actor.ex`, `lib/matwork/platform/checks/system_actor.ex`, `lib/matwork/platform/webhook_event.ex`, `lib/matwork/platform.ex`
- Create: `lib/matwork/platform/mux/signature.ex` + `test/matwork/platform/mux/signature_test.exs`
- Modify: `config/config.exs` (register domain)
- Test: `test/matwork/platform/webhook_event_test.exs`

**Interfaces:**
- Produces (used by T3, T4):
  - `%Matwork.Platform.SystemActor{}` and check `Matwork.Platform.Checks.SystemActor`.
  - `Matwork.Platform` interfaces: `record_webhook_event(provider, external_id, payload, opts)` (idempotent), `get_webhook_event(id, opts)`, `mark_webhook_processed(event, opts)`.
  - `Matwork.Platform.Mux.Signature.verify(raw_body, signature_header, secret) :: :ok | :error`.

- [ ] **Step 1: Register the domain**

`config/config.exs` — extend `ash_domains`:

```elixir
  ash_domains: [Matwork.Accounts, Matwork.Gyms, Matwork.Curriculum, Matwork.Platform, Matwork.Media],
```

(Register `Matwork.Media` now too; its resource is added in Task 3. Ash tolerates a domain declared before its resources exist only if the domain module lists no missing resources — so add `Matwork.Media` to this list in Task 3 instead if compilation complains. Safe order: add only `Matwork.Platform` here, add `Matwork.Media` in Task 3 Step 1.)

Use this exact line for Task 2:

```elixir
  ash_domains: [Matwork.Accounts, Matwork.Gyms, Matwork.Curriculum, Matwork.Platform],
```

- [ ] **Step 2: Write the system actor + check**

Create `lib/matwork/platform/system_actor.ex`:

```elixir
defmodule Matwork.Platform.SystemActor do
  @moduledoc """
  The actor used by webhook-driven Oban jobs, where there is no human actor.
  Policies authorize this struct explicitly (see `Platform.Checks.SystemActor`)
  so that webhook processing keeps authorization on the resource rather than
  reaching for `authorize?: false` (per CLAUDE.md §3.4 of the spec).
  """
  defstruct []
end
```

Create `lib/matwork/platform/checks/system_actor.ex`:

```elixir
defmodule Matwork.Platform.Checks.SystemActor do
  @moduledoc "Policy check: is the actor the `%Matwork.Platform.SystemActor{}`?"
  use Ash.Policy.SimpleCheck

  def describe(_opts), do: "actor is the system actor"

  def match?(%Matwork.Platform.SystemActor{}, _context, _opts), do: true
  def match?(_actor, _context, _opts), do: false
end
```

- [ ] **Step 3: Write the `WebhookEvent` resource**

Create `lib/matwork/platform/webhook_event.ex`. Global (no multitenancy). Idempotent on `(provider, external_id)` via upsert. Only the system actor may read/write it.

```elixir
defmodule Matwork.Platform.WebhookEvent do
  @moduledoc """
  Idempotent ledger of inbound provider webhooks (Mux now; Stripe in M2).
  Global resource. Recorded by the webhook controller and processed by an Oban
  job — never processed inline. Uniqueness on `(provider, external_id)` makes
  double-delivery a no-op upsert.
  """
  use Ash.Resource,
    otp_app: :matwork,
    domain: Matwork.Platform,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "webhook_events"
    repo Matwork.Repo
  end

  actions do
    defaults [:read]

    create :record do
      accept [:provider, :external_id, :payload]
      upsert? true
      upsert_identity :unique_provider_event
      # On duplicate delivery, keep the original row untouched.
      upsert_fields []
    end

    update :mark_processed do
      accept []
      change set_attribute(:processed_at, &DateTime.utc_now/0)
    end
  end

  policies do
    # Only webhook-processing code (the system actor) touches this resource.
    bypass Matwork.Platform.Checks.SystemActor do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :provider, :atom do
      constraints one_of: [:stripe, :mux]
      allow_nil? false
      public? true
    end

    attribute :external_id, :string do
      allow_nil? false
      public? true
    end

    attribute :payload, :map do
      allow_nil? false
      public? true
    end

    attribute :processed_at, :utc_datetime do
      public? true
    end

    timestamps()
  end

  identities do
    identity :unique_provider_event, [:provider, :external_id]
  end
end
```

- [ ] **Step 4: Write the `Matwork.Platform` domain**

Create `lib/matwork/platform.ex`:

```elixir
defmodule Matwork.Platform do
  @moduledoc "Operational domain: the inbound-webhook ledger."
  use Ash.Domain, otp_app: :matwork

  resources do
    resource Matwork.Platform.WebhookEvent do
      define :record_webhook_event, action: :record, args: [:provider, :external_id, :payload]
      define :get_webhook_event, action: :read, get_by: [:id]
      define :mark_webhook_processed, action: :mark_processed
    end
  end
end
```

- [ ] **Step 5: Write the signature verifier (plain module)**

Create `lib/matwork/platform/mux/signature.ex`:

```elixir
defmodule Matwork.Platform.Mux.Signature do
  @moduledoc """
  Verifies a Mux webhook `Mux-Signature` header against the raw request body.
  Header format: `t=<unix_ts>,v1=<hex_hmac_sha256>`; the signed payload is
  `"<t>.<raw_body>"` keyed by the webhook secret. Local crypto only — not a
  Mux API call, so it is not part of the `Platform.Mux` behaviour.
  """

  @spec verify(raw_body :: binary(), header :: String.t() | nil, secret :: String.t()) ::
          :ok | :error
  def verify(raw_body, header, secret)
      when is_binary(raw_body) and is_binary(header) and is_binary(secret) do
    with %{"t" => t, "v1" => provided} <- parse(header),
         expected <- sign(t, raw_body, secret),
         true <- Plug.Crypto.secure_compare(expected, provided) do
      :ok
    else
      _ -> :error
    end
  end

  def verify(_raw_body, _header, _secret), do: :error

  defp parse(header) do
    header
    |> String.split(",")
    |> Enum.map(&String.split(&1, "=", parts: 2))
    |> Enum.reduce(%{}, fn
      [k, v], acc -> Map.put(acc, String.trim(k), v)
      _, acc -> acc
    end)
  end

  defp sign(t, raw_body, secret) do
    :hmac
    |> :crypto.mac(:sha256, secret, "#{t}.#{raw_body}")
    |> Base.encode16(case: :lower)
  end
end
```

- [ ] **Step 6: Write the signature test**

Create `test/matwork/platform/mux/signature_test.exs`:

```elixir
defmodule Matwork.Platform.Mux.SignatureTest do
  use ExUnit.Case, async: true

  alias Matwork.Platform.Mux.Signature

  @secret "test_mux_secret"
  @body ~s({"type":"video.asset.ready","id":"evt_1"})

  defp header(body, secret, t \\ "1600000000") do
    v1 =
      :crypto.mac(:hmac, :sha256, secret, "#{t}.#{body}") |> Base.encode16(case: :lower)

    "t=#{t},v1=#{v1}"
  end

  test "accepts a correctly signed body" do
    assert Signature.verify(@body, header(@body, @secret), @secret) == :ok
  end

  test "rejects a tampered body" do
    assert Signature.verify(@body <> "x", header(@body, @secret), @secret) == :error
  end

  test "rejects a wrong secret" do
    assert Signature.verify(@body, header(@body, "other"), @secret) == :error
  end

  test "rejects a missing/garbage header" do
    assert Signature.verify(@body, nil, @secret) == :error
    assert Signature.verify(@body, "nonsense", @secret) == :error
  end
end
```

- [ ] **Step 7: Generate the migration**

Run: `mix ash.codegen create_webhook_events` then `mix ecto.migrate`
Expected: a migration creating `webhook_events` with a unique index on `(provider, external_id)`; applies cleanly.

- [ ] **Step 8: Write the `WebhookEvent` test**

Create `test/matwork/platform/webhook_event_test.exs`:

```elixir
defmodule Matwork.Platform.WebhookEventTest do
  use Matwork.DataCase, async: true

  import Matwork.Generator

  alias Matwork.Platform
  alias Matwork.Platform.SystemActor

  @system %SystemActor{}

  test "record is idempotent on (provider, external_id)" do
    {:ok, first} =
      Platform.record_webhook_event(:mux, "evt_1", %{"type" => "video.asset.ready"},
        actor: @system
      )

    {:ok, second} =
      Platform.record_webhook_event(:mux, "evt_1", %{"type" => "video.asset.ready"},
        actor: @system
      )

    assert first.id == second.id

    count =
      Matwork.Platform.WebhookEvent
      |> Ash.count!(actor: @system)

    assert count == 1
  end

  test "mark_processed sets processed_at" do
    {:ok, event} =
      Platform.record_webhook_event(:mux, "evt_2", %{"type" => "x"}, actor: @system)

    {:ok, processed} = Platform.mark_webhook_processed(event, actor: @system)
    refute is_nil(processed.processed_at)
  end

  test "a normal user cannot read or record webhook events" do
    user = generate(user())

    assert {:error, %Ash.Error.Forbidden{}} =
             Platform.record_webhook_event(:mux, "evt_3", %{}, actor: user)
  end
end
```

- [ ] **Step 9: Run tests, format, lint, commit**

Run: `mix test test/matwork/platform/` (expect PASS).

```bash
mix format
mix credo --strict
git add config/config.exs lib/matwork/platform.ex lib/matwork/platform/ test/matwork/platform/ priv/repo/migrations
git commit -m "Add Platform domain, WebhookEvent ledger, and system actor"
```

---

## Task 3: `Media` domain + `Video` resource

**Files:**
- Create: `lib/matwork/media.ex`, `lib/matwork/media/video.ex`
- Modify: `config/config.exs` (add `Matwork.Media` to `ash_domains`), `test/support/generator.ex`
- Test: `test/matwork/media/video_test.exs`

**Interfaces:**
- Consumes: `Platform.Mux` (T1), `Platform.Checks.SystemActor` + `SystemActor` (T2), `Matwork.Gyms.Checks.ActiveMember` (existing, parameterized on `:roles`).
- Produces (used by T4, T5, T6):
  - `Matwork.Media.create_direct_upload(title, opts) :: {:ok, {Video.t(), upload_url :: String.t()}} | {:error, term}` — calls Mux, creates the `Video`.
  - Code interfaces: `get_video(id, opts)`, `get_video_by_upload_id(upload_id, opts)`, `mark_video_processing(video, params, opts)`, `mark_video_ready(video, params, opts)`, `mark_video_errored(video, opts)`.
  - Generator `video(opts)` — `seed_generator` for `Video`, accepts `gym:` and `uploaded_by:`.

- [ ] **Step 1: Register the domain**

`config/config.exs` — extend `ash_domains` to its final Session-2 form:

```elixir
  ash_domains: [Matwork.Accounts, Matwork.Gyms, Matwork.Curriculum, Matwork.Platform, Matwork.Media],
```

- [ ] **Step 2: Write the `Video` resource**

Create `lib/matwork/media/video.ex`. Managers (owner/instructor) create/read; only the system actor runs the `mark_*` transitions.

```elixir
defmodule Matwork.Media.Video do
  @moduledoc """
  A Mux-backed video. Tenant-scoped on `gym_id`. Created in `:pending_upload`
  when an instructor starts a direct upload; driven to `:processing`/`:ready`/
  `:errored` by webhook-processing jobs running as the system actor. Playback
  IDs are signed-policy; minting playback JWTs is Session 3, not here.
  """
  use Ash.Resource,
    otp_app: :matwork,
    domain: Matwork.Media,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "videos"
    repo Matwork.Repo

    custom_indexes do
      index [:gym_id]
      index [:mux_upload_id]
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:mux_upload_id, :title]
      change relate_actor(:uploaded_by)
    end

    read :by_upload_id do
      argument :mux_upload_id, :string, allow_nil?: false
      get? true
      filter expr(mux_upload_id == ^arg(:mux_upload_id))
    end

    update :mark_processing do
      accept [:mux_asset_id]
      change set_attribute(:status, :processing)
    end

    update :mark_ready do
      accept [:mux_asset_id, :mux_playback_id, :duration_seconds]
      change set_attribute(:status, :ready)
    end

    update :mark_errored do
      accept []
      change set_attribute(:status, :errored)
    end
  end

  policies do
    # Webhook jobs (system actor) may do anything, including the mark_* writes.
    bypass Matwork.Platform.Checks.SystemActor do
      authorize_if always()
    end

    policy action_type([:create, :read]) do
      authorize_if {Matwork.Gyms.Checks.ActiveMember, roles: [:owner, :instructor]}
    end

    # mark_* updates have no non-system policy → forbidden for everyone else.
  end

  multitenancy do
    strategy :attribute
    attribute :gym_id
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      public? true
    end

    attribute :mux_upload_id, :string do
      allow_nil? false
      public? true
    end

    attribute :mux_asset_id, :string do
      public? true
    end

    attribute :mux_playback_id, :string do
      public? true
    end

    attribute :status, :atom do
      constraints one_of: [:pending_upload, :processing, :ready, :errored]
      default :pending_upload
      allow_nil? false
      public? true
    end

    attribute :duration_seconds, :integer do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :gym, Matwork.Gyms.Gym do
      allow_nil? false
      public? true
    end

    belongs_to :uploaded_by, Matwork.Accounts.User do
      allow_nil? false
      public? true
    end
  end
end
```

- [ ] **Step 3: Write the `Matwork.Media` domain**

Create `lib/matwork/media.ex`. `create_direct_upload/2` is the orchestration seam: it calls Mux (passing the tenant as `passthrough` so the webhook can resolve the gym without a cross-tenant scan), then creates the `Video`.

```elixir
defmodule Matwork.Media do
  @moduledoc "The Media domain: Mux-backed videos and their upload lifecycle."
  use Ash.Domain, otp_app: :matwork

  resources do
    resource Matwork.Media.Video do
      define :create_video, action: :create, args: [:mux_upload_id, :title]
      define :get_video, action: :read, get_by: [:id]
      define :get_video_by_upload_id, action: :by_upload_id, args: [:mux_upload_id]
      define :mark_video_processing, action: :mark_processing
      define :mark_video_ready, action: :mark_ready
      define :mark_video_errored, action: :mark_errored
    end
  end

  @doc """
  Start a Mux direct upload for the current tenant and record a `Video` in
  `:pending_upload`. Returns `{:ok, {video, upload_url}}`; the caller hands
  `upload_url` to the browser (via the MuxUpload JS hook) — video bytes never
  touch the server. `opts` must include `:actor` and `:tenant`.
  """
  def create_direct_upload(title, opts) do
    tenant = Keyword.fetch!(opts, :tenant)

    with {:ok, %{id: upload_id, url: upload_url}} <-
           Matwork.Platform.Mux.create_direct_upload(%{passthrough: tenant}),
         {:ok, video} <- create_video(upload_id, title, opts) do
      {:ok, {video, upload_url}}
    end
  end
end
```

- [ ] **Step 4: Add the `video` generator**

In `test/support/generator.ex`, add:

```elixir
  def video(opts \\ []) do
    {owning_gym, opts} = Keyword.pop(opts, :gym)
    {uploader, opts} = Keyword.pop(opts, :uploaded_by)

    owning_gym = owning_gym || generate(gym())
    uploader = uploader || %Matwork.Accounts.User{id: owning_gym.owner_id}

    seed_generator(
      %Matwork.Media.Video{
        gym_id: owning_gym.id,
        uploaded_by_id: uploader.id,
        title: sequence(:video_title, &"Video #{&1}"),
        mux_upload_id: sequence(:mux_upload_id, &"upload_#{&1}"),
        status: :pending_upload
      },
      overrides: opts
    )
  end
```

- [ ] **Step 5: Generate the migration**

Run: `mix ash.codegen create_videos` then `mix ecto.migrate`
Expected: a `videos` table with the upload/asset/playback columns and indexes; applies cleanly.

- [ ] **Step 6: Write the failing tests**

Create `test/matwork/media/video_test.exs`. Mux is stubbed with Mox (the call happens in the test process, so private-mode Mox works with `async: true`).

```elixir
defmodule Matwork.Media.VideoTest do
  use Matwork.DataCase, async: true

  import Mox
  import Matwork.Generator

  alias Matwork.Media
  alias Matwork.Platform.SystemActor

  setup :verify_on_exit!

  @system %SystemActor{}

  describe "create_direct_upload/2" do
    test "an instructor starts an upload; Mux gets the tenant as passthrough" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      instructor = generate(user())
      generate(membership(gym: gym, user: instructor, role: :instructor))

      Matwork.Platform.MuxMock
      |> expect(:create_direct_upload, fn %{passthrough: passthrough} ->
        assert passthrough == gym.id
        {:ok, %{id: "upload_xyz", url: "https://storage.example/put"}}
      end)

      assert {:ok, {video, "https://storage.example/put"}} =
               Media.create_direct_upload("Armbar", actor: instructor, tenant: gym.id)

      assert video.mux_upload_id == "upload_xyz"
      assert video.status == :pending_upload
      assert video.uploaded_by_id == instructor.id
    end

    test "a student cannot start an upload" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      student = generate(user())
      generate(membership(gym: gym, user: student, role: :student))

      # Mux stub with no expectation — a forbidden create must never reach Mux.
      stub(Matwork.Platform.MuxMock, :create_direct_upload, fn _ ->
        flunk("Mux must not be called for a forbidden upload")
      end)

      assert {:error, %Ash.Error.Forbidden{}} =
               Media.create_direct_upload("Nope", actor: student, tenant: gym.id)
    end
  end

  describe "mark_* transitions (system actor only)" do
    test "mark_video_ready sets asset/playback/duration and status" do
      gym = generate(gym())
      video = generate(video(gym: gym))

      {:ok, ready} =
        Media.mark_video_ready(
          video,
          %{mux_asset_id: "asset_1", mux_playback_id: "pb_1", duration_seconds: 42},
          actor: @system,
          tenant: gym.id
        )

      assert ready.status == :ready
      assert ready.mux_asset_id == "asset_1"
      assert ready.mux_playback_id == "pb_1"
      assert ready.duration_seconds == 42
    end

    test "a normal manager cannot run mark_video_ready" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      video = generate(video(gym: gym))

      assert {:error, %Ash.Error.Forbidden{}} =
               Media.mark_video_ready(video, %{mux_asset_id: "a"}, actor: owner, tenant: gym.id)
    end
  end

  describe "read" do
    test "get_video_by_upload_id finds within the tenant" do
      gym = generate(gym())
      video = generate(video(gym: gym, mux_upload_id: "upload_find_me"))

      {:ok, found} =
        Media.get_video_by_upload_id("upload_find_me", actor: %SystemActor{}, tenant: gym.id)

      assert found.id == video.id
    end

    test "tenancy isolation: a manager in gym A cannot read gym B's video" do
      gym_a = generate(gym())
      manager_a = generate(user())
      generate(membership(gym: gym_a, user: manager_a, role: :instructor))

      gym_b = generate(gym())
      video_b = generate(video(gym: gym_b))

      assert {:error, %Ash.Error.Forbidden{}} =
               Media.get_video(video_b.id, actor: manager_a, tenant: gym_b.id)
    end
  end
end
```

- [ ] **Step 7: Run tests, format, lint, commit**

Run: `mix test test/matwork/media/video_test.exs` (expect PASS).

```bash
mix format
mix credo --strict
git add config/config.exs lib/matwork/media.ex lib/matwork/media/video.ex test/support/generator.ex test/matwork/media/video_test.exs priv/repo/migrations
git commit -m "Add Media domain and Video resource with Mux direct upload"
```

---

## Task 4: Mux webhook controller + Oban processing + live broadcast

**Files:**
- Create: `lib/matwork_web/plugs/cache_raw_body.ex`, `lib/matwork_web/controllers/webhook_controller.ex`, `lib/matwork/media/jobs/process_mux_webhook.ex`
- Modify: `lib/matwork_web/endpoint.ex`, `lib/matwork_web/router.ex`
- Test: `test/matwork/media/jobs/process_mux_webhook_test.exs`, `test/matwork_web/controllers/webhook_controller_test.exs`

**Interfaces:**
- Consumes: `Platform.record_webhook_event/4`, `Platform.get_webhook_event/2`, `Platform.mark_webhook_processed/2`, `Platform.Mux.Signature.verify/3` (T2); `Media.get_video_by_upload_id/2`, `Media.mark_video_ready/3`, `Media.mark_video_errored/2`, `Media.mark_video_processing/3` (T3).
- Produces (used by T6): PubSub messages `{:video_updated, video_id}` on topic `"gym:#{gym_id}:videos"` (via `Matwork.PubSub`). Route `POST /webhooks/mux`.

- [ ] **Step 1: Cache the raw body for the webhook path**

Create `lib/matwork_web/plugs/cache_raw_body.ex`:

```elixir
defmodule MatworkWeb.Plugs.CacheRawBody do
  @moduledoc """
  Custom `Plug.Parsers` body reader that stashes the raw request body on the
  conn for webhook paths, so a controller can verify an HMAC signature over the
  exact bytes the provider signed. Scoped to `/webhooks/` to avoid retaining
  every request body in memory.
  """
  @spec read_body(Plug.Conn.t(), keyword()) ::
          {:ok, binary(), Plug.Conn.t()} | {:more, binary(), Plug.Conn.t()} | {:error, term()}
  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} -> {:ok, body, cache(conn, body)}
      {:more, body, conn} -> {:more, body, cache(conn, body)}
      other -> other
    end
  end

  defp cache(%Plug.Conn{request_path: "/webhooks/" <> _} = conn, body) do
    Plug.Conn.update_in(conn.assigns[:raw_body], fn
      nil -> [body]
      chunks -> [body | chunks]
    end)
  end

  defp cache(conn, _body), do: conn

  @doc "Returns the accumulated raw body (or nil) as a single binary."
  def raw_body(%Plug.Conn{assigns: %{raw_body: chunks}}) when is_list(chunks) do
    chunks |> Enum.reverse() |> IO.iodata_to_binary()
  end

  def raw_body(_conn), do: nil
end
```

`lib/matwork_web/endpoint.ex` — add `body_reader:` to the existing `Plug.Parsers` (lines 51–54):

```elixir
  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library(),
    body_reader: {MatworkWeb.Plugs.CacheRawBody, :read_body, []}
```

- [ ] **Step 2: Write the Oban worker**

Create `lib/matwork/media/jobs/process_mux_webhook.ex`. Resolves the tenant from `passthrough`, finds the `Video` by `upload_id`, applies the transition as the system actor, marks the event processed, and broadcasts.

```elixir
defmodule Matwork.Media.Jobs.ProcessMuxWebhook do
  @moduledoc """
  Processes one recorded Mux `WebhookEvent`: resolves the tenant from the
  event's `passthrough` (the gym_id we set at upload time), applies the matching
  `Video` transition as the system actor, marks the event processed, and
  broadcasts `{:video_updated, video_id}` so open builder LiveViews refresh.
  Idempotent: a re-run of an already-processed event is a no-op.
  """
  use Oban.Worker, queue: :default, max_attempts: 5

  alias Matwork.Media
  alias Matwork.Platform
  alias Matwork.Platform.SystemActor

  @system %SystemActor{}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"webhook_event_id" => id}}) do
    {:ok, event} = Platform.get_webhook_event(id, actor: @system)

    if event.processed_at do
      :ok
    else
      :ok = handle(event.payload)
      {:ok, _} = Platform.mark_webhook_processed(event, actor: @system)
      :ok
    end
  end

  # ⚠️ Verify these payload paths against docs.mux.com (see the Mux-contract
  # callout in Global Constraints).
  defp handle(%{"type" => "video.asset.ready", "data" => data}) do
    tenant = data["passthrough"]
    playback_id = data |> Map.get("playback_ids", []) |> List.first() |> playback_id()

    with_video(tenant, data["upload_id"], fn video ->
      Media.mark_video_ready(
        video,
        %{
          mux_asset_id: data["id"],
          mux_playback_id: playback_id,
          duration_seconds: duration(data["duration"])
        },
        actor: @system,
        tenant: tenant
      )
    end)
  end

  defp handle(%{"type" => "video.upload.asset_created", "data" => data}) do
    tenant = data["passthrough"]

    with_video(tenant, data["upload_id"], fn video ->
      Media.mark_video_processing(video, %{mux_asset_id: data["asset_id"]},
        actor: @system,
        tenant: tenant
      )
    end)
  end

  defp handle(%{"type" => "video.asset.errored", "data" => data}) do
    tenant = data["passthrough"]

    with_video(tenant, data["upload_id"], fn video ->
      Media.mark_video_errored(video, actor: @system, tenant: tenant)
    end)
  end

  # Unhandled event types are recorded (for audit/replay) but need no action.
  defp handle(_payload), do: :ok

  defp with_video(nil, _upload_id, _fun), do: :ok
  defp with_video(_tenant, nil, _fun), do: :ok

  defp with_video(tenant, upload_id, fun) do
    case Media.get_video_by_upload_id(upload_id, actor: @system, tenant: tenant) do
      {:ok, video} ->
        {:ok, updated} = fun.(video)
        broadcast(tenant, updated.id)
        :ok

      # The Video may not exist yet (webhook raced the upload record) — let Oban
      # retry via max_attempts by raising, so a later attempt finds it.
      {:error, _} ->
        raise "video for upload #{upload_id} not found in tenant #{tenant}"
    end
  end

  defp broadcast(tenant, video_id) do
    Phoenix.PubSub.broadcast(Matwork.PubSub, "gym:#{tenant}:videos", {:video_updated, video_id})
  end

  defp playback_id(%{"id" => id}), do: id
  defp playback_id(_), do: nil

  defp duration(seconds) when is_number(seconds), do: trunc(seconds)
  defp duration(_), do: nil
end
```

- [ ] **Step 3: Write the webhook controller**

Create `lib/matwork_web/controllers/webhook_controller.ex`:

```elixir
defmodule MatworkWeb.WebhookController do
  use MatworkWeb, :controller

  alias Matwork.Media.Jobs.ProcessMuxWebhook
  alias Matwork.Platform
  alias Matwork.Platform.Mux.Signature
  alias Matwork.Platform.SystemActor
  alias MatworkWeb.Plugs.CacheRawBody

  @system %SystemActor{}

  def mux(conn, params) do
    raw_body = CacheRawBody.raw_body(conn)
    signature = conn |> get_req_header("mux-signature") |> List.first()
    secret = Application.fetch_env!(:matwork, :mux_webhook_secret)

    case Signature.verify(raw_body, signature, secret) do
      :ok -> record_and_enqueue(conn, params)
      :error -> send_resp(conn, 400, "invalid signature")
    end
  end

  defp record_and_enqueue(conn, %{"id" => external_id} = params) do
    with {:ok, event} <-
           Platform.record_webhook_event(:mux, external_id, params, actor: @system),
         {:ok, _job} <-
           %{"webhook_event_id" => event.id} |> ProcessMuxWebhook.new() |> Oban.insert() do
      send_resp(conn, 200, "")
    else
      _ -> send_resp(conn, 200, "")
    end
  end

  # A Mux webhook always carries a top-level "id"; anything else is noise.
  defp record_and_enqueue(conn, _params), do: send_resp(conn, 400, "missing id")
end
```

- [ ] **Step 4: Route it**

`lib/matwork_web/router.ex` — add a minimal pipeline and scope (the webhook is unauthenticated and global — no `:browser`, no tenant). Place after the existing `:api` pipeline:

```elixir
  pipeline :webhooks do
    plug :accepts, ["json"]
  end

  scope "/webhooks", MatworkWeb do
    pipe_through :webhooks

    post "/mux", WebhookController, :mux
  end
```

- [ ] **Step 5: Write the Oban job test**

Create `test/matwork/media/jobs/process_mux_webhook_test.exs`. Oban is `testing: :manual`, so run the job directly with `Oban.Testing.perform_job/3`.

```elixir
defmodule Matwork.Media.Jobs.ProcessMuxWebhookTest do
  use Matwork.DataCase, async: true
  use Oban.Testing, repo: Matwork.Repo

  import Matwork.Generator

  alias Matwork.Media
  alias Matwork.Media.Jobs.ProcessMuxWebhook
  alias Matwork.Platform
  alias Matwork.Platform.SystemActor

  @system %SystemActor{}

  defp ready_payload(gym_id, upload_id) do
    %{
      "type" => "video.asset.ready",
      "id" => "evt_#{upload_id}",
      "data" => %{
        "id" => "asset_1",
        "upload_id" => upload_id,
        "passthrough" => gym_id,
        "duration" => 42.7,
        "playback_ids" => [%{"id" => "pb_1", "policy" => "signed"}]
      }
    }
  end

  test "processing a ready event marks the video ready and processed" do
    gym = generate(gym())
    video = generate(video(gym: gym, mux_upload_id: "upload_ready"))
    payload = ready_payload(gym.id, "upload_ready")

    {:ok, event} =
      Platform.record_webhook_event(:mux, payload["id"], payload, actor: @system)

    assert :ok = perform_job(ProcessMuxWebhook, %{"webhook_event_id" => event.id})

    {:ok, reloaded} = Media.get_video(video.id, actor: @system, tenant: gym.id)
    assert reloaded.status == :ready
    assert reloaded.mux_playback_id == "pb_1"
    assert reloaded.duration_seconds == 42

    {:ok, processed_event} = Platform.get_webhook_event(event.id, actor: @system)
    refute is_nil(processed_event.processed_at)
  end

  test "re-processing an already-processed event is a no-op" do
    gym = generate(gym())
    generate(video(gym: gym, mux_upload_id: "upload_twice"))
    payload = ready_payload(gym.id, "upload_twice")

    {:ok, event} =
      Platform.record_webhook_event(:mux, payload["id"], payload, actor: @system)

    assert :ok = perform_job(ProcessMuxWebhook, %{"webhook_event_id" => event.id})
    assert :ok = perform_job(ProcessMuxWebhook, %{"webhook_event_id" => event.id})
  end

  test "broadcasts to the gym's video topic" do
    gym = generate(gym())
    generate(video(gym: gym, mux_upload_id: "upload_bcast"))
    payload = ready_payload(gym.id, "upload_bcast")

    Phoenix.PubSub.subscribe(Matwork.PubSub, "gym:#{gym.id}:videos")

    {:ok, event} =
      Platform.record_webhook_event(:mux, payload["id"], payload, actor: @system)

    perform_job(ProcessMuxWebhook, %{"webhook_event_id" => event.id})

    assert_receive {:video_updated, _video_id}
  end
end
```

- [ ] **Step 6: Write the controller test (signature + idempotency + enqueue)**

Create `test/matwork_web/controllers/webhook_controller_test.exs`:

```elixir
defmodule MatworkWeb.WebhookControllerTest do
  use MatworkWeb.ConnCase, async: true
  use Oban.Testing, repo: Matwork.Repo

  alias Matwork.Media.Jobs.ProcessMuxWebhook

  @secret "test_mux_secret"

  defp signed(conn, body) do
    t = "1600000000"
    v1 = :crypto.mac(:hmac, :sha256, @secret, "#{t}.#{body}") |> Base.encode16(case: :lower)

    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("mux-signature", "t=#{t},v1=#{v1}")
    |> post("/webhooks/mux", body)
  end

  test "a validly signed event is recorded and a job is enqueued", %{conn: conn} do
    body = ~s({"type":"video.asset.ready","id":"evt_ctrl_1","data":{"passthrough":"g","upload_id":"u"}})

    conn = signed(conn, body)

    assert response(conn, 200)
    assert_enqueued(worker: ProcessMuxWebhook)
  end

  test "a duplicate delivery enqueues based on one recorded event", %{conn: conn} do
    body = ~s({"type":"video.asset.ready","id":"evt_ctrl_dup","data":{"passthrough":"g","upload_id":"u"}})

    signed(conn, body)
    signed(recycle(conn), body)

    count = Matwork.Platform.WebhookEvent |> Ash.count!(actor: %Matwork.Platform.SystemActor{})
    assert count == 1
  end

  test "a badly signed event is rejected", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("mux-signature", "t=1600000000,v1=deadbeef")
      |> post("/webhooks/mux", ~s({"type":"x","id":"evt_bad"}))

    assert response(conn, 400)
    refute_enqueued(worker: ProcessMuxWebhook)
  end
end
```

Note for the implementer: if `post/3` with a raw string body doesn't reach `CacheRawBody` as expected under `Phoenix.ConnTest`, pass the body as a raw string (as above) — `ConnTest` sends it through the endpoint's parser stack, so the `body_reader` runs. If the signature test can't see the raw body, verify the `body_reader` is on the endpoint's `Plug.Parsers` (Task 4 Step 1) and that the path matches `/webhooks/`.

- [ ] **Step 7: Run tests, format, lint, commit**

Run: `mix test test/matwork/media/jobs test/matwork_web/controllers/webhook_controller_test.exs` (expect PASS).

```bash
mix format
mix credo --strict
git add lib/matwork_web/plugs/cache_raw_body.ex lib/matwork_web/controllers/webhook_controller.ex lib/matwork/media/jobs/ lib/matwork_web/endpoint.ex lib/matwork_web/router.ex test/matwork/media/jobs test/matwork_web/controllers/webhook_controller_test.exs
git commit -m "Add Mux webhook controller and Oban processing job"
```

---

## Task 5: `Lesson.video_id` + attach/detach

**Files:**
- Create: `lib/matwork/curriculum/validations/video_in_tenant.ex`
- Modify: `lib/matwork/curriculum/lesson.ex`, `lib/matwork/curriculum.ex`
- Test: `test/matwork/curriculum/lesson_video_test.exs`

**Interfaces:**
- Consumes: `Media.Video` (T3); the existing `Validations.SectionInTenant` pattern.
- Produces (used by T6): `Curriculum.attach_lesson_video(lesson, video, opts)`, `Curriculum.detach_lesson_video(lesson, opts)`; `Lesson.video` relationship (nullable).

- [ ] **Step 1: Write the `VideoInTenant` validation**

Create `lib/matwork/curriculum/validations/video_in_tenant.ex` (mirrors `Validations.SectionInTenant`):

```elixir
defmodule Matwork.Curriculum.Validations.VideoInTenant do
  @moduledoc """
  Validates that a Lesson's `video_id` resolves to a `Video` in the same tenant
  (gym_id) as the change. Prevents a curriculum manager in one gym from
  attaching another gym's video by passing an arbitrary video_id.
  """
  use Ash.Resource.Validation

  require Ash.Query

  @impl true
  def validate(changeset, _opts, _context) do
    video_id = Ash.Changeset.get_attribute(changeset, :video_id)
    tenant = changeset.tenant

    cond do
      is_nil(video_id) ->
        :ok

      Matwork.Media.Video
      |> Ash.Query.filter(id == ^video_id)
      |> Ash.exists?(tenant: tenant, authorize?: false) ->
        :ok

      true ->
        {:error, field: :video_id, message: "must belong to this gym"}
    end
  end
end
```

- [ ] **Step 2: Add `video_id` + attach/detach actions to `Lesson`**

`lib/matwork/curriculum/lesson.ex` — in `actions do`, add after `set_position`:

```elixir
    update :attach_video do
      accept [:video_id]
      validate {Matwork.Curriculum.Validations.VideoInTenant, []}
    end

    update :detach_video do
      accept []
      change set_attribute(:video_id, nil)
    end
```

In `relationships do`, add (nullable — a lesson may have no video):

```elixir
    belongs_to :video, Matwork.Media.Video do
      allow_nil? true
      public? true
    end
```

The existing `policy action_type([:create, :update, :destroy])` (ManagesCurriculum) already covers `attach_video`/`detach_video` — no policy change needed. Update the moduledoc's "added in Session 2" note to past tense.

- [ ] **Step 3: Add domain interfaces**

`lib/matwork/curriculum.ex` — inside the `Lesson` resource block, add:

```elixir
      define :attach_lesson_video_by_id, action: :attach_video
      define :detach_lesson_video, action: :detach_video
```

And add a thin wrapper to the module body so callers pass a `%Video{}`:

```elixir
  @doc "Attach `video` to `lesson` (both must be in `opts[:tenant]`)."
  def attach_lesson_video(lesson, video, opts) do
    attach_lesson_video_by_id(lesson, %{video_id: video.id}, opts)
  end
```

- [ ] **Step 4: Generate the migration**

Run: `mix ash.codegen add_lesson_video` then `mix ecto.migrate`
Expected: an `ALTER TABLE lessons ADD COLUMN video_id` (nullable FK to `videos`). Applies cleanly. Existing lesson tests still pass (the column is nullable with no default behavior change).

- [ ] **Step 5: Write the failing tests**

Create `test/matwork/curriculum/lesson_video_test.exs`:

```elixir
defmodule Matwork.Curriculum.LessonVideoTest do
  use Matwork.DataCase, async: true

  import Matwork.Generator

  alias Matwork.Curriculum

  test "an instructor can attach a same-gym video to a lesson" do
    owner = generate(user())
    gym = generate(gym(owner: owner))
    lesson = generate(lesson(section: generate(section(course: generate(course(gym: gym))))))
    video = generate(video(gym: gym))

    {:ok, updated} = Curriculum.attach_lesson_video(lesson, video, actor: owner, tenant: gym.id)

    assert updated.video_id == video.id
  end

  test "attaching another gym's video is rejected" do
    owner = generate(user())
    gym = generate(gym(owner: owner))
    lesson = generate(lesson(section: generate(section(course: generate(course(gym: gym))))))

    other_gym = generate(gym())
    foreign_video = generate(video(gym: other_gym))

    assert {:error, %Ash.Error.Invalid{}} =
             Curriculum.attach_lesson_video(lesson, foreign_video, actor: owner, tenant: gym.id)
  end

  test "a student cannot attach a video" do
    owner = generate(user())
    gym = generate(gym(owner: owner))
    student = generate(user())
    generate(membership(gym: gym, user: student, role: :student))
    lesson = generate(lesson(section: generate(section(course: generate(course(gym: gym))))))
    video = generate(video(gym: gym))

    assert {:error, %Ash.Error.Forbidden{}} =
             Curriculum.attach_lesson_video(lesson, video, actor: student, tenant: gym.id)
  end

  test "detach clears the video" do
    owner = generate(user())
    gym = generate(gym(owner: owner))
    lesson = generate(lesson(section: generate(section(course: generate(course(gym: gym))))))
    video = generate(video(gym: gym))
    {:ok, attached} = Curriculum.attach_lesson_video(lesson, video, actor: owner, tenant: gym.id)

    {:ok, detached} = Curriculum.detach_lesson_video(attached, actor: owner, tenant: gym.id)

    assert is_nil(detached.video_id)
  end
end
```

- [ ] **Step 6: Run tests, format, lint, commit**

Run: `mix test test/matwork/curriculum/lesson_video_test.exs` plus the existing `test/matwork/curriculum/lesson_test.exs` (expect all PASS).

```bash
mix format
mix credo --strict
git add lib/matwork/curriculum/validations/video_in_tenant.ex lib/matwork/curriculum/lesson.ex lib/matwork/curriculum.ex test/matwork/curriculum/lesson_video_test.exs priv/repo/migrations
git commit -m "Add nullable Lesson.video_id with tenant-guarded attach/detach"
```

---

## Task 6: Course-builder upload UI + live status

Wires the browser→Mux upload into the builder: a per-lesson upload control (JS hook using UpChunk), a status badge, and a PubSub subscription that flips the badge to "Ready" when the webhook job finishes.

**Files:**
- Create: `lib/stalwart_ui/video_upload_field.ex`, `assets/js/hooks/mux_upload.js`, `assets/package.json`
- Modify: `lib/stalwart_ui/curriculum_tree.ex`, `lib/matwork/curriculum.ex` (`load_course_tree` loads `:video`), `lib/matwork_web/live/course_builder_live.ex`, `assets/js/app.js`, `COMPONENTS.md`
- Test: `test/stalwart_ui/video_upload_field_test.exs`, `test/matwork_web/live/course_builder_upload_test.exs`

**Interfaces:**
- Consumes: `Media.create_direct_upload/2` (T3), `Curriculum.attach_lesson_video/3` (T5), PubSub `{:video_updated, id}` (T4), `StalwartUI.CurriculumTree` (existing).
- Produces: `StalwartUI.VideoUploadField.video_upload_field/1`; `MuxUpload` JS hook.

- [ ] **Step 1: Load `:video` in the course tree**

`lib/matwork/curriculum.ex` — in `load_course_tree/2`, load each lesson's video so the builder can show status. Change the `lessons_query`:

```elixir
    lessons_query =
      Matwork.Curriculum.Lesson
      |> Ash.Query.sort(position: :asc)
      |> Ash.Query.load(:video)
```

(The `:video` relationship read runs as the same manager actor; managers can read videos per Task 3's read policy.)

- [ ] **Step 2: Write the `VideoUploadField` component**

Create `lib/stalwart_ui/video_upload_field.ex`. Plain assigns; the hook name and event name are wired via data attributes so the component stays app-agnostic.

```elixir
defmodule StalwartUI.VideoUploadField do
  @moduledoc """
  Per-lesson video upload affordance: a file input wired to the `MuxUpload` JS
  hook, plus a status label. Plain assigns only — no resource/domain/route
  references (see COMPONENTS.md). The hook pushes `@on_request_upload` to the
  parent LiveView with `%{"lesson_id" => ...}` and expects a `%{upload_url}`
  reply, then streams the file straight to Mux.
  """
  use Phoenix.Component

  attr :lesson_id, :string, required: true
  attr :status, :atom, default: nil, doc: "nil | :pending_upload | :processing | :ready | :errored"
  attr :on_request_upload, :string, default: "request_upload"

  def video_upload_field(assigns) do
    ~H"""
    <div
      id={"upload-#{@lesson_id}"}
      phx-hook="MuxUpload"
      data-lesson-id={@lesson_id}
      data-event={@on_request_upload}
      class="flex items-center gap-2"
    >
      <span class="text-xs opacity-70">{status_label(@status)}</span>
      <label :if={@status in [nil, :errored]} class="btn btn-xs">
        Upload video
        <input type="file" accept="video/*" class="hidden" />
      </label>
    </div>
    """
  end

  defp status_label(nil), do: "No video"
  defp status_label(:pending_upload), do: "Uploading…"
  defp status_label(:processing), do: "Processing…"
  defp status_label(:ready), do: "Ready"
  defp status_label(:errored), do: "Upload failed"
end
```

- [ ] **Step 3: Render status + upload field in `CurriculumTree`**

`lib/stalwart_ui/curriculum_tree.ex`:

- Update the `sections` attr doc to: `"sorted list of %{id, title, lessons: [%{id, title, free_preview, video_status}]}"`.
- Add `import StalwartUI.VideoUploadField` at the top (after `use Phoenix.Component`).
- Add an `on_request_upload` passthrough attr: `attr :on_request_upload, :string, default: "request_upload"`.
- In the lesson `<li>`, after the `Preview` badge, render:

```heex
            <.video_upload_field
              lesson_id={lesson.id}
              status={lesson.video_status}
              on_request_upload={@on_request_upload}
            />
```

- [ ] **Step 4: Add the UpChunk JS hook + dependency**

Create `assets/package.json`:

```json
{
  "name": "matwork-assets",
  "private": true,
  "dependencies": {
    "@mux/upchunk": "^3.4.0"
  }
}
```

Run: `npm install --prefix assets`
Expected: creates `assets/node_modules/@mux/upchunk`. ⚠️ This is the project's first npm dependency; esbuild resolves `node_modules` relative to the entry file, so `assets/node_modules` is found automatically. Confirm with `mix assets.build` (no resolution error) after Step 5.

Create `assets/js/hooks/mux_upload.js`:

```javascript
import * as UpChunk from "@mux/upchunk"

// Streams the selected file straight to Mux. Asks the server (via the event
// named in data-event) for a one-time upload URL, then uploads the bytes
// directly — they never touch the Phoenix server. The server-side Video state
// is driven by Mux webhooks, not by this hook.
export const MuxUpload = {
  mounted() {
    const input = this.el.querySelector("input[type=file]")
    if (!input) return

    input.addEventListener("change", (e) => {
      const file = e.target.files && e.target.files[0]
      if (!file) return

      const event = this.el.dataset.event
      const lessonId = this.el.dataset.lessonId

      this.pushEvent(event, {lesson_id: lessonId}, (reply) => {
        if (!reply || !reply.upload_url) return

        const upload = UpChunk.createUpload({endpoint: reply.upload_url, file})
        upload.on("error", () => this.pushEvent("upload_failed", {lesson_id: lessonId}))
        upload.on("success", () => this.pushEvent("upload_finished", {lesson_id: lessonId}))
      })
    })
  },
}
```

`assets/js/app.js` — import and register the hook:

```javascript
import {hooks as colocatedHooks} from "phoenix-colocated/matwork"
import {MuxUpload} from "./hooks/mux_upload"
```

and change the LiveSocket hooks option to:

```javascript
  hooks: {...colocatedHooks, MuxUpload},
```

- [ ] **Step 5: Wire the builder LiveView**

`lib/matwork_web/live/course_builder_live.ex`:

1. Subscribe to the gym's video topic on connected mount. In `mount/3`, after resolving the manager branch and before/after `load_course_tree`, add a subscription (only when connected):

```elixir
  def mount(%{"id" => course_id}, _session, socket) do
    membership = socket.assigns.current_membership

    if GymLiveAuth.manager?(membership) do
      if connected?(socket) do
        Phoenix.PubSub.subscribe(Matwork.PubSub, "gym:#{socket.assigns.current_gym.id}:videos")
      end

      case Curriculum.load_course_tree(course_id, opts(socket)) do
        {:ok, course} ->
          {:ok, socket |> assign(:course_id, course_id) |> assign_course(course)}

        {:error, _not_found} ->
          {:ok,
           socket
           |> put_flash(:error, "Course not found.")
           |> push_navigate(to: ~p"/g/#{socket.assigns.current_gym.slug}/courses")}
      end
    else
      {:ok, assign(socket, manager?: false, course: nil, sections: [], raw_sections: [])}
    end
  end
```

2. Add the upload event handler (uses `{:reply, ...}` to hand the URL back to the hook). Add near the other lesson events:

```elixir
  def handle_event("request_upload", %{"lesson_id" => lesson_id}, socket) do
    case find_lesson(socket, lesson_id) do
      nil ->
        {:reply, %{error: "stale"}, stale_item(socket)}

      lesson ->
        case Matwork.Media.create_direct_upload(lesson.title, opts(socket)) do
          {:ok, {video, upload_url}} ->
            {:ok, _} = Curriculum.attach_lesson_video(lesson, video, opts(socket))
            {:reply, %{upload_url: upload_url}, load_course(socket)}

          {:error, _} ->
            {:reply, %{error: "could not start upload"},
             socket |> put_flash(:error, "Could not start upload.") |> load_course()}
        end
    end
  end

  def handle_event("upload_failed", _params, socket) do
    {:noreply, socket |> put_flash(:error, "Upload failed — try again.") |> load_course()}
  end

  def handle_event("upload_finished", _params, socket) do
    # Bytes are in Mux; the webhook drives the video to :ready. Just refresh.
    {:noreply, load_course(socket)}
  end
```

3. Add the PubSub handler:

```elixir
  def handle_info({:video_updated, _video_id}, socket) do
    {:noreply, load_course(socket)}
  end
```

4. In `assign_course/2`, include `video_status` in the projected lesson map:

```elixir
            Enum.map(section.lessons, fn lesson ->
              %{
                id: lesson.id,
                title: lesson.title,
                free_preview: lesson.free_preview,
                video_status: video_status(lesson.video)
              }
            end)
```

and add the helper:

```elixir
  defp video_status(%Matwork.Media.Video{status: status}), do: status
  defp video_status(_), do: nil
```

(`lesson.video` is `nil` when unattached, or an `Ash.NotLoaded` only if not loaded — `load_course_tree` loads it, so it is either `nil` or a `%Video{}`.)

- [ ] **Step 6: Write the component test**

Create `test/stalwart_ui/video_upload_field_test.exs`:

```elixir
defmodule StalwartUI.VideoUploadFieldTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import StalwartUI.VideoUploadField

  defp field(assigns), do: render_component(&video_upload_field/1, assigns)

  test "renders an upload control when there is no video" do
    html = field(%{lesson_id: "l1", status: nil})
    assert html =~ "No video"
    assert html =~ ~s(phx-hook="MuxUpload")
    assert html =~ ~s(data-lesson-id="l1")
    assert html =~ "type=\"file\""
  end

  test "shows processing status and hides the upload control while in-flight" do
    html = field(%{lesson_id: "l1", status: :processing})
    assert html =~ "Processing…"
    refute html =~ "type=\"file\""
  end

  test "shows ready status" do
    assert field(%{lesson_id: "l1", status: :ready}) =~ "Ready"
  end
end
```

- [ ] **Step 7: Write the builder upload LiveView test**

Create `test/matwork_web/live/course_builder_upload_test.exs`. The Mux call happens in the LiveView process, so use Mox in **global** mode with `async: false`.

```elixir
defmodule MatworkWeb.CourseBuilderUploadTest do
  use MatworkWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox
  import Matwork.Generator

  alias Matwork.Curriculum

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    owner = generate(user())
    gym = generate(gym(owner: owner))
    course = generate(course(gym: gym, title: "Half Guard"))
    section = generate(section(course: course))
    lesson = generate(lesson(section: section, title: "Old-school sweep"))
    %{owner: owner, gym: gym, course: course, lesson: lesson}
  end

  test "requesting an upload creates a Video, attaches it, and returns the URL",
       %{conn: conn, owner: owner, gym: gym, course: course, lesson: lesson} do
    stub(Matwork.Platform.MuxMock, :create_direct_upload, fn %{passthrough: passthrough} ->
      assert passthrough == gym.id
      {:ok, %{id: "upload_live", url: "https://storage.example/put"}}
    end)

    conn = sign_in(conn, owner)
    {:ok, lv, _html} = live(conn, ~p"/g/#{gym.slug}/courses/#{course.id}/edit")

    # Simulate the JS hook's pushEvent for the lesson's upload control.
    render_hook(element(lv, "#upload-#{lesson.id}"), "request_upload", %{
      "lesson_id" => lesson.id
    })

    {:ok, reloaded} =
      Curriculum.get_course(course.id, actor: owner, tenant: gym.id)

    lesson_row =
      Curriculum.list_lessons!(actor: owner, tenant: gym.id)
      |> Enum.find(&(&1.id == lesson.id))

    assert lesson_row.video_id
    assert reloaded.id == course.id
  end

  test "a webhook-driven video_updated broadcast refreshes the builder to Ready",
       %{conn: conn, owner: owner, gym: gym, course: course, lesson: lesson} do
    video = generate(video(gym: gym, status: :processing))
    {:ok, _} = Curriculum.attach_lesson_video(lesson, video, actor: owner, tenant: gym.id)

    conn = sign_in(conn, owner)
    {:ok, lv, _html} = live(conn, ~p"/g/#{gym.slug}/courses/#{course.id}/edit")

    # Mark ready as the system actor, then broadcast the same message the job sends.
    {:ok, _} =
      Matwork.Media.mark_video_ready(video, %{mux_playback_id: "pb"},
        actor: %Matwork.Platform.SystemActor{},
        tenant: gym.id
      )

    Phoenix.PubSub.broadcast(Matwork.PubSub, "gym:#{gym.id}:videos", {:video_updated, video.id})

    assert render(lv) =~ "Ready"
  end
end
```

- [ ] **Step 8: Update `COMPONENTS.md`**

Append a `VideoUploadField` entry and update the `CurriculumTree` assigns line to note the new `video_status` lesson key + `on_request_upload` passthrough:

```markdown
## VideoUploadField (`StalwartUI.VideoUploadField.video_upload_field/1`)

Per-lesson video upload affordance: a hidden file input wired to the `MuxUpload`
JS hook plus a status label. The hook pushes the `on_request_upload` event with
`%{"lesson_id" => ...}` and expects a `%{upload_url: ...}` reply, then streams
the file directly to Mux.

**Assigns:** `lesson_id` (required, string); `status` (atom, default `nil` —
one of `nil | :pending_upload | :processing | :ready | :errored`);
`on_request_upload` (string phx event name, default `"request_upload"`).

_CurriculumTree update:_ lesson maps now include `video_status` (the atoms
above), and `curriculum_tree/1` accepts an `on_request_upload` passthrough
(default `"request_upload"`) forwarded to each lesson's `VideoUploadField`.
```

- [ ] **Step 9: Run tests, build assets, format, lint, commit**

Run: `mix test test/stalwart_ui/video_upload_field_test.exs test/matwork_web/live/course_builder_upload_test.exs` and `mix assets.build` (no esbuild resolution error), then the **full suite** `mix test` (expect all green, including the Session 1 builder tests, which still pass because `video_status` is additive and the tree shape is backward-compatible for lessons without video).

```bash
mix format
mix credo --strict
git add lib/stalwart_ui/video_upload_field.ex lib/stalwart_ui/curriculum_tree.ex lib/matwork/curriculum.ex lib/matwork_web/live/course_builder_live.ex assets/ COMPONENTS.md test/stalwart_ui/video_upload_field_test.exs test/matwork_web/live/course_builder_upload_test.exs
git commit -m "Add video upload UI to course builder with live status"
```

---

## Self-Review

**Spec coverage** (against `docs/superpowers/specs/2026-07-16-milestone-1-curriculum-video-design.md` §5, §2.2, §2.3, §3.4, §7):

- §5.1 `Platform.Mux` behaviour (Req-backed) + Mox + env vars → Task 1. `sign_playback` correctly deferred to Session 3 (explicit note).
- §5.2 upload flow: (1) builder "Upload video" → `Media.create_direct_upload` → stores `mux_upload_id`, creates `Video`, relates to lesson → Tasks 3, 5, 6; (2) browser→Mux via UpChunk → Task 6 JS hook; (3) signature-verified, idempotent `WebhookEvent`, enqueue → Task 4 (never inline); (4) Oban job runs `mark_ready`/`mark_errored` as system actor → Task 4; (5) PubSub flips builder live → Tasks 4 + 6.
- §2.2 `Video` attributes → Task 3 (exact fields).
- §2.3 `WebhookEvent` global, unique `(provider, external_id)` → Task 2.
- §3.4 system actor bypass rather than `authorize?: false` → Task 2 (`SystemActor` + check), applied in Tasks 2–3.
- §7 component inventory: `VideoUploadField` added to `COMPONENTS.md` → Task 6. (`VideoPlayer`/`LockedLesson` remain Session 3.)
- Testing (§5.3): Mux via Mox (T1, T3), webhook idempotency (T2, T4), Oban job drives `mark_ready` (T4), bad-signature rejection (T2, T4). Plus policy allow/deny + tenant isolation on `Video` (T3) and lesson↔video attach (T5), matching Session 1's discipline.

**Placeholder scan:** none. Every step has concrete code/commands. The genuine external unknowns (Mux request/response, webhook payload paths, signature header, UpChunk API) are consolidated into one ⚠️ "verify against docs.mux.com" callout with the exact shapes the code assumes — the implementer verifies (a checkbox), they do not invent.

**Type/name consistency:**
- `Matwork.Platform.SystemActor` struct + `Matwork.Platform.Checks.SystemActor` check used identically in `WebhookEvent` (T2) and `Video` (T3) policies and in the worker/controller/tests.
- Media interfaces (`create_direct_upload/2`, `create_video`, `get_video`, `get_video_by_upload_id`, `mark_video_processing/ready/errored`) are defined in T3 and consumed with matching arity in T4's worker and T6's LiveView.
- `Platform.Mux.create_direct_upload/1` returns `{:ok, %{id, url}}` in the behaviour (T1), the HTTP impl (T1), every Mox stub (T1, T3, T6), and is destructured identically in `Media.create_direct_upload/2` (T3).
- Webhook `passthrough` = `gym_id` (tenant) is set in `Media.create_direct_upload` (T3) and read back in the worker (T4) — the single mechanism that resolves a tenant-scoped `Video` from a global webhook without a cross-tenant scan; consistent on both ends.
- PubSub topic `"gym:#{gym_id}:videos"` and message `{:video_updated, video_id}` match between the worker broadcast (T4) and the builder's `subscribe`/`handle_info` (T6).
- Builder event/param names (`request_upload` with `%{"lesson_id" => ...}`, `upload_failed`, `upload_finished`) match the JS hook's `pushEvent` calls (T6). Note these use `lesson_id` (hook-supplied), distinct from the existing tree forms' `_id` convention (documented in `COMPONENTS.md`) — no collision.

**Deviations from the design spec, flagged (per `CLAUDE.md` "if code and design disagree, say so"):**
1. **UUID primary keys**, not the spec's `bigserial` — continues the Session-1 decision; `Video`/`WebhookEvent` use `uuid_primary_key`.
2. **Tenant resolution via Mux `passthrough`.** The spec (§5.2) says the job "reads from `WebhookEvent` and invokes the action" but doesn't say how a *global* webhook locates a *tenant-scoped* `Video`. This plan sets `passthrough = gym_id` on the Mux upload and reads it back — the cleanest option that avoids a cross-tenant scan or a `global?` multitenancy relaxation. Called out here because it's a design decision the spec left open.
3. **`ActiveMember` reused for `Video` write/read gating** rather than a new `ManagesMedia` check — `Matwork.Gyms.Checks.ActiveMember` is already parameterized on `:roles`, so `{ActiveMember, roles: [:owner, :instructor]}` is the DRY choice over duplicating `ManagesCurriculum` into the Media namespace.
4. **First npm dependency** (`@mux/upchunk`) — the project previously vendored JS (`assets/vendor/`) with no `package.json`. Task 6 introduces `assets/package.json` + `npm install --prefix assets`; flagged as the one build-setup assumption to verify (`mix assets.build`).
```
