defmodule EctoWatch.WatcherServer do
  @moduledoc """
  GenServer for the individiual change watchers which are configured by end users
  """

  alias EctoWatch.Helpers
  alias EctoWatch.Options.WatcherOptions

  use GenServer

  def pub_sub_subscription_details(identifier, identifier_value) do
    with {:ok, pid} <- find(identifier) do
      GenServer.call(pid, {:pub_sub_subscription_details, identifier, identifier_value})
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

  def init({repo_mod, pub_sub_mod, options}) do
    unique_label = "#{unique_label(options)}"

    update_keyword =
      case options.update_type do
        :inserted ->
          "INSERT"

        :updated ->
          if options.trigger_columns && options.trigger_columns != [] do
            "UPDATE OF #{Enum.join(options.trigger_columns, ", ")}"
          else
            "UPDATE"
          end

        :deleted ->
          "DELETE"
      end

    columns_sql =
      [options.schema_definition.primary_key | options.extra_columns]
      |> Enum.map_join(",", &"'#{&1}',row.#{&1}")

    Ecto.Adapters.SQL.query!(
      repo_mod,
      """
      CREATE OR REPLACE FUNCTION \"#{options.schema_definition.schema_prefix}\".#{unique_label}_func()
        RETURNS trigger AS $trigger$
        DECLARE
          row record;
          payload TEXT;
        BEGIN
          row := COALESCE(NEW, OLD);
          payload := jsonb_build_object('type','#{options.update_type}','values',json_build_object(#{columns_sql}));
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
      DROP TRIGGER IF EXISTS #{unique_label}_trigger on \"#{options.schema_definition.schema_prefix}\".\"#{options.schema_definition.table_name}\";
      """,
      []
    )

    Ecto.Adapters.SQL.query!(
      repo_mod,
      """
      CREATE TRIGGER #{unique_label}_trigger
        AFTER #{update_keyword} ON \"#{options.schema_definition.schema_prefix}\".\"#{options.schema_definition.table_name}\" FOR EACH ROW
        EXECUTE PROCEDURE \"#{options.schema_definition.schema_prefix}\".#{unique_label}_func();
      """,
      []
    )

    notifications_pid = Process.whereis(:ecto_watch_postgrex_notifications)
    {:ok, _notifications_ref} = Postgrex.Notifications.listen(notifications_pid, unique_label)

    {:ok,
     %{
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

        {:ok, {state.pub_sub_mod, channel_name}}
      end

    {:reply, result, state}
  end

  defp validate_subscription(state, identifier, column) do
    cond do
      match?({_, :inserted}, identifier) && column == state.options.schema_definition.primary_key ->
        {:error, "Cannot subscribe to primary_key for inserted records"}

      column && not MapSet.member?(state.identifier_columns, column) ->
        {:error, "Column #{column} is not an association column"}

      column && column != state.options.schema_definition.primary_key &&
          column not in state.options.extra_columns ->
        {:error, "Column #{column} is not in the list of extra columns"}

      true ->
        :ok
    end
  end

  def handle_info({:notification, _pid, _ref, channel_name, payload}, state) do
    if channel_name != state.unique_label do
      raise "Expected to receive message from #{state.unique_label}, but received from #{channel_name}"
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
            state.identifier_columns
          ) do
      Phoenix.PubSub.broadcast(state.pub_sub_mod, topic, message)
    end

    {:noreply, state}
  end

  def topics(update_type, unique_label, returned_values, identifier_columns)
      when update_type in ~w[inserted updated deleted]a do
    [
      unique_label
      | returned_values
        |> Enum.filter(fn {k, _} -> MapSet.member?(identifier_columns, k) end)
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
    if options.label do
      unique_label(options.label)
    else
      unique_label({options.schema_definition.label, options.update_type})
    end
  end

  defp unique_label({schema_mod, update_type}) do
    :"ew_#{update_type}_for_#{Helpers.label(schema_mod)}"
  end

  defp unique_label(label) do
    :"ew_for_#{Helpers.label(label)}"
  end
end
