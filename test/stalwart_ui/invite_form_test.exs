defmodule StalwartUI.InviteFormTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import StalwartUI.InviteForm

  test "renders email and role inputs" do
    form = Phoenix.Component.to_form(%{"email" => "", "role" => "student"}, as: :form)

    html = render_component(&invite_form/1, form: form)

    assert html =~ ~s(type="email")
    assert html =~ "instructor"
    assert html =~ "student"
    assert html =~ "Send invite"
  end
end
