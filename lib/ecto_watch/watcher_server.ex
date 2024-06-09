defmodule EctoWatch.WatcherServer do
  use GenServer

  def start_link({repo_mod, pub_sub_mod, watcher_options}) do
    GenServer.start_link(__MODULE__, {repo_mod, pub_sub_mod, watcher_options},
      name: name(watcher_options)
    )
  end

  # DEPRECATED
  def name(watcher_options) do
    name(watcher_options.schema_mod, watcher_options.update_type)
  end

  def name(schema_mod, update_type) do
    :"ecto_watch_watcher_server_#{schema_mod}_#{update_type}"
  end

  def init({repo_mod, pub_sub_mod, watcher_options}) do
    table_name = watcher_options.schema_mod.__schema__(:source)

    channel_name = "ecto_watch_#{table_name}_#{watcher_options.update_type}"

    function_name = "ecto_watch_#{table_name}_notify_#{watcher_options.update_type}"

    update_keyword =
      case watcher_options.update_type do
        :inserted -> "INSERT"
        :updated -> "UPDATE"
        :deleted -> "DELETE"
      end

    Ecto.Adapters.SQL.query!(
      repo_mod,
      """
      CREATE OR REPLACE FUNCTION #{function_name}()
        RETURNS trigger AS $trigger$
        DECLARE
          payload TEXT;
        BEGIN
          payload := jsonb_build_object('type','#{watcher_options.update_type}','id',COALESCE(OLD.id, NEW.id));
          PERFORM pg_notify('#{channel_name}', payload);

          RETURN NEW;
        END;
        $trigger$ LANGUAGE plpgsql;
      """,
      []
    )

    Ecto.Adapters.SQL.query!(
      repo_mod,
      """
      CREATE OR REPLACE TRIGGER ecto_watch_#{table_name}_#{watcher_options.update_type}_trigger
        AFTER #{update_keyword} ON #{table_name} FOR EACH ROW
        EXECUTE PROCEDURE #{function_name}();
      """,
      []
    )

    notifications_pid = Process.whereis(:ecto_watch_postgrex_notifications)
    {:ok, _notifications_ref} = Postgrex.Notifications.listen(notifications_pid, channel_name)

    {:ok,
     %{
       pub_sub_mod: pub_sub_mod,
       channel_name: channel_name,
       schema_mod: watcher_options.schema_mod
     }}
  end

  def handle_info({:notification, _pid, _ref, channel_name, payload}, state) do
    if channel_name != state.channel_name do
      raise "Expected to receive message from #{state.channel_name}, but received from #{channel_name}"
    end

    schema_mod = state.schema_mod

    %{"type" => type, "id" => id} = Jason.decode!(payload)

    case type do
      "inserted" ->
        Phoenix.PubSub.broadcast(
          state.pub_sub_mod,
          pub_sub_channel(schema_mod, :inserted),
          {:inserted, schema_mod, id}
        )

      "updated" ->
        Phoenix.PubSub.broadcast(
          state.pub_sub_mod,
          pub_sub_channel(schema_mod, :updated),
          {:updated, schema_mod, id}
        )

        Phoenix.PubSub.broadcast(
          state.pub_sub_mod,
          pub_sub_channel(schema_mod, :updated, id),
          {:updated, schema_mod, id}
        )

      "deleted" ->
        Phoenix.PubSub.broadcast(
          state.pub_sub_mod,
          pub_sub_channel(schema_mod, :deleted),
          {:deleted, schema_mod, id}
        )

        Phoenix.PubSub.broadcast(
          state.pub_sub_mod,
          pub_sub_channel(schema_mod, :deleted, id),
          {:deleted, schema_mod, id}
        )
    end

    {:noreply, state}
  end

  def pub_sub_channel(schema_mod, update_type, id \\ nil) do
    if id do
      "ecto_watch:#{schema_mod.__schema__(:source)}:#{update_type}:#{id}"
    else
      "ecto_watch:#{schema_mod.__schema__(:source)}:#{update_type}"
    end
  end
end
