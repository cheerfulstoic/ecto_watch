defmodule EctoWatch.WatcherTriggerValidator do
  @moduledoc """
  Internal task run as part of the EctoWatch supervision tree to check for a match between the triggers
  that are in the database and the triggers that were started via the configuration.

  Used internally, but you'll see it in your application supervision tree.
  """

  alias EctoWatch.WatcherSupervisor

  use Task, restart: :transient

  require Logger

  def start_link(_) do
    Task.start_link(__MODULE__, :run, [nil])
  end

  defmodule TriggerDetails do
    @moduledoc false

    defstruct ~w[name table_schema table_name]a
  end

  defmodule FunctionDetails do
    @moduledoc false

    defstruct ~w[name schema]a
  end

  def run(_) do
    triggers_by_repo_mod()
    |> Enum.each(fn {repo_mod, {extra_found_triggers, extra_found_functions}} ->
      if System.get_env("ECTO_WATCH_CLEANUP") == "cleanup" do
        # One solution would be to remove all triggers and then allow them to be re-created,
        # but that could lead to missed messages.  Better to remove unused triggers.
        Enum.each(extra_found_triggers, &drop_trigger(repo_mod, &1))
        Enum.each(extra_found_functions, &drop_function(repo_mod, &1))
      else
        if MapSet.size(extra_found_triggers) > 0 do
          log_extra_triggers(extra_found_triggers)
        end

        if MapSet.size(extra_found_functions) > 0 do
          log_extra_functions(extra_found_functions)
        end
      end
    end)

    :ok
  end

  defp log_extra_triggers(extra_found_triggers) do
    Logger.error("""
    Found the following extra EctoWatch triggers:

    #{Enum.map_join(extra_found_triggers, "\n", fn trigger_details -> "\"#{trigger_details.name}\" in the table \"#{trigger_details.table_schema}\".\"#{trigger_details.table_name}\"" end)}

    ...but they were not specified in the watcher options.

    To cleanup unspecified triggers and functions, run your app with the `ECTO_WATCH_CLEANUP`
    environment variable set to the value `cleanup`
    """)
  end

  defp log_extra_functions(extra_found_functions) do
    Logger.error("""
    Found the following extra EctoWatch functions:

    #{Enum.map_join(extra_found_functions, "\n", fn function_details -> "\"#{function_details.name}\" in the schema \"#{function_details.schema}\"" end)}

    To cleanup unspecified triggers and functions, run your app with the `ECTO_WATCH_CLEANUP`
    environment variable set to the value `cleanup`
    """)
  end

  defp triggers_by_repo_mod do
    case WatcherSupervisor.watcher_details() do
      {:ok, watcher_details} ->
        watcher_details

      {:error, message} ->
        raise message
    end
    |> Enum.group_by(& &1.repo_mod)
    |> Map.new(fn {repo_mod, details} ->
      specified_triggers =
        details
        |> Enum.map(fn details ->
          %TriggerDetails{
            name: details.trigger_name,
            table_schema: details.schema_definition.schema_prefix,
            table_name: details.schema_definition.table_name
          }
        end)
        |> MapSet.new()

      specified_functions =
        details
        |> Enum.map(fn details ->
          %FunctionDetails{
            name: details.function_name,
            schema: details.schema_definition.schema_prefix
          }
        end)
        |> MapSet.new()

      found_triggers = find_triggers(repo_mod)

      found_functions = find_functions(repo_mod)

      {
        repo_mod,
        {
          MapSet.difference(found_triggers, specified_triggers),
          MapSet.difference(found_functions, specified_functions)
        }
      }
    end)
  end

  defp drop_trigger(repo_mod, %TriggerDetails{} = trigger_details) do
    sql_query(
      repo_mod,
      """
      DROP TRIGGER IF EXISTS "#{trigger_details.name}" ON "#{trigger_details.table_schema}".#{trigger_details.table_name}
      """
    )
  end

  defp drop_function(repo_mod, %FunctionDetails{} = function_details) do
    sql_query(
      repo_mod,
      """
      DROP FUNCTION IF EXISTS "#{function_details.schema}"."#{function_details.name}"
      """
    )
  end

  # When triggers are inserted for a partitioned table,
  # Postgres will automatically add "clone" triggers for all partitions
  # https://www.postgresql.org/docs/current/sql-createtrigger.html
  # So when looking for stray triggers we exclude triggers on
  # tables that have an entry in pg_inherits (= are partitions)
  defp find_triggers(repo_mod) do
    sql_query(
      repo_mod,
      """
      SELECT trigger_name, event_object_schema, event_object_table
      FROM information_schema.triggers
      WHERE trigger_name LIKE 'ew_%'
        AND EXISTS (
          SELECT 1
          FROM pg_class c
            JOIN pg_namespace n ON c.relnamespace = n.oid
          WHERE n.nspname = event_object_schema
            AND c.relname = event_object_table
            AND NOT EXISTS (
              SELECT 1
              FROM pg_inherits inh
              WHERE inh.inhrelid = c.oid
            )
        )
      """
    )
    |> Enum.map(fn [name, table_schema, table_name] ->
      %TriggerDetails{
        name: name,
        table_schema: table_schema,
        table_name: table_name
      }
    end)
    |> MapSet.new()
  end

  def find_functions(repo_mod) do
    sql_query(
      repo_mod,
      """
      SELECT n.nspname AS schema, p.proname AS name
      FROM pg_proc p LEFT JOIN pg_namespace n ON p.pronamespace = n.oid
      WHERE n.nspname NOT IN ('pg_catalog', 'information_schema') AND p.proname LIKE 'ew_%'
      ORDER BY schema, name;
      """
    )
    |> Enum.map(fn [schema, name] -> %FunctionDetails{name: name, schema: schema} end)
    |> MapSet.new()
  end

  defp sql_query(repo_mod, query) do
    %Postgrex.Result{rows: rows} = Ecto.Adapters.SQL.query!(repo_mod, query, [])

    rows
  end
end
