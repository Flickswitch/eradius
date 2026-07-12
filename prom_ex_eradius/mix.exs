defmodule PromExEradius.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/Flickswitch/eradius"

  def project do
    [
      app: :prom_ex_eradius,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      name: "PromExEradius",
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:prom_ex, "~> 1.9"},
      # prom_ex compiles Plug.Conn-backed modules; required to build the dep
      {:plug, "~> 1.14"},
      {:telemetry, "~> 1.0"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp description do
    """
    PromEx plugin that exposes eradius RADIUS metrics from telemetry events
    (`[:eradius, ...]`). Optional companion to the Erlang eradius library.
    """
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib mix.exs README.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"]
    ]
  end
end
