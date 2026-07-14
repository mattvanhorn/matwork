defmodule MatworkWeb.PageController do
  use MatworkWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
