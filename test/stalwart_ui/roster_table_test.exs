defmodule StalwartUI.RosterTableTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import StalwartUI.RosterTable

  test "renders a row per membership with a role badge" do
    memberships = [
      %{id: "m1", role: :owner, status: :active, user: %{email: "owner@example.com"}},
      %{id: "m2", role: :student, status: :active, user: %{email: "student@example.com"}}
    ]

    html = render_component(&roster_table/1, memberships: memberships)

    assert html =~ "owner@example.com"
    assert html =~ "student@example.com"
    assert html =~ "badge-primary"
    assert html =~ "badge-ghost"
  end

  test "renders an empty state with no memberships" do
    html = render_component(&roster_table/1, memberships: [])

    assert html =~ "No members yet."
  end

  test "renders with fallback badge for unrecognized role" do
    memberships = [
      %{id: "m1", role: :unknown, status: :active, user: %{email: "unknown@example.com"}}
    ]

    html = render_component(&roster_table/1, memberships: memberships)

    assert html =~ "unknown@example.com"
    assert html =~ "badge"
    refute html =~ "badge-primary"
    refute html =~ "badge-secondary"
    refute html =~ "badge-ghost"
  end
end
