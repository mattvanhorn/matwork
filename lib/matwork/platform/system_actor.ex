defmodule Matwork.Platform.SystemActor do
  @moduledoc """
  The actor used by webhook-driven Oban jobs, where there is no human actor.
  Policies authorize this struct explicitly (see `Platform.Checks.SystemActor`)
  so that webhook processing keeps authorization on the resource rather than
  reaching for `authorize?: false` (per CLAUDE.md §3.4 of the spec).
  """
  defstruct []
end
