defmodule DogoWeb.PWATest do
  @moduledoc "E6-S2: aplikacija se može instalirati na početni zaslon."
  use DogoWeb.ConnCase, async: true

  describe "manifest" do
    test "ima sve što preglednik traži za instalaciju", %{conn: conn} do
      conn = get(conn, ~p"/manifest.webmanifest")

      assert response_content_type(conn, :json) =~ "application/manifest+json"
      manifest = json_response(conn, 200)

      assert manifest["name"] == "Dogo — plaže za pse"
      assert manifest["short_name"] == "Dogo"
      assert manifest["start_url"] == "/"
      assert manifest["scope"] == "/"
      assert manifest["display"] == "standalone"
      assert manifest["theme_color"] == "#0c4a6e"
    end

    test "nudi ikone od 192 i 512 px te maskable varijantu", %{conn: conn} do
      icons = conn |> get(~p"/manifest.webmanifest") |> json_response(200) |> Map.fetch!("icons")

      sizes = Enum.map(icons, & &1["sizes"])
      assert "192x192" in sizes
      assert "512x512" in sizes

      assert Enum.any?(icons, &(&1["purpose"] == "maskable"))
      assert Enum.all?(icons, &(&1["type"] == "image/png"))
    end

    test "naziv i opis prate jezik", %{conn: conn} do
      german =
        conn
        |> put_req_header("accept-language", "de")
        |> get(~p"/manifest.webmanifest")
        |> json_response(200)

      assert german["name"] == "Dogo — hundefreundliche Strände"
      assert german["lang"] == "de"
      assert german["description"] =~ "Hund"
    end
  end

  describe "datoteke" do
    test "ikone se posluzuju", %{conn: conn} do
      for path <- ~w(/icons/icon-192.png /icons/icon-512.png /icons/icon-maskable-512.png) do
        conn = get(conn, path)

        assert conn.status == 200
        # PNG potpis: bajtovi koje preglednik provjerava.
        assert <<137, "PNG", 13, 10, 26, 10, _rest::binary>> = conn.resp_body
      end
    end

    test "service worker se posluzuje s korijena, pa pokriva cijelu aplikaciju", %{conn: conn} do
      conn = get(conn, "/sw.js")

      assert conn.status == 200
      # Chrome nudi instalaciju samo ako service worker ima fetch handler.
      assert conn.resp_body =~ "addEventListener(\"fetch\""
    end

    # E6-S3. Ponasanje service workera provjereno je rucno u pregledniku
    # (opis u commitu); ovdje se zakljucava ono sto se lako pokvari izmjenom.
    test "service worker cacheira app shell, ali ne websocket ni tuđe domene", %{conn: conn} do
      sw = conn |> get("/sw.js") |> Map.fetch!(:resp_body)

      assert sw =~ ~s|const SHELL_URL = "/"|
      assert sw =~ ~s|url.pathname.startsWith("/live")|
      assert sw =~ "url.origin !== self.location.origin"
      assert sw =~ ~s|request.method !== "GET"|
    end
  end

  describe "stranica" do
    test "upucuje na manifest, temu i ikonu", %{conn: conn} do
      html = conn |> get(~p"/") |> html_response(200)

      assert html =~ ~s(rel="manifest")
      assert html =~ ~s(<meta name="theme-color" content="#0c4a6e")
      assert html =~ ~s(rel="apple-touch-icon")
      assert html =~ ~s(name="viewport")
    end
  end
end
