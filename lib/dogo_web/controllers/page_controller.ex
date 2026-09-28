defmodule DogoWeb.PageController do
  use DogoWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
