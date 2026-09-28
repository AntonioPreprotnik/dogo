# Credo configuration. Run with `mix credo --strict`.
#
# The default check set is used as-is; only the analysed paths are narrowed.
%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/", "bench/", "config/"],
        excluded: [~r"/_build/", ~r"/deps/"]
      },
      strict: true,
      checks: %{
        disabled: [
          # Phoenix generators use TODO-free but alias-heavy modules; nothing to
          # disable yet. Kept as a documented extension point.
        ]
      }
    }
  ]
}
