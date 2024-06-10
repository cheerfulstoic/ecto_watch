defmodule EctoWatch.Options do
  alias EctoWatch.WatcherOptions

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
        type: {:custom, __MODULE__, :check_valid_watchers_list, []},
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

  def check_valid_watchers_list([]), do: {:error, "requires at least one watcher"}

  def check_valid_watchers_list(watchers) when is_list(watchers) do
    valid? =
      Enum.all?(watchers, fn
        {schema_mod, update_type} ->
          EctoWatch.Helpers.is_ecto_schema_mod?(schema_mod) && valid_update_type?(update_type)

        {schema_mod, update_type, _} ->
          EctoWatch.Helpers.is_ecto_schema_mod?(schema_mod) && valid_update_type?(update_type)

        _ ->
          false
      end)

    if valid? do
      {:ok, watchers}
    else
      {:error,
       ":watchers items should either be `{schema_mod, update_type}` or `{schema_mod, update_type, opts}`"}
    end
  end

  def check_valid_watchers_list(_), do: {:error, ":watchers options should be a list"}

  defp valid_update_type?(update_type) do
    update_type in [:inserted, :updated, :deleted]
  end
end
