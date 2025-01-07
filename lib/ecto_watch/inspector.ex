defmodule EctoWatch.Inspector do
  @moduledoc """
  Use this module to compare given configuration VS triggers / functions in the DB
  """

  alias EctoWatch.WatcherTriggerValidator.FunctionDetails
  alias EctoWatch.WatcherTriggerValidator.TriggerDetails

  def watcher_details do
    case EctoWatch.WatcherSupervisor.watcher_details() do
      {:ok, watcher_details} ->
        watcher_details

      {:error, message} ->
        raise message
    end
  end

  def repo_details(repo_mod) do
    by_repo = Enum.group_by(watcher_details(), & &1.repo_mod)
    details = Map.get(by_repo, repo_mod)
    summary_for_repo(repo_mod, details)
  end

  defp triggers_for_repo(details) do
    details
    |> Enum.map(fn details ->
      %TriggerDetails{
        name: details.trigger_name,
        table_schema: details.schema_definition.schema_prefix,
        table_name: details.schema_definition.table_name
      }
    end)
    |> MapSet.new()
  end

  defp functions_for_repo(details) do
    details
    |> Enum.map(fn details ->
      %FunctionDetails{
        name: details.function_name,
        schema: details.schema_definition.schema_prefix
      }
    end)
    |> MapSet.new()
  end

  defp summary_for_repo(repo_mod, details) do
    specified_triggers = triggers_for_repo(details)
    specified_functions = functions_for_repo(details)
    found_triggers = find_triggers(repo_mod)
    found_functions = find_functions(repo_mod)

    Map.new([
      {
        repo_mod,
        %{
          diff_triggers: MapSet.difference(found_triggers, specified_triggers),
          diff_functions: MapSet.difference(found_functions, specified_functions),
          specified_triggers: specified_triggers,
          specified_functions: specified_functions,
          found_triggers: found_triggers,
          found_functions: found_functions
        }
      }
    ])
  end

  defp find_triggers(repo_mod) do
    sql_query(
      repo_mod,
      """
      SELECT trigger_name, event_object_schema, event_object_table
      FROM information_schema.triggers
      WHERE trigger_name LIKE 'ew_%'
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

  defp find_functions(repo_mod) do
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
