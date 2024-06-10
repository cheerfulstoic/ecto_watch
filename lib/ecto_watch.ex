defmodule EctoWatch do
  alias EctoWatch.WatcherServer

  use Supervisor

  def subscribe(schema_mod, update_type, id \\ nil) do
    if !Process.whereis(__MODULE__) do
      raise "EctoWatch is not running.  Please start it by adding it to your supervision tree or using EctoWatch.start_link/1"
    end

    pubsub_mod = Agent.get(:pub_sub_mod_agent, fn pub_sub_mod -> pub_sub_mod end)

    case check_subscription_args(schema_mod, update_type, id) do
      {:error, error} ->
        raise ArgumentError, error

      :ok ->
        pub_sub_channel_name = WatcherServer.pub_sub_channel(schema_mod, update_type, id)

        Phoenix.PubSub.subscribe(pubsub_mod, pub_sub_channel_name)
    end
  end

  def check_subscription_args(schema_mod, :inserted, id) when not is_nil(id) do
    {:error, "Cannot subscribe to id for inserted records"}
  end

  def check_subscription_args(schema_mod, :inserted, _), do: :ok
  def check_subscription_args(schema_mod, :updated, _), do: :ok
  def check_subscription_args(schema_mod, :deleted, _), do: :ok

  def check_subscription_args(schema_mod, other, _) do
    {:error,
     "Unexpected subscription event: #{inspect(other)}.  Expected :inserted, :updated, or :deleted"}
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
      %{
        id: :pub_sub_mod_agent,
        start: {Agent, :start_link, [fn -> options.pub_sub_mod end, [name: :pub_sub_mod_agent]]}
      },
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
