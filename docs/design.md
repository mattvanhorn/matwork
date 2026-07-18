# BJJ Instructor Platform — POC Design Document

Prepared for: Matt Van Horn / Stalwart Studios
Working codename: `matwork` (placeholder — trivially renameable at scaffold time)
Scope: the agreed POC slice — video curriculum library behind a Stripe Connect paywall, with a basic member roster. Web-first Phoenix LiveView on the Ash Framework.
Revision note: v2 — adopts Ash Framework fully (declarative resources/domains, AshAuthentication, attribute multitenancy, policy-based authorization), replacing the vanilla-Phoenix-contexts design of v1.

---

## 1. Goals and non-goals

The POC exists to prove one loop end to end: an instructor uploads video curriculum, a student pays for access, the student watches gated content, the instructor receives the money, and the platform takes an application fee. Everything in this document serves that loop.

It also serves two secondary purposes: it's a concrete demo for your continuing discovery conversations with gym owners, and it's the first production pressure-test of the UI components you eventually want to extract into a monetizable library — so components are namespaced and kept app-agnostic from day one.

Explicit non-goals for this slice: class scheduling, attendance, belt/stripe tracking, seminars, merch/e-commerce, native mobile apps, multi-instructor permission hierarchies, and marketing/CRM features. All are plausible later; none are needed to prove the thesis. The resource model below leaves clean seams for them but implements none of them.

## 2. Stack summary

Elixir 1.18+/OTP 27, Phoenix 1.8 with LiveView, **Ash 3.x** with `ash_postgres` (PostgreSQL 16), `ash_authentication` + `ash_authentication_phoenix` (magic-link strategy), `ash_oban`/Oban for background jobs, Tailwind CSS (Phoenix 1.8 default toolchain), Stripe Connect (Express accounts) for payments, Mux for video (direct uploads, transcoding, signed playback), Fly.io for hosting with Fly Postgres (or Neon) alongside. Email via Resend or Postmark through Swoosh — magic-link auth makes reliable email delivery a launch requirement, not a nicety.

Single Phoenix application, no umbrella. Ash domains do the modularization work. Migrations are generated from resource definitions via `mix ash.codegen`, keeping schema and code from drifting.

Why Ash for this app specifically, recorded for posterity: (a) the framework *enforces* tenant isolation rather than relying on discipline — any operation on a tenant-scoped resource without a tenant set is an error, not a silent cross-tenant leak, which matters for a platform whose pitch is "your students and your revenue are yours"; (b) authorization lives as policies on resources rather than as functions someone must remember to call, so the content-gating rule in §6 is structurally unavoidable; (c) AshJsonApi/AshGraphql can later derive a full API from the same resource definitions, which nearly zeroes the cost of the "native client against an API" option when mobile stops being deferrable; (d) you've built with Ash before, so the learning-curve tax that would otherwise argue for vanilla Phoenix doesn't apply. The trade-off accepted: Stripe Connect and Mux integration work is plain Elixir regardless (Ash neither helps nor hurts there), and the codebase is legible to a smaller — but growing, and more specialized — pool of future collaborators. That specialization cuts both ways: Ash-capable consulting is a scarcer skill Stalwart can advertise.

## 3. Multi-tenancy model

Ash **attribute-strategy multitenancy**, single database. Every tenant-owned resource declares `multitenancy do strategy :attribute; attribute :gym_id end`; Ash then refuses any query or changeset on that resource without a tenant, and automatically scopes identities (uniqueness constraints) per tenant. Schema-per-tenant (Ash's context strategy) is rejected for operational cost at this stage; the attribute strategy is also the path Alembic and the Ash docs recommend starting from, graduating later only if isolation demands it.

Which resources are tenant-scoped vs. global is a deliberate split:

**Global resources** (no multitenancy block): `User`, `Token` (AshAuthentication's), `Gym` itself, and `WebhookEvent`. A user's identity is global — one account, one email — because people in BJJ train at multiple academies, instructors guest-teach, and an owner of one gym may be a student at another. Keeping `User` global also sidesteps the plug-ordering subtlety Ash documents (tenant must be set before authentication plugs when the user resource itself is multitenant) — ours isn't, so authentication is tenant-independent and simpler.

**Tenant-scoped resources** (attribute strategy on `gym_id`): `Membership`, `Invite`, `Course`, `CourseSection`, `Lesson`, `Video`, `Plan`, `Subscription`, `StripeCustomer`.

Tenant plumbing: gyms live under a path slug — `/g/:gym_slug/...` — for the POC. A plug (for controllers) and an `on_mount` hook (for LiveViews) resolve the slug to a `Gym`, call `Ash.PlugHelpers.set_tenant/2`, and assign `current_gym` and the actor's `Membership` (nil if none). Code interface calls from LiveViews pass `tenant: gym.id` and `actor: current_user`. Per-tenant identities give us useful uniqueness for free: e.g. `StripeCustomer` unique on `user_id` per gym without composite-index hand-wiring. Subdomains or custom domains (which gym owners will eventually want for branding) are a later swap of the resolution plug only; a `slug` column and a nullable, unused `custom_domain` column on `Gym` reserve the space.

## 4. Domains and resources

Six Ash domains, mapping one-to-one onto the bounded contexts of the v1 design. Resources shown in attribute shorthand; all get timestamps; ids are `uuid_primary_key` (this doc originally called for bigserial "for the POC," but every M0 and M1 resource shipped with UUIDs instead — see the §10 revisit note). Each domain exposes code interfaces (`define :publish_course, args: [...]` etc.) so LiveViews call named domain functions, not raw `Ash.read!/2` — that's the DDD seam that keeps the UI thin.

### Accounts domain

```
User (global)
  email            ci_string, unique (all tenants), required
  name             string
  confirmed_at     utc_datetime
  # AshAuthentication magic_link strategy, registration_enabled? true
  # Token resource as generated by ash_authentication
```

No password authentication at all — magic links only, for sign-up and sign-in alike (Ash's magic-link registration upserts by email, so a student clicking an invite and a returning user are one flow). AshAuthentication's require-interaction default (token consumed on button click, not on page fetch) is kept — it prevents email security scanners from burning links.

### Gyms domain (tenancy root + roster)

```
Gym (global)
  name             string, required
  slug             ci_string, unique, required
  custom_domain    ci_string, unique, nullable   # reserved, unused in POC
  owner_id         belongs_to User
  stripe_account_id        string, nullable      # Connect Express account
  stripe_onboarding_state  atom: none | started | complete
  application_fee_percent  decimal, default from platform config

Membership (tenant-scoped)
  user_id          belongs_to User
  role             atom: owner | instructor | student
  status           atom: active | invited | removed
  identity: unique user_id per tenant

Invite (tenant-scoped)
  email            ci_string
  role             atom (as above)
  token            string, unique
  accepted_at      utc_datetime, nullable
```

The roster in the POC is exactly this: memberships plus invites. An instructor invites students by email; accepting an invite runs a single Ash action that upserts the user and creates the membership. This is deliberately minimal and still demonstrates the platform's structural advantage — the gym's audience is *on* the platform, addressable, which is what Patreon/Uscreen/Shopify stacks never give an instructor.

### Curriculum domain (all tenant-scoped)

```
Course
  title            string, required
  description      text
  status           atom: draft | published | archived
  position         integer

CourseSection
  course_id        belongs_to Course
  title            string
  position         integer

Lesson
  section_id       belongs_to CourseSection
  title            string, required
  description      text
  video_id         belongs_to Video, nullable
  free_preview     boolean, default false
  position         integer
```

Course → sections → lessons is the shallowest hierarchy that matches how instructors actually think ("Half Guard: Fundamentals" → "Sweeps" → "Old-school sweep, far-side underhook"). `free_preview` lessons are watchable without payment — the standard conversion mechanic for content businesses, and cheap to include now. State transitions (`publish`, `archive`) are named Ash actions with policies, not generic updates.

### Media domain (tenant-scoped)

```
Video
  uploaded_by_id     belongs_to User
  mux_upload_id      string            # direct-upload handshake
  mux_asset_id       string, nullable  # set by webhook when ready
  mux_playback_id    string, nullable  # signed-playback ID
  status             atom: pending_upload | processing | ready | errored
  duration_seconds   integer, nullable
  title              string
```

Upload flow: LiveView asks the server for a Mux direct-upload URL, browser uploads straight to Mux (video bytes never touch your server), Mux webhooks (`video.asset.ready` etc.) land in a controller that verifies the signature, records the event, and enqueues an Oban job that runs the `Video`'s `mark_ready` action. Playback uses **signed playback IDs from the start** — retrofitting signing onto public playback IDs after launch means re-creating assets, so this is one of the few "do it properly in the POC" items. The server mints short-lived playback JWTs only through the policy-gated action in §6.

### Commerce domain (tenant-scoped)

```
Plan                               # what a gym sells; POC: one per gym
  stripe_product_id  string
  stripe_price_id    string
  name             string          # e.g. "Online Curriculum Access"
  amount_cents     integer
  interval         atom: month | year
  status           atom: active | archived

Subscription
  user_id                 belongs_to User
  plan_id                 belongs_to Plan
  stripe_subscription_id  string, unique (all tenants)
  status                  atom: incomplete | active | past_due | canceled
  current_period_end      utc_datetime

StripeCustomer
  user_id            belongs_to User
  stripe_customer_id string
  identity: unique user_id per tenant   # customers live on the CONNECTED account
```

The POC sells exactly one thing: a monthly (or yearly) subscription granting access to all of a gym's published courses. Per-course one-time purchases are a natural later addition (a `Purchase` resource, same shape minus the period), but one SKU keeps the Stripe surface small while still proving the money loop.

### Platform domain (operations, not tenant-facing)

```
WebhookEvent (global)
  provider         atom: stripe | mux
  external_id      string, unique per provider   # idempotency key
  payload          map (jsonb)
  processed_at     utc_datetime, nullable
```

Both Stripe and Mux webhooks are recorded first, processed by Oban jobs second, and idempotent by construction (unique identity on provider + event ID). This one resource eliminates the entire category of "we missed/double-processed a webhook" bugs and gives you a replay mechanism for free.

## 5. Stripe Connect design

Express connected accounts. The onboarding flow: gym owner clicks "Set up payments," server creates the Express account, stores `stripe_account_id`, and redirects into Stripe's hosted onboarding; a return webhook/refresh updates `stripe_onboarding_state`. You never touch KYC, tax forms, or payout schedules — Stripe's hosted flow owns all of it, which is exactly right for a solo platform operator.

Money flow: **destination charges**. Checkout Sessions are created on the platform account with `subscription_data.application_fee_percent` (or fixed amount) and `transfer_data.destination` pointing at the gym's connected account. Students' card statements show the gym's name; the gym gets its money on Stripe's payout schedule; the platform fee arrives in Stalwart's account automatically. This is the simplest Connect topology that matches "flat SaaS fee + percentage of instructor earnings," and it's also the pricing story that discovery conversations should pressure-test (the guide already asks the flat-vs-percentage question).

All Stripe (and Mux) API interaction lives behind thin behaviours (`Platform.Stripe`, `Platform.Mux`) — this is plain Elixir, deliberately outside Ash; Ash actions call these boundaries from within action logic or Oban jobs. Webhooks that matter for the POC: `checkout.session.completed`, `customer.subscription.updated`, `customer.subscription.deleted`, `invoice.payment_failed`, `account.updated` (Connect onboarding state). Each handler is an Oban job reading from `WebhookEvent` and invoking a named Ash action (`Commerce.sync_subscription_from_stripe`, etc.) with a system actor.

Subscription state is mirrored, never trusted: the local `Subscription.status` is a cache of Stripe's truth, updated only by webhook-driven actions. Authorization policies read the local row (fast), and a nightly Oban job reconciles against the Stripe API (safety net).

## 6. Authorization: policies on resources

Where v1 had a `can_watch?/2` function that every caller had to remember, v2 puts the rule where it can't be bypassed — as Ash policies on the `Lesson` resource's playback-token action (and its read action for the member-facing views):

The `request_playback_token` action on `Lesson` authorizes when any of: the lesson is `free_preview`; the actor's membership in the tenant gym has role `owner` or `instructor`; or the actor holds a `Subscription` in this tenant with status `active` — or `past_due` within a grace window (a knob worth having from day one, because "my card expired and I instantly lost access" is a churn accelerant). The grace-window and role checks are small custom `Ash.Policy.SimpleCheck` modules; the rest is standard policy expressions over relationships.

Because the Mux JWT is only ever minted inside this action, there is no code path to watchable video that skips the check. Every future revenue stream (per-course purchases, seminar recordings) extends these policies rather than scattering new checks. Instructor-side write actions (course CRUD, publishing, uploads) get the mirror-image policies: actor's membership role must be `owner` or `instructor` in the tenant.

## 7. UI component strategy (the future library)

All reusable UI lives under a dedicated namespace — `StalwartUI` — in its own directory tree (`lib/stalwart_ui/`), depending only on Phoenix.Component, Tailwind, and its own JS hooks. App-specific composition lives in the app's own components. The discipline that makes later extraction real: nothing in `StalwartUI` may reference an app resource, domain, or route helper. (Ash resources stay behind the LiveViews; components receive plain assigns.)

The POC will naturally produce first drafts of exactly the components that are rare in existing Phoenix libraries (Petal Components and friends sell primitives; almost nobody sells flows): a video player component wrapping Mux Player with a LiveView hook; a course/section/lesson curriculum tree with drag-to-reorder; a paywall/upgrade gate component; a Stripe Connect onboarding status card; an invite-members flow; roster table with role badges. Keep a running `COMPONENTS.md` inventory as you build — that file becomes the library's initial catalog and, later, marketing copy. A second, Ash-specific library opportunity may emerge here too (form components tuned to `AshPhoenix.Form`, policy-aware UI helpers) — note candidates as they appear but don't design for them yet.

## 8. Build sequence

Ordered so that every milestone ends with something demoable, and the riskiest integrations (Mux, Connect) are reached as early as possible after the foundation exists. Estimates assume your 20–30 hrs/week, AI-assisted, with your existing Ash experience — the estimate does *not* budget for learning Ash from scratch.

**Milestone 0 — Foundation (week 1).** `mix igniter.new` with Ash + AshPostgres + AshAuthentication (magic link), `Gym`/`Membership`/`Invite` resources, tenant-resolution plug + `on_mount` hook, `/g/:slug` routing, first policies (roster visibility), deploy pipeline to Fly from day one (deploying week 1 is much cheaper than deploying week 5). Demo: create a gym, invite a student by email, student signs in via magic link and sees the gym's empty home page.

**Milestone 1 — Curriculum + video (weeks 2–3).** Curriculum and Media resources with instructor-gated actions, Mux direct upload from the lesson form, webhook + Oban processing driving `Video` state actions, signed playback for instructors, free-preview lessons watchable by any roster member. Demo: instructor builds a real mini-course with actual technique footage and watches it play back.

**Milestone 2 — Money (weeks 3–5).** Connect Express onboarding for the gym, one `Plan`, Checkout with destination charges + application fee, webhook-driven subscription mirroring via system-actor actions, `request_playback_token` policies wired to Mux JWT minting, student-facing subscribe/upgrade flow, minimal billing status page. Demo: the full thesis loop with a real card in test mode — this is the demo you put in front of gym owners.

**Milestone 3 — Polish for design partners (week 6).** Instructor dashboard (subscriber count, MRR from local mirror, Stripe dashboard link for the rest), empty states, mobile-browser pass, error/edge handling on the payment flows, seed script that sets up a convincing demo gym. Demo: hand an account to your first friendly black belt and watch what confuses them.

Roughly six calendar weeks to a design-partner-ready POC. The honest risk concentration is Milestone 2 — Connect has the most unfamiliar moving parts, and it's the part Ash helps with least — which is why it's sequenced immediately after video rather than last.

## 9. Testing and environments

ExUnit throughout; resource/action tests against the DB (Ash's authorization testing helpers to assert policies both allow and *deny* correctly — test the deny paths, they're the product), LiveView tests for the critical flows (invite → join, subscribe → watch). Stripe and Mux both have first-class test modes — use them directly rather than mocking the world; the `Platform.Stripe`/`Platform.Mux` behaviours give Mox a stubbing point where live calls would slow the suite. `stripe listen` (the CLI) forwards webhooks to localhost during development. One shared staging app on Fly pointing at test-mode keys is enough; no separate staging infra.

## 10. Deferred decisions, recorded

Native mobile: deferred; PWA-quality responsive web for the POC — with the note that full Ash adoption keeps the AshJsonApi/AshGraphql door open, materially cheapening the "native client against an API" option versus v1's design. Subdomains/custom domains: schema space reserved, resolution-plug swap later. Per-course purchases, seminars, merch, curriculum/belt tracking, affiliate/association licensing: all post-POC, all compatible with this resource model (seminars and merch are new Commerce resources; belt tracking is a new domain keyed on memberships; association licensing is a relationship between gyms). UUID vs bigserial: this doc originally called for bigserial now, revisiting only if federation/import-export made enumeration a concern — but every M0 (`User`, `Gym`, `Membership`, `Invite`, `Token`) and M1 (`Course`, `CourseSection`, `Lesson`) resource shipped with `uuid_primary_key` instead, matching `ash_authentication`'s own UUID-keyed resources with zero friction in practice. Treat UUID as the settled convention; this entry stays only as a record of the reversed decision. Schema-based (context-strategy) tenancy: available as a documented Ash migration path if a future enterprise customer demands hard isolation; not now. AshStateMachine for subscription lifecycle: considered, skipped for POC (webhook-mirrored status atom is enough); revisit if local state transitions multiply.

---

*Next step after your review: scaffold Milestone 0 in the workspace, as a repo you can pull down and run locally.*
