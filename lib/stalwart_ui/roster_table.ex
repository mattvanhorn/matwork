defmodule StalwartUI.RosterTable do
  @moduledoc """
  Renders a gym's roster as a table with role badges.

  Takes plain assigns only — no resource, domain, or route-helper
  references, per the StalwartUI extraction discipline (see COMPONENTS.md).
  """
  use Phoenix.Component

  attr :id, :string, default: "roster-table"

  attr :memberships, :list,
    required: true,
    doc: "list of maps/structs with :id, :role, :status, and a loaded :user with :email"

  def roster_table(assigns) do
    ~H"""
    <table id={@id} class="table">
      <thead>
        <tr>
          <th>Member</th>
          <th>Role</th>
          <th>Status</th>
        </tr>
      </thead>
      <tbody>
        <tr :for={membership <- @memberships} id={"#{@id}-row-#{membership.id}"}>
          <td>{to_string(membership.user.email)}</td>
          <td><span class={role_badge_class(membership.role)}>{membership.role}</span></td>
          <td>{membership.status}</td>
        </tr>
      </tbody>
    </table>
    <p :if={@memberships == []} class="text-sm opacity-70">No members yet.</p>
    """
  end

  defp role_badge_class(:owner), do: "badge badge-primary"
  defp role_badge_class(:instructor), do: "badge badge-secondary"
  defp role_badge_class(:student), do: "badge badge-ghost"
end
