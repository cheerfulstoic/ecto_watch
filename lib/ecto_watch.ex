defmodule EctoWatch do
  @moduledoc false

  alias EctoWatch.WatcherServer

  use Supervisor

  def subscribe(schema_mod_or_label, update_type, id \\ nil) do
    if !Process.whereis(__MODULE__) do
      raise "EctoWatch is not running. Please start it by adding it to your supervision tree or using EctoWatch.start_link/1"
    end

    with :ok <- check_update_args(update_type, id),
         {:ok, {pub_sub_mod, channel_name}} <-
           WatcherServer.pub_sub_subscription_details(schema_mod_or_label, update_type, id) do
      Phoenix.PubSub.subscribe(pub_sub_mod, channel_name)
    else
      {:error, error} ->
        raise ArgumentError, error
    end
  end

  def check_update_args(update_type, id) do
    case {update_type, id} do
      {:inserted, _} ->
        :ok

      {:updated, _} ->
        :ok

      {:deleted, _} ->
        :ok

      {other, _} ->
        raise ArgumentError,
              "Unexpected update_type: #{inspect(other)}.  Expected :inserted, :updated, or :deleted"
    end
  end

  def start_link(opts) do
    case EctoWatch.Options.validate(opts) do
      {:ok, validated_opts} ->
        options = EctoWatch.Options.new(validated_opts)

        Supervisor.start_link(__MODULE__, options, name: __MODULE__)

      {:error, errors} ->
        raise ArgumentError, "Invalid options: #{Exception.message(errors)}"
    end
  end

  def init(options) do
    # TODO:
    # Allow passing in options specific to Postgrex.Notifications.start_link/1
    # https://hexdocs.pm/postgrex/Postgrex.Notifications.html#start_link/1

    postgrex_notifications_options =
      options.repo_mod.config()
      |> Keyword.put(:name, :ecto_watch_postgrex_notifications)

    children = [
      {Postgrex.Notifications, postgrex_notifications_options},
      {EctoWatch.WatcherSupervisor, options}
    ]

    # children = children ++
    #   Enum.map(options.watchers, fn watcher_options ->
    #     %{
    #       id: WatcherServer.name(watcher_options),
    #       start: {WatcherServer, :start_link, [{options.repo_mod, options.pub_sub_mod, watcher_options}]}
    #     }
    #   end)

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
