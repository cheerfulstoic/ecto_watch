defmodule EctoWatch.WatcherServer do
  alias EctoWatch.Helpers
  alias EctoWatch.WatcherOptions

  use GenServer

  def pub_sub_subscription_details(schema_mod_or_label, update_type, identifier) do
    name = unique_label(schema_mod_or_label, update_type)

    if Process.whereis(name) do
      {:ok,
       GenServer.call(
         name,
         {:pub_sub_subscription_details, schema_mod_or_label, update_type, identifier}
       )}
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
        {:pub_sub_subscription_details, schema_mod_or_label, update_type, identifier},
        _from,
        state
      ) do
    unique_label = unique_label(schema_mod_or_label, update_type)

    channel_name =
      if identifier do
        "#{unique_label}:#{identifier}"
      else
        "#{unique_label}"
      end

    {:reply, {state.pub_sub_mod, channel_name}, state}
  end

  def init({repo_mod, pub_sub_mod, watcher_options}) do
    schema_name =
      case watcher_options.schema_mod.__schema__(:prefix) do
        nil -> "public"
        prefix -> prefix
      end

    table_name = "#{watcher_options.schema_mod.__schema__(:source)}"
    unique_label = "#{unique_label(watcher_options)}"

    update_keyword =
      case watcher_options.update_type do
        :inserted ->
          "INSERT"

        :updated ->
          trigger_columns = watcher_options.opts[:trigger_columns]

          if trigger_columns do
            "UPDATE OF #{Enum.join(trigger_columns, ", ")}"
          else
            "UPDATE"
          end

        :deleted ->
          "DELETE"
      end

    extra_columns_sql =
      (watcher_options.opts[:extra_columns] || [])
      |> Enum.map_join(",", &"'#{&1}',row.#{&1}")

    # TODO: Raise an "unsupported" error if primary key is more than one column
    # Or maybe multiple columns could be supported?
    [primary_key] = watcher_options.schema_mod.__schema__(:primary_key)

    Ecto.Adapters.SQL.query!(
      repo_mod,
      """
      CREATE OR REPLACE FUNCTION \"#{schema_name}\".#{unique_label}_func()
        RETURNS trigger AS $trigger$
        DECLARE
          row record;
          payload TEXT;
        BEGIN
          row := COALESCE(NEW, OLD);
          payload := jsonb_build_object('type','#{watcher_options.update_type}','identifier',row.#{primary_key},'extra',json_build_object(#{extra_columns_sql}));
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
        AFTER #{update_keyword} ON \"#{schema_name}\".\"#{table_name}\" FOR EACH ROW
        EXECUTE PROCEDURE \"#{schema_name}\".#{unique_label}_func();
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

    %{"type" => type, "identifier" => identifier, "extra" => extra} = Jason.decode!(payload)

    extra = Map.new(extra, fn {k, v} -> {String.to_existing_atom(k), v} end)

    case type do
      "inserted" ->
        Phoenix.PubSub.broadcast(
          state.pub_sub_mod,
          state.unique_label,
          {:inserted, state.schema_mod_or_label, identifier, extra}
        )

      "updated" ->
        Phoenix.PubSub.broadcast(
          state.pub_sub_mod,
          "#{state.unique_label}:#{identifier}",
          {:updated, state.schema_mod_or_label, identifier, extra}
        )

        Phoenix.PubSub.broadcast(
          state.pub_sub_mod,
          state.unique_label,
          {:updated, state.schema_mod_or_label, identifier, extra}
        )

      "deleted" ->
        Phoenix.PubSub.broadcast(
          state.pub_sub_mod,
          "#{state.unique_label}:#{identifier}",
          {:deleted, state.schema_mod_or_label, identifier, extra}
        )

        Phoenix.PubSub.broadcast(
          state.pub_sub_mod,
          state.unique_label,
          {:deleted, state.schema_mod_or_label, identifier, extra}
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
