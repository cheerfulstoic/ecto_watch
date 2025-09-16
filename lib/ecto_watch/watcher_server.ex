defmodule EctoWatch.WatcherServer do
  @moduledoc """
  Internal GenServer for the individual change watchers which are configured by end users

  Used internally, but you'll see it in your application supervision tree.
  """

  alias EctoWatch.DB
  alias EctoWatch.Helpers
  alias EctoWatch.Options.WatcherOptions

  use GenServer

  def pub_sub_subscription_details(identifier, identifier_value) do
    with {:ok, pid} <- find(identifier) do
      GenServer.call(pid, {:pub_sub_subscription_details, identifier, identifier_value})
    end
  end

  def details(pid) when is_pid(pid) do
    GenServer.call(pid, :details)
  end

  def details(identifier) do
    with {:ok, pid} <- find(identifier) do
      GenServer.call(pid, :details)
    end
  end

  defp find(identifier) do
    name = unique_label(identifier)

    case Process.whereis(name) do
      nil -> {:error, "No watcher found for #{inspect(identifier)}"}
      pid -> {:ok, pid}
    end
  end

  def start_link({repo_mod, pub_sub_mod, watcher_options}) do
    GenServer.start_link(
      __MODULE__,
      {repo_mod, pub_sub_mod, watcher_options},
      name: unique_label(watcher_options)
    )
  end

  @impl true
  def init({repo_mod, pub_sub_mod, options}) do
    debug_log(options, "Starting server")

    unique_label = "#{unique_label(options)}"

    update_keyword =
      case options.update_type do
        :inserted ->
          "INSERT"

        :updated ->
          if options.trigger_columns && options.trigger_columns != [] do
            # Get the actual column names from the schema definition and make
            # sure they are quoted in case of special characters
            options.trigger_columns
            |> Enum.map_join(", ", &source_column(options.schema_definition, &1))
            |> then(&"UPDATE OF #{&1}")
          else
            "UPDATE"
          end

        :deleted ->
          "DELETE"
      end

    columns_sql =
      [options.schema_definition.primary_key | options.extra_columns]
      |> Enum.map_join(
        ",",
        &"'#{&1}',row.#{source_column(options.schema_definition, &1)}"
      )

    details =
      watcher_details(%{unique_label: unique_label, repo_mod: repo_mod, options: options})

    validate_watcher_details!(details, options)

    Ecto.Adapters.SQL.query!(
      repo_mod,
      """
      CREATE OR REPLACE FUNCTION \"#{options.schema_definition.schema_prefix}\".#{details.function_name}()
        RETURNS trigger AS $trigger$
        DECLARE
          row record;
          payload TEXT;
        BEGIN
          row := COALESCE(NEW, OLD);
          payload := jsonb_build_object('type','#{options.update_type}','values',json_build_object(#{columns_sql}));
          PERFORM pg_notify('#{details.notify_channel}', payload);

          RETURN NEW;
        END;
        $trigger$ LANGUAGE plpgsql;
      """,
      []
    )

    if DB.supports_create_or_replace_trigger?(repo_mod) do
      Ecto.Adapters.SQL.query!(
        repo_mod,
        """
        CREATE OR REPLACE TRIGGER #{details.trigger_name}
          AFTER #{update_keyword} ON \"#{options.schema_definition.schema_prefix}\".\"#{options.schema_definition.table_name}\" FOR EACH ROW
          EXECUTE PROCEDURE \"#{options.schema_definition.schema_prefix}\".#{details.function_name}();
        """,
        []
      )
    else
      Ecto.Adapters.SQL.query!(
        repo_mod,
        """
        DROP TRIGGER IF EXISTS #{details.trigger_name} on \"#{options.schema_definition.schema_prefix}\".\"#{options.schema_definition.table_name}\";
        """,
        []
      )

      Ecto.Adapters.SQL.query!(
        repo_mod,
        """
        CREATE TRIGGER #{details.trigger_name}
          AFTER #{update_keyword} ON \"#{options.schema_definition.schema_prefix}\".\"#{options.schema_definition.table_name}\" FOR EACH ROW
          EXECUTE PROCEDURE \"#{options.schema_definition.schema_prefix}\".#{details.function_name}();
        """,
        []
      )
    end

    notifications_pid = Process.whereis(:ecto_watch_postgrex_notifications)
    {:ok, _notifications_ref} = Postgrex.Notifications.listen(notifications_pid, unique_label)

    {:ok,
     %{
       repo_mod: repo_mod,
       pub_sub_mod: pub_sub_mod,
       unique_label: unique_label,
       identifier_columns:
         MapSet.put(
           MapSet.new(options.schema_definition.association_columns),
           options.schema_definition.primary_key
         ),
       options: options
     }}
  end

  defp source_column(schema_definition, column) do
    Map.get(schema_definition.column_map, column, column)
    |> then(&"\"#{&1}\"")
  end

  @impl true
  def handle_call(
        {:pub_sub_subscription_details, identifier, identifier_value},
        _from,
        state
      ) do
    {column, value} =
      case identifier_value do
        {key, value} ->
          {key, value}

        nil ->
          {nil, nil}

        identifier_value ->
          {state.options.schema_definition.primary_key, identifier_value}
      end

    result =
      with :ok <- validate_subscription(state, identifier, column) do
        channel_name =
          if column && value do
            "#{state.unique_label}|#{column}|#{value}"
          else
            "#{state.unique_label}"
          end

        {:ok, {state.pub_sub_mod, channel_name, state.options.debug?}}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call(:details, _from, state) do
    {:reply, watcher_details(state), state}
  end

  defp validate_subscription(state, identifier, column) do
    cond do
      match?({_, :inserted}, identifier) && column == state.options.schema_definition.primary_key ->
        {:error,
         "Cannot subscribe to primary_key for inserted records because primary key values aren't created until the insert happens"}

      column && not MapSet.member?(state.identifier_columns, column) ->
        {:error, "Column #{column} is not an association column"}

      column && column != state.options.schema_definition.primary_key &&
          column not in state.options.extra_columns ->
        {:error, "Column #{column} is not in the list of extra columns"}

      true ->
        :ok
    end
  end

  @impl true
  def handle_info({:notification, _pid, _ref, channel_name, payload}, state) do
    debug_log(
      state.options,
      "Received Postgrex notification on channel `#{channel_name}`: #{payload}"
    )

    details = watcher_details(state)

    if channel_name != details.notify_channel do
      raise "Expected to receive message from #{details.notify_channel}, but received from #{channel_name}"
    end

    %{"type" => type, "values" => returned_values} = Jason.decode!(payload)

    returned_values = Map.new(returned_values, fn {k, v} -> {String.to_existing_atom(k), v} end)

    type = String.to_existing_atom(type)

    message =
      case state.options.label do
        nil ->
          {{state.options.label || state.options.schema_definition.label, type}, returned_values}

        label ->
          {label, returned_values}
      end

    for topic <-
          topics(
            type,
            state.unique_label,
            returned_values,
            state.options.schema_definition
          ) do
      debug_log(
        state.options,
        "Broadcasting to Phoenix PubSub topic `#{topic}`: #{inspect(message)}"
      )

      Phoenix.PubSub.broadcast(state.pub_sub_mod, topic, message)
    end

    {:noreply, state}
  end

  defp watcher_details(%{unique_label: unique_label, repo_mod: repo_mod, options: options}) do
    %{
      repo_mod: repo_mod,
      schema_definition: options.schema_definition,
      function_name: "#{unique_label}_func",
      notify_channel: unique_label,
      trigger_name: "#{unique_label}_trigger"
    }
  end

  defp validate_watcher_details!(watcher_details, watcher_options) do
    max_identifier_length =
      DB.max_identifier_length(watcher_details.repo_mod)

    max_byte_size =
      max(
        byte_size(watcher_details.function_name),
        byte_size(watcher_details.trigger_name)
      )

    if max_byte_size > max_identifier_length do
      difference = max_byte_size - max_identifier_length

      if watcher_options.label do
        raise """
          Error for watcher: #{inspect(identifier(watcher_options))}

          Label is #{difference} character(s) too long to be part of the Postgres trigger name.
        """
      else
        raise """
          Error for watcher: #{inspect(identifier(watcher_options))}

          Schema module name is #{difference} character(s) too long for the auto-generated Postgres trigger name.

          You may want to use the `label` option

        """
      end
    end
  end

  def topics(update_type, unique_label, returned_values, schema_definition)
      when update_type in ~w[inserted updated deleted]a do
    identifier_columns =
      case update_type do
        :inserted ->
          # There isn't a need to broadcast to topics specifically
          # for the primary key because it's not possible to subscribe
          # to IDs which haven't been created yet.
          schema_definition.association_columns

        _ ->
          [schema_definition.primary_key | schema_definition.association_columns]
      end

    # |> MapSet.new()

    [
      unique_label
      | returned_values
        |> Enum.filter(fn {k, _} -> k in identifier_columns end)
        |> Enum.map(fn {k, v} -> "#{unique_label}|#{k}|#{v}" end)
    ]
  end

  def name(%WatcherOptions{} = watcher_options) do
    unique_label(watcher_options)
  end

  # To make things simple: generate a single string which is unique for each watcher
  # that can be used as the watcher process name, trigger name, trigger function name,
  # and Phoenix.PubSub channel name.
  defp unique_label(%WatcherOptions{} = options) do
    options
    |> identifier()
    |> unique_label()
  end

  defp unique_label({schema_mod, update_type}) do
    :"ew_#{update_type}_for_#{Helpers.label(schema_mod)}"
  end

  defp unique_label(label) do
    :"ew_for_#{Helpers.label(label)}"
  end

  defp identifier(%WatcherOptions{} = options) do
    if options.label do
      options.label
    else
      {options.schema_definition.label, options.update_type}
    end
  end

  defp debug_log(%{debug?: debug_value} = options, message) do
    if debug_value do
      Helpers.debug_log(identifier(options), message)
    end
  end
end
