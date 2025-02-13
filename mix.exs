defmodule EctoWatch.MixProject do
  use Mix.Project

  @source_url "https://github.com/cheerfulstoic/ecto_watch"

  def project do
    [
      app: :ecto_watch,
      version: "0.12.2",
      elixir: "~> 1.10",
      description:
        "EctoWatch allows you to easily get Phoenix.PubSub notifications directly from postgresql.",
      licenses: ["MIT"],
      package: package(),
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      # Docs
      name: "EctoWatch",
      docs: docs()
    ]
  end

  defp package do
    [
      maintainers: ["Brian Underwood"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        Changelog: "#{@source_url}/blob/main/CHANGELOG.md"
      }
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
      {:mix_test_watch, "~> 1.0", only: [:dev, :test]},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp docs do
    [
      extra_section: "GUIDES",
      source_url: @source_url,
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"],
      extras: extras(),
      # ,
      groups_for_extras: groups_for_extras()
      # main: "Getting Started",
      # api_reference: false
    ]
  end

  def extras() do
    [
      "guides/introduction/Getting Started.md",
      "guides/introduction/Tracking columns and using labels.md",
      "guides/introduction/Getting additional values.md",
      "guides/introduction/Watching without a schema.md",
      "guides/introduction/Unsubscribing.md",
      "guides/introduction/Trigger Length Errors.md",
      "guides/introduction/Debugging.md",
      "guides/introduction/Notes.md",
      "guides/howtos/Upgrading Versions.md",
      "guides/other/Potental TODOs.md",
      "CHANGELOG.md"
    ]
  end

  defp groups_for_extras do
    [
      Introduction: ~r/guides\/introduction\/.?/,
      # Cheatsheets: ~r/cheatsheets\/.?/,
      "How-To's": ~r/guides\/howtos\/.?/,
      Other: ~r/guides\/other\/.?/
    ]
  end
end
