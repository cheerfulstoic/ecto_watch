defmodule EctoWatch.WatcherSupervisor do
  alias EctoWatch.WatcherServer

  use Supervisor

  def start_link(options) do
    Supervisor.start_link(__MODULE__, options, name: __MODULE__)
  end

  def init(options) do
    postgrex_notifications_options =
      options.repo_mod.config()
      |> Keyword.put(:name, :ecto_watch_postgrex_notifications)

    children =
      Enum.map(options.watchers, fn watcher_options ->
        %{
          id: WatcherServer.name(watcher_options),
          start:
            {WatcherServer, :start_link,
             [{options.repo_mod, options.pub_sub_mod, watcher_options}]}
        }
      end)

    Supervisor.init(children, strategy: :one_for_one)
  end
end
