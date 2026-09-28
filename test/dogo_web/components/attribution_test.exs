defmodule DogoWeb.AttributionTest do
  @moduledoc """
  E1-S5: izvor podataka mora biti vidljiv svugdje, jer to traže i ODbL
  licenca OpenStreetMapa i pošteno predstavljanje generiranih atributa.
  """
  use DogoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias DogoWeb.BeachComponents

  describe "podnožje" do
    setup %{conn: conn} do
      %{html: conn |> get(~p"/") |> html_response(200)}
    end

    test "sadrži OSM atribuciju i link na licencu", %{html: html} do
      assert html =~ "© OpenStreetMap contributors"
      assert html =~ "https://www.openstreetmap.org/copyright"
      assert html =~ "ODbL"
    end

    test "sadrži disclaimer o demonstracijskim podacima", %{html: html} do
      assert html =~ "Podaci su demonstracijski"
      assert html =~ "djelomično su generirani"
    end
  end

  describe "oznaka izvora statusa za pse" do
    test "OSM izvor" do
      html = render_component(&BeachComponents.dog_status_source/1, source: :osm)

      assert html =~ "iz OSM-a"
      assert html =~ ~s(data-source="osm")
      assert html =~ "OpenStreetMapa"
    end

    test "generirani izvor je označen kao takav" do
      html = render_component(&BeachComponents.dog_status_source/1, source: :generated)

      assert html =~ "generirano"
      assert html =~ ~s(data-source="generated")
      assert html =~ "demonstracije"
    end
  end

  describe "oznaka statusa za pse" do
    test "svaki status ima svoj tekst i boju" do
      for {status, label} <- [
            designated: "Plaža za pse",
            allowed: "Psi dozvoljeni",
            not_allowed: "Psi nisu dozvoljeni",
            unknown: "Nepoznato"
          ] do
        assert render_component(&BeachComponents.dog_status/1, status: status) =~ label
      end
    end
  end
end
