defmodule EctoWatch.Options do
  @moduledoc false

  alias EctoWatch.Options.WatcherOptions

  defstruct [:repo_mod, :pub_sub_mod, :watchers]

  def new(opts) do
    %__MODULE__{
      repo_mod: opts[:repo],
      pub_sub_mod: opts[:pub_sub],
      watchers: Enum.map(opts[:watchers], &WatcherOptions.new/1)
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
