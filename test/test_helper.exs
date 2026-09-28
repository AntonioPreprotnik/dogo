ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Dogo.Repo, :manual)

# Vanjski servisi su iza behaviourova i u testovima se mockiraju.
Mox.defmock(Dogo.OverpassMock, for: Dogo.Import.Overpass)
Mox.defmock(Dogo.GeocoderMock, for: Dogo.Geo.Geocoder)
