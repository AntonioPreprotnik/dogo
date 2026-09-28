defmodule DogoWeb.LocaleTest do
  @moduledoc """
  E6-S1: jezik se bira iz cookieja, pa iz Accept-Language, pa zadani.
  """
  use DogoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias DogoWeb.Locale

  defp with_language(conn, header), do: put_req_header(conn, "accept-language", header)

  describe "accept_language/1" do
    test "poredak po kvaliteti", %{conn: conn} do
      conn = with_language(conn, "de-AT,de;q=0.9,en;q=0.8")

      assert Locale.accept_language(conn) == ["de", "de", "en"]
    end

    test "regionalna varijanta se svodi na jezik", %{conn: conn} do
      assert Locale.accept_language(with_language(conn, "en-GB")) == ["en"]
    end

    test "bez zaglavlja nema kandidata", %{conn: conn} do
      assert Locale.accept_language(conn) == []
    end

    test "smeće u zaglavlju ne ruši parsiranje", %{conn: conn} do
      assert is_list(Locale.accept_language(with_language(conn, ";;;q=,,")))
    end
  end

  describe "pick/1" do
    test "prvi podržani jezik pobjeđuje" do
      assert Locale.pick(["xx", "de", "en"]) == "de"
    end

    test "bez podržanog jezika vraća zadani" do
      assert Locale.pick(["xx", nil]) == Locale.default()
      assert Locale.pick([]) == "hr"
    end
  end

  describe "odabir jezika za zahtjev" do
    test "zadani jezik je hrvatski", %{conn: conn} do
      assert conn |> get(~p"/") |> html_response(200) =~ "Plaže za pse"
    end

    test "Accept-Language bira njemački", %{conn: conn} do
      html = conn |> with_language("de-AT,de;q=0.9") |> get(~p"/") |> html_response(200)

      assert html =~ "Hundefreundliche Strände"
      refute html =~ "Plaže za pse"
      # Jezik dokumenta prati izbor, zbog citaca ekrana i trazilica.
      assert html =~ ~s(<html lang="de">)
    end

    test "Accept-Language bira engleski", %{conn: conn} do
      html = conn |> with_language("en-US,en;q=0.9") |> get(~p"/") |> html_response(200)

      assert html =~ "Dog-friendly beaches"
    end

    test "nepodržani jezik pada na hrvatski", %{conn: conn} do
      html = conn |> with_language("fr-FR,fr") |> get(~p"/") |> html_response(200)

      assert html =~ "Plaže za pse"
    end

    test "cookie je jači od Accept-Language", %{conn: conn} do
      html =
        conn
        |> with_language("de-AT,de;q=0.9")
        |> put_req_cookie(Locale.cookie(), "en")
        |> get(~p"/")
        |> html_response(200)

      assert html =~ "Dog-friendly beaches"
      refute html =~ "Hundefreundliche"
    end

    test "neispravan cookie se ignorira", %{conn: conn} do
      html =
        conn
        |> put_req_cookie(Locale.cookie(), "klingonski")
        |> with_language("de")
        |> get(~p"/")
        |> html_response(200)

      assert html =~ "Hundefreundliche Strände"
    end
  end

  describe "ručna promjena jezika" do
    test "sprema izbor u cookie i vraća na istu stranicu", %{conn: conn} do
      conn = post(conn, ~p"/locale", %{"locale" => "de", "return_to" => "/beaches/1"})

      assert redirected_to(conn) == "/beaches/1"
      assert conn.resp_cookies[Locale.cookie()].value == "de"
      assert conn.resp_cookies[Locale.cookie()].max_age > 0
    end

    test "nepodržani jezik ne mijenja cookie", %{conn: conn} do
      conn = post(conn, ~p"/locale", %{"locale" => "klingonski"})

      assert conn.resp_cookies[Locale.cookie()] == nil
    end

    test "vanjski return_to se odbija", %{conn: conn} do
      for target <- ["https://zlo.example/", "//zlo.example/", "javascript:alert(1)"] do
        conn = post(build_conn(), ~p"/locale", %{"locale" => "en", "return_to" => target})

        assert redirected_to(conn) == "/"
      end

      assert conn
    end

    test "izbor vrijedi i na sljedećem zahtjevu", %{conn: conn} do
      conn = post(conn, ~p"/locale", %{"locale" => "de"})

      html =
        build_conn()
        |> put_req_cookie(Locale.cookie(), conn.resp_cookies[Locale.cookie()].value)
        |> get(~p"/")
        |> html_response(200)

      assert html =~ "Hundefreundliche Strände"
    end
  end

  describe "LiveView" do
    test "preuzima jezik iz sesije, ne pada na zadani", %{conn: conn} do
      {:ok, _view, html} =
        conn
        |> with_language("de")
        |> get(~p"/")
        |> live()

      assert html =~ "Hundefreundliche Strände"
    end

    test "prebacivač nudi sve jezike i označava trenutni", %{conn: conn} do
      {:ok, view, _html} = conn |> with_language("de") |> get(~p"/") |> live()

      for locale <- ~w(hr en de) do
        assert has_element?(view, ~s([data-role="locale-option"][data-locale="#{locale}"]))
      end

      assert has_element?(view, ~s([data-locale="de"][aria-current="true"]))
      refute has_element?(view, ~s([data-locale="hr"][aria-current="true"]))
    end

    test "prebacivač vraća na trenutnu stranicu", %{conn: conn} do
      beach = Dogo.BeachesFixtures.beach_fixture(%{})

      {:ok, view, _html} = live(conn, ~p"/beaches/#{beach.id}")

      assert view
             |> element(~s(form[action="/locale"] input[name="return_to"]))
             |> render() =~ ~s(value="/beaches/#{beach.id}")
    end
  end
end
