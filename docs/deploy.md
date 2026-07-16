# Deploying to Fly.io

This app's Docker image and `fly.toml` are scaffolded (`Dockerfile`,
`.dockerignore`, `rel/overlays/`, `lib/matwork/release.ex`, `fly.toml`) but
launching and deploying requires your own Fly.io account and CLI
authentication, so it isn't automated. Steps to run yourself:

## First-time setup

1. Install the Fly CLI if you haven't: `curl -L https://fly.io/install.sh | sh`
2. `fly auth login`
3. From the project root: `fly launch --no-deploy` — this will detect the
   existing `fly.toml` and Dockerfile, ask to confirm/adjust the app name
   and region, and create the Fly app without deploying yet. Update the
   `app` key in `fly.toml` if Fly assigns a different name than the
   placeholder `"matwork"`.
4. Provision Postgres: `fly postgres create` (or attach an existing Fly
   Postgres cluster with `fly postgres attach`).
5. Set secrets (the app raises on boot without these — see
   `config/runtime.exs`):
   ```
   fly secrets set SECRET_KEY_BASE=$(mix phx.gen.secret)
   fly secrets set TOKEN_SIGNING_SECRET=$(mix phx.gen.secret)
   ```
   Mailer secrets (Resend/Postmark API key) once a production Swoosh
   adapter is configured — not yet needed for this milestone, since
   `config/prod.exs` still needs that adapter wired in before it matters
   in production. Local dev keeps using `Swoosh.Adapters.Local`.

## Every deploy after that

```
fly deploy
```

`release_command` in `fly.toml` runs `/app/bin/migrate` automatically before
each deploy's new version goes live, so `mix ash.migrate`-generated
migrations ship on every deploy without a separate manual step.

## Verifying a deploy

```
fly status
fly logs
```

Visit `https://<app-name>.fly.dev` (or the custom `PHX_HOST` you configure)
to confirm the app boots and the `/` route responds.
