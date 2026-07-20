defmodule Matwork.Platform.Checks.SystemActor do
  @moduledoc "Policy check: is the actor the `%Matwork.Platform.SystemActor{}`?"
  use Ash.Policy.SimpleCheck

  def describe(_opts), do: "actor is the system actor"

  def match?(%Matwork.Platform.SystemActor{}, _context, _opts), do: true
  def match?(_actor, _context, _opts), do: false
end
