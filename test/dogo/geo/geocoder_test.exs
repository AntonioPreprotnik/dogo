defmodule Dogo.Geo.GeocoderTest do
  use ExUnit.Case, async: true

  import Mox

  alias Dogo.Geo.Geocoder
  alias Dogo.GeocoderMock

  setup :verify_on_exit!

  test "prekratak upit ne ide na mrežu" do
    for query <- ["", " ", "a", "sp", "  sp  "] do
      assert {:ok, []} = Geocoder.search(query)
    end
  end

  test "upit od tri znaka ide dalje" do
    expect(GeocoderMock, :search, fn "spl" -> {:ok, []} end)

    assert {:ok, []} = Geocoder.search("spl")
  end

  test "upit se očisti od razmaka prije slanja" do
    expect(GeocoderMock, :search, fn "Split" -> {:ok, []} end)

    assert {:ok, []} = Geocoder.search("  Split  ")
  end

  test "ono što nije string ne ruši pretragu" do
    assert {:ok, []} = Geocoder.search(nil)
  end
end
