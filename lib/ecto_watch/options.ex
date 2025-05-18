defmodule EctoWatch.Options do
  @moduledoc false

  alias EctoWatch.Options.WatcherOptions

  defstruct [:repo_mod, :pub_sub_mod, :watchers, :debug?, :legacy_postgres_support?]

  def new(opts) do
    %__MODULE__{
      repo_mod: opts[:repo],
      pub_sub_mod: opts[:pub_sub],
      legacy_postgres_support?: opts[:legacy_postgres_support?],
      watchers:
        Enum.map(opts[:watchers], fn watcher_opts ->
          WatcherOptions.new(watcher_opts, opts[:debug?], opts[:legacy_postgres_support?])
        end)
    }
  end

  def validate(opts) do
    schema = [
      repo: [
        type: {:custom, __MODULE__, :check_valid_repo_module, []},
        required: true
      ],
      pub_sub: [
        type: {:custom, __MODULE__, :check_valid_pubsub_module, []},
        required: true
      ],
      watchers: [
        type: {:custom, WatcherOptions, :validate_list, []},
        required: true
      ],
      debug?: [
        type: :boolean,
        required: false,
        default: false
      ],
      legacy_postgres_support?: [
        type: :boolean,
        required: false,
        default: false,
        doc:
          "Set to true to use DROP/CREATE instead of CREATE OR REPLACE for trigger creation (only needed for PostgreSQL versions older than 13.3.4)"
      ]
    ]

    NimbleOptions.validate(opts, schema)
  end

  def check_valid_repo_module(repo_mod) when is_atom(repo_mod) do
    if repo_mod in Ecto.Repo.all_running() do
      {:ok, repo_mod}
    else
      {:error, "#{inspect(repo_mod)} was not a currently running ecto repo"}
    end
  end

  def check_valid_repo_module(repo), do: {:error, "#{inspect(repo)} was not an atom"}

  def check_valid_pubsub_module(pubsub_mod) when is_atom(pubsub_mod) do
    Phoenix.PubSub.node_name(pubsub_mod)

    {:ok, pubsub_mod}
  rescue
    _ -> {:error, "#{inspect(pubsub_mod)} was not a currently running Phoenix PubSub module"}
  end

  def check_valid_pubsub_module(repo), do: {:error, "#{inspect(repo)} was not an atom"}
end
