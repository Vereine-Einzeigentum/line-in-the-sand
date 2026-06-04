defmodule LineWebWeb.PageController do
  use LineWebWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
