defmodule EctoWatch.MixProject do
  use Mix.Project

  def project do
    [
      app: :ecto_watch,
      version: "0.1.0",
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:postgrex, ">= 0.0.0"},
      {:phoenix_pubsub, ">= 1.0.0"},
      {:jason, ">= 1.0.0"},
      {:ecto_sql, ">= 3.0.0"},
      {:mix_test_watch, "~> 1.0", only: [:dev, :test]}
    ]
  end
end
