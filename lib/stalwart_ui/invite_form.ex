defmodule StalwartUI.InviteForm do
  @moduledoc """
  A form for inviting someone to a gym by email and role.

  Takes a `Phoenix.HTML.Form` and role options as plain assigns — no
  resource, domain, or route-helper references, per the StalwartUI
  extraction discipline (see COMPONENTS.md).
  """
  use Phoenix.Component

  attr :form, Phoenix.HTML.Form, required: true
  attr :roles, :list, default: [:instructor, :student]
  attr :id, :string, default: "invite-form"
  attr :on_change, :string, default: "validate"
  attr :on_submit, :string, default: "invite"

  def invite_form(assigns) do
    ~H"""
    <.form for={@form} id={@id} phx-change={@on_change} phx-submit={@on_submit}>
      <input
        type="email"
        name={@form[:email].name}
        id={@form[:email].id}
        value={@form[:email].value}
        placeholder="Email address"
        class="input"
      />
      <select name={@form[:role].name} id={@form[:role].id} class="select">
        <option
          :for={role <- @roles}
          value={role}
          selected={to_string(@form[:role].value) == to_string(role)}
        >
          {role}
        </option>
      </select>
      <button type="submit" class="btn btn-primary">Send invite</button>
    </.form>
    """
  end
end
