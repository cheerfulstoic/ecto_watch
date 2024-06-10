defmodule EctoWatch.WatcherServer do
  alias EctoWatch.Helpers
  alias EctoWatch.WatcherOptions

  use GenServer

  def pub_sub_subscription_details(schema_mod_or_label, update_type, id) do
    name = unique_label(schema_mod_or_label, update_type)

    if Process.whereis(name) do
      {:ok,
       GenServer.call(name, {:pub_sub_subscription_details, schema_mod_or_label, update_type, id})}
    else
      {:error, "No watcher found for #{inspect(schema_mod_or_label)} / #{inspect(update_type)}"}
    end
  end

  def start_link({repo_mod, pub_sub_mod, watcher_options}) do
    GenServer.start_link(__MODULE__, {repo_mod, pub_sub_mod, watcher_options},
      name: unique_label(watcher_options)
    )
  end

  def handle_call(
        {:pub_sub_subscription_details, schema_mod_or_label, update_type, id},
        _from,
        state
      ) do
    unique_label = unique_label(schema_mod_or_label, update_type)

    channel_name =
      if id do
        "#{unique_label}:#{id}"
      else
        "#{unique_label}"
      end

    {:reply, {state.pub_sub_mod, channel_name}, state}
  end

  def init({repo_mod, pub_sub_mod, watcher_options}) do
    table_name = watcher_options.schema_mod.__schema__(:source)

    unique_label = "#{unique_label(watcher_options)}"

    update_keyword =
      case watcher_options.update_type do
        :inserted ->
          "INSERT"

        :updated ->
          columns = watcher_options.opts[:columns]

          if columns do
            "UPDATE OF #{Enum.join(columns, ", ")}"
          else
            "UPDATE"
          end

        :deleted ->
          "DELETE"
      end

    Ecto.Adapters.SQL.query!(
      repo_mod,
      """
      CREATE OR REPLACE FUNCTION #{unique_label}_func()
        RETURNS trigger AS $trigger$
        DECLARE
          payload TEXT;
        BEGIN
          payload := jsonb_build_object('type','#{watcher_options.update_type}','id',COALESCE(OLD.id, NEW.id));
          PERFORM pg_notify('#{unique_label}', payload);

          RETURN NEW;
        END;
        $trigger$ LANGUAGE plpgsql;
      """,
      []
    )

    Ecto.Adapters.SQL.query!(
      repo_mod,
      """
      CREATE OR REPLACE TRIGGER #{unique_label}_trigger
        AFTER #{update_keyword} ON #{table_name} FOR EACH ROW
        EXECUTE PROCEDURE #{unique_label}_func();
      """,
      []
    )

    notifications_pid = Process.whereis(:ecto_watch_postgrex_notifications)
    {:ok, _notifications_ref} = Postgrex.Notifications.listen(notifications_pid, unique_label)

    {:ok,
     %{
       pub_sub_mod: pub_sub_mod,
       unique_label: unique_label,
       schema_mod: watcher_options.schema_mod,
       schema_mod_or_label: watcher_options.opts[:label] || watcher_options.schema_mod
     }}
  end

  def handle_info({:notification, _pid, _ref, channel_name, payload}, state) do
    if channel_name != state.unique_label do
      raise "Expected to receive message from #{state.unique_label}, but received from #{channel_name}"
    end

    %{"type" => type, "id" => id} = Jason.decode!(payload)

    case type do
      "inserted" ->
        Phoenix.PubSub.broadcast(
          state.pub_sub_mod,
          state.unique_label,
          {:inserted, state.schema_mod_or_label, id}
        )

      "updated" ->
        Phoenix.PubSub.broadcast(
          state.pub_sub_mod,
          "#{state.unique_label}:#{id}",
          {:updated, state.schema_mod_or_label, id}
        )

        Phoenix.PubSub.broadcast(
          state.pub_sub_mod,
          state.unique_label,
          {:updated, state.schema_mod_or_label, id}
        )

      "deleted" ->
        Phoenix.PubSub.broadcast(
          state.pub_sub_mod,
          "#{state.unique_label}:#{id}",
          {:deleted, state.schema_mod_or_label, id}
        )

        Phoenix.PubSub.broadcast(
          state.pub_sub_mod,
          state.unique_label,
          {:deleted, state.schema_mod_or_label, id}
        )
    end

    {:noreply, state}
  end

  def name(%WatcherOptions{} = watcher_options) do
    unique_label(watcher_options)
  end

  # To make things simple: generate a single string which is unique for each watcher
  # that can be used as the watcher process name, trigger name, trigger function name,
  # and Phoenix.PubSub channel name.
  def unique_label(%WatcherOptions{} = watcher_options) do
    unique_label(
      watcher_options.opts[:label] || watcher_options.schema_mod,
      watcher_options.update_type
    )
  end

  defp unique_label(schema_mod_or_label, update_type) do
    label = Helpers.label(schema_mod_or_label)

    :"ew_#{update_type}_for_#{label}"
  end
end
