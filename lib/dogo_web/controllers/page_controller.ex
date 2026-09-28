defmodule DogoWeb.PageController do
  use DogoWeb, :controller

  alias Dogo.Beaches

  def home(conn, _params) do
    render(conn, :home, beach_count: Beaches.count_beaches())
  end
end
