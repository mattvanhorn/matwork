defmodule StalwartUI.CurriculumTreeTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import StalwartUI.CurriculumTree

  defp tree(assigns) do
    render_component(&curriculum_tree/1, assigns)
  end

  test "renders sections and their lessons" do
    html =
      tree(%{
        sections: [
          %{
            id: "s1",
            title: "Sweeps",
            lessons: [%{id: "l1", title: "Old-school sweep", free_preview: true}]
          }
        ]
      })

    assert html =~ "Sweeps"
    assert html =~ "Old-school sweep"
  end

  test "marks free-preview lessons" do
    html =
      tree(%{
        sections: [
          %{id: "s1", title: "Sweeps", lessons: [%{id: "l1", title: "L", free_preview: true}]}
        ]
      })

    assert html =~ "Preview"
  end

  test "renders an empty-state when there are no sections" do
    assert tree(%{sections: []}) =~ "No sections yet"
  end
end
