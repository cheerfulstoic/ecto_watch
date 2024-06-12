defmodule EctoWatch.MixProject do
  use Mix.Project

  def project do
    [
      app: :ecto_watch,
      version: "0.4.0",
      elixir: "~> 1.10",
      description:
        "EctoWatch allows you to easily get Phoenix.PubSub notifications directly from postgresql.",
      licenses: ["MIT"],
      package: package(),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  defp package do
    [
      maintainers: ["Brian Underwood"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/cheerfulstoic/ecto_watch"}
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
      {:nimble_options, "~> 1.1"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_pubsub, ">= 1.0.0"},
      {:jason, ">= 1.0.0"},
      {:ecto_sql, ">= 3.0.0"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:mix_test_watch, "~> 1.0", only: [:dev, :test]}
    ]
  end
end
