defmodule Dogo.Beaches.ClusterTest do
  @moduledoc "E3-S3: sažetak plaža po mreži, da brojevi u klasterima budu točni."
  use Dogo.DataCase, async: true

  import Dogo.BeachesFixtures

  alias Dogo.Beaches

  @bbox {16.0, 43.0, 17.0, 43.6}

  defp beaches_at(base_lon, base_lat, count, overrides \\ %{}) do
    for i <- 1..count do
      attrs =
        Map.merge(
          %{
            osm_id: "way/#{base_lon}-#{base_lat}-#{i}",
            geom: point(base_lon + i / 100_000, base_lat + i / 100_000)
          },
          overrides
        )

      beach_fixture(attrs)
    end
  end

  test "grupira bliske plaže u jednu ćeliju" do
    beaches_at(16.44, 43.50, 5)

    assert [%{count: 5}] = Beaches.cluster_in_bbox(@bbox)
  end

  test "udaljene plaže završe u različitim ćelijama" do
    beaches_at(16.10, 43.10, 3)
    beaches_at(16.90, 43.50, 2)

    clusters = Beaches.cluster_in_bbox(@bbox)

    assert length(clusters) == 2
    assert clusters |> Enum.map(& &1.count) |> Enum.sort() == [2, 3]
  end

  test "zbroj svih ćelija je stvaran broj plaža, ne odrezan" do
    beaches_at(16.10, 43.10, 7)
    beaches_at(16.50, 43.30, 11)
    beaches_at(16.90, 43.50, 4)

    total = Beaches.cluster_in_bbox(@bbox) |> Enum.map(& &1.count) |> Enum.sum()

    assert total == 22
  end

  test "ćelija nosi težište svojih plaža" do
    beaches_at(16.44, 43.50, 4)

    assert [%{lon: lon, lat: lat}] = Beaches.cluster_in_bbox(@bbox)

    assert_in_delta lon, 16.44, 0.01
    assert_in_delta lat, 43.50, 0.01
  end

  test "gušća mreža razdvaja ono što rjeđa spoji" do
    beaches_at(16.40, 43.50, 2)
    beaches_at(16.46, 43.50, 2)

    assert [%{count: 4}] = Beaches.cluster_in_bbox(@bbox, columns: 5)
    assert length(Beaches.cluster_in_bbox(@bbox, columns: 200)) == 2
  end

  test "plaže izvan pravokutnika se ne broje" do
    beaches_at(16.44, 43.50, 3)
    beaches_at(18.09, 42.65, 5)

    assert [%{count: 3}] = Beaches.cluster_in_bbox(@bbox)
  end

  test "filteri vrijede i za sažetak" do
    beaches_at(16.44, 43.50, 3, %{dog_status: :designated})
    beaches_at(16.45, 43.50, 4, %{dog_status: :not_allowed})

    assert [%{count: 3}] = Beaches.cluster_in_bbox(@bbox, dog_status: [:designated])
  end

  test "prazan pravokutnik daje prazan sažetak" do
    assert Beaches.cluster_in_bbox(@bbox) == []
  end

  describe "veličina ćelije" do
    test "izvodi se iz širine karte u pikselima" do
      beaches_at(16.21, 43.30, 2)
      beaches_at(16.29, 43.30, 2)

      # Uska karta: krupnije ćelije, obje skupine završe u istoj.
      assert [%{count: 4}] = Beaches.cluster_in_bbox(@bbox, width_px: 320)

      # Široka karta: sitnije ćelije, skupine se razdvajaju.
      assert length(Beaches.cluster_in_bbox(@bbox, width_px: 2560)) == 2
    end

    test "eksplicitni columns ima prednost pred pikselima" do
      beaches_at(16.21, 43.30, 2)
      beaches_at(16.29, 43.30, 2)

      assert [%{count: 4}] = Beaches.cluster_in_bbox(@bbox, width_px: 2560, columns: 5)
    end

    test "besmislena širina pada natrag na zadano" do
      beaches_at(16.44, 43.50, 3)

      for width <- [nil, 0, -100, "sirok"] do
        assert [%{count: 3}] = Beaches.cluster_in_bbox(@bbox, width_px: width)
      end
    end
  end
end
