defmodule EctoWatch.WatcherSupervisor do
  @moduledoc """
  Internal Supervisor for postgres notification watchers (`EctoWatch.WatcherServer`)

  Used internally, but you'll see it in your application supervision tree.
  """

  alias EctoWatch.WatcherServer

  use Supervisor

  def start_link(options) do
    Supervisor.start_link(__MODULE__, options, name: __MODULE__)
  end

  def init(options) do
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

  def watcher_details do
    case Process.whereis(__MODULE__) do
      nil ->
        {:error, "WatcherSupervisor is not running!"}

      pid ->
        {:ok,
         Supervisor.which_children(pid)
         |> Enum.map(fn {_, pid, :worker, [EctoWatch.WatcherServer]} ->
           WatcherServer.details(pid)
         end)}
    end
  end
end
