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

  defmodule EctoSchemaDetails do
    @moduledoc """
    Struct holding pre-processed details about Ecto schemas for use in the watcher server
    """

    defstruct ~w[schema_mod pg_schema_name table_name primary_key]a

    def from_watcher_options(watcher_options) do
      pg_schema_name =
        case watcher_options.schema_mod.__schema__(:prefix) do
          nil -> "public"
          prefix -> prefix
        end

      table_name = "#{watcher_options.schema_mod.__schema__(:source)}"

      # TODO: Raise an "unsupported" error if primary key is more than one column
      # Or maybe multiple columns could be supported?
      [primary_key] = watcher_options.schema_mod.__schema__(:primary_key)

      %__MODULE__{
        schema_mod: watcher_options.schema_mod,
        pg_schema_name: pg_schema_name,
        table_name: table_name,
        primary_key: primary_key
      }
    end
  end

  def start_link({repo_mod, pub_sub_mod, watcher_options}) do
    unique_label = "#{unique_label(watcher_options)}"

    ecto_schema_details = EctoSchemaDetails.from_watcher_options(watcher_options)

    GenServer.start_link(
      __MODULE__,
      {repo_mod, pub_sub_mod, ecto_schema_details, watcher_options, unique_label,
       watcher_options.label},
      name: unique_label(watcher_options)
    )
  end

  def handle_call(
        {:pub_sub_subscription_details, schema_mod_or_label, update_type, identifier_value},
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
          {state.ecto_schema_details.primary_key, identifier_value}
      end

    result =
      with :ok <- validate_subscription(state, update_type, column) do
        unique_label = unique_label(schema_mod_or_label, update_type)

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

  defp validate_subscription(state, update_type, column) do
    cond do
      update_type == :inserted && column == state.ecto_schema_details.primary_key ->
        {:error, "Cannot subscribe to primary_key for inserted records"}

      column && not MapSet.member?(state.identifier_columns, column) ->
        {:error, "Column #{column} is not an association column"}

      column && column != state.ecto_schema_details.primary_key &&
          column not in state.options.extra_columns ->
        {:error, "Column #{column} is not in the list of extra columns"}

      true ->
        :ok
    end
  end

  def init({repo_mod, pub_sub_mod, ecto_schema_details, options, unique_label, label}) do
    update_keyword =
      case options.update_type do
        :inserted ->
          "INSERT"

        :updated ->
          if options.trigger_columns do
            "UPDATE OF #{Enum.join(options.trigger_columns, ", ")}"
          else
            "UPDATE"
          end

        :deleted ->
          "DELETE"
      end

    columns_sql =
      [ecto_schema_details.primary_key | options.extra_columns]
      |> Enum.map_join(",", &"'#{&1}',row.#{&1}")

    Ecto.Adapters.SQL.query!(
      repo_mod,
      """
      CREATE OR REPLACE FUNCTION \"#{ecto_schema_details.pg_schema_name}\".#{unique_label}_func()
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
      DROP TRIGGER IF EXISTS #{unique_label}_trigger on \"#{ecto_schema_details.pg_schema_name}\".\"#{ecto_schema_details.table_name}\";
      """,
      []
    )

    Ecto.Adapters.SQL.query!(
      repo_mod,
      """
      CREATE TRIGGER #{unique_label}_trigger
        AFTER #{update_keyword} ON \"#{ecto_schema_details.pg_schema_name}\".\"#{ecto_schema_details.table_name}\" FOR EACH ROW
        EXECUTE PROCEDURE \"#{ecto_schema_details.pg_schema_name}\".#{unique_label}_func();
      """,
      []
    )

    notifications_pid = Process.whereis(:ecto_watch_postgrex_notifications)
    {:ok, _notifications_ref} = Postgrex.Notifications.listen(notifications_pid, unique_label)

    {:ok,
     %{
       pub_sub_mod: pub_sub_mod,
       unique_label: unique_label,
       ecto_schema_details: ecto_schema_details,
       identifier_columns:
         MapSet.put(
           association_columns(ecto_schema_details.schema_mod),
           ecto_schema_details.primary_key
         ),
       options: options,
       schema_mod_or_label: label || ecto_schema_details.schema_mod
     }}
  end

  defp association_columns(schema_mod) do
    schema_mod.__schema__(:associations)
    |> Enum.map(&schema_mod.__schema__(:association, &1))
    |> Enum.map(& &1.owner_key)
    |> MapSet.new()
  end

  def handle_info({:notification, _pid, _ref, channel_name, payload}, state) do
    if channel_name != state.unique_label do
      raise "Expected to receive message from #{state.unique_label}, but received from #{channel_name}"
    end

    %{"type" => type, "values" => returned_values} = Jason.decode!(payload)

    returned_values = Map.new(returned_values, fn {k, v} -> {String.to_existing_atom(k), v} end)

    type = String.to_existing_atom(type)

    message = {type, state.schema_mod_or_label, returned_values}

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
  def unique_label(%WatcherOptions{} = options) do
    unique_label(
      options.label || options.schema_mod,
      options.update_type
    )
  end

  defp unique_label(schema_mod_or_label, update_type) do
    label = Helpers.label(schema_mod_or_label)

    :"ew_#{update_type}_for_#{label}"
  end
end
