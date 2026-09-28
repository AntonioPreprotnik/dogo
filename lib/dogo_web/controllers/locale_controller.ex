defmodule DogoWeb.LocaleController do
  @moduledoc """
  Ručna promjena jezika.

  Ide kroz običan zahtjev, ne kroz LiveView: cookie se može postaviti samo u
  HTTP odgovoru, a i jezik mijenja cijelu stranicu.
  """
  use DogoWeb, :controller

  alias DogoWeb.Locale

  def update(conn, %{"locale" => locale} = params) do
    conn
    |> Locale.put_cookie(locale)
    |> redirect(to: safe_return_to(params["return_to"]))
  end

  # Samo relativne putanje unutar aplikacije; inace bi parametar bio otvoreni
  # redirect na tudi poslužitelj.
  defp safe_return_to("/" <> _rest = path) do
    if String.starts_with?(path, "//"), do: ~p"/", else: path
  end

  defp safe_return_to(_other), do: ~p"/"
end
