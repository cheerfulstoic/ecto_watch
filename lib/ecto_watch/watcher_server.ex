defmodule EctoWatch.WatcherServer do
  @moduledoc """
  GenServer for the individiual change watchers which are configured by end users
  """

  alias EctoWatch.Helpers
  alias EctoWatch.WatcherOptions

  use GenServer

  def pub_sub_subscription_details(schema_mod_or_label, update_type, identifier_value) do
    name = unique_label(schema_mod_or_label, update_type)

    if Process.whereis(name) do
      GenServer.call(
        name,
        {:pub_sub_subscription_details, schema_mod_or_label, update_type, identifier_value}
      )
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
        {:pub_sub_subscription_details, schema_mod_or_label, update_type, identifier_value},
        _from,
        state
      ) do
    unique_label = unique_label(schema_mod_or_label, update_type)

    [primary_key] = state.schema_mod.__schema__(:primary_key)

    {column, value} =
      case identifier_value do
        {key, value} ->
          {key, value}

        nil ->
          {nil, nil}

        identifier_value ->
          {primary_key, identifier_value}
      end

    result =
      cond do
        update_type == :inserted && column == primary_key ->
          {:error, "Cannot subscribe to primary_key for inserted records"}

        column && not MapSet.member?(state.identifier_keys, column) ->
          {:error, "Column #{column} is not an association column/"}

        column && column != primary_key && column not in state.extra_columns ->
          {:error, "Column #{column} is not in the list of extra columns"}

        true ->
          channel_name =
            if column && value do
              "#{unique_label}|#{column}|#{value}"
            else
              "#{unique_label}"
            end

          {:ok, {state.pub_sub_mod, channel_name}}
      end

    {:reply, result, state}
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

    # TODO: Raise an "unsupported" error if primary key is more than one column
    # Or maybe multiple columns could be supported?
    [primary_key] = watcher_options.schema_mod.__schema__(:primary_key)

    extra_columns = watcher_options.opts[:extra_columns] || []
    all_columns = [primary_key | extra_columns]

    columns_sql = Enum.map_join(all_columns, ",", &"'#{&1}',row.#{&1}")

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
          payload := jsonb_build_object('type','#{watcher_options.update_type}','values',json_build_object(#{columns_sql}));
          PERFORM pg_notify('#{unique_label}', payload);

          RETURN NEW;
        END;
        $trigger$ LANGUAGE plpgsql;
      """,
      []
    )

    # Can't use the "OR REPLACE" syntax before postgres v13.3.4, so using DROP TRIGGER IF EXISTS
    Ecto.Adapters.SQL.query!(
      repo_mod,
      """
      DROP TRIGGER IF EXISTS #{unique_label}_trigger on \"#{schema_name}\".\"#{table_name}\";
      """,
      []
    )

    Ecto.Adapters.SQL.query!(
      repo_mod,
      """
      CREATE TRIGGER #{unique_label}_trigger
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
       identifier_keys:
         MapSet.put(association_owner_keys(watcher_options.schema_mod), primary_key),
       extra_columns: watcher_options.opts[:extra_columns] || [],
       schema_mod_or_label: watcher_options.opts[:label] || watcher_options.schema_mod
     }}
  end

  defp association_owner_keys(schema_mod) do
    schema_mod.__schema__(:associations)
    |> Enum.map(&schema_mod.__schema__(:association, &1))
    |> Enum.map(& &1.owner_key)
    |> MapSet.new()
  end

  def handle_info({:notification, _pid, _ref, channel_name, payload}, state) do
    if channel_name != state.unique_label do
      raise "Expected to receive message from #{state.unique_label}, but received from #{channel_name}"
    end

    %{"type" => type, "values" => values} = Jason.decode!(payload)

    values = Map.new(values, fn {k, v} -> {String.to_existing_atom(k), v} end)

    type = String.to_existing_atom(type)

    message = {type, state.schema_mod_or_label, values}

    for topic <-
          topics(
            type,
            state.unique_label,
            values,
            state.identifier_keys
          ) do
      Phoenix.PubSub.broadcast(state.pub_sub_mod, topic, message)
    end

    {:noreply, state}
  end

  def topics(:inserted, unique_label, values, identifier_keys) do
    subscription_columns =
      Enum.filter(values, fn {k, _} -> MapSet.member?(identifier_keys, k) end)

    [unique_label | Enum.map(subscription_columns, fn {k, v} -> "#{unique_label}|#{k}|#{v}" end)]
  end

  def topics(:updated, unique_label, values, identifier_keys) do
    subscription_columns =
      Enum.filter(values, fn {k, _} -> MapSet.member?(identifier_keys, k) end)

    [unique_label | Enum.map(subscription_columns, fn {k, v} -> "#{unique_label}|#{k}|#{v}" end)]
  end

  def topics(:deleted, unique_label, values, identifier_keys) do
    subscription_columns =
      Enum.filter(values, fn {k, _} -> MapSet.member?(identifier_keys, k) end)

    [unique_label | Enum.map(subscription_columns, fn {k, v} -> "#{unique_label}|#{k}|#{v}" end)]
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
