defmodule EctoWatch.Helpers do
  @moduledoc false
  require Logger

  def ecto_schema_mod?(schema_mod) do
    schema_mod.__schema__(:fields)

    true
  rescue
    UndefinedFunctionError -> false
  end

  def validate_list(list, func) when is_list(list) do
    result =
      list
      |> Enum.map(func)

    first_error =
      result
      |> Enum.find(&match?({:error, _}, &1))

    first_error || {:ok, Enum.map(result, fn {:ok, value} -> value end)}
  end

  def validate_list(_, _) do
    {:error, "should be a list"}
  end

  def debug_log(watcher_identifier, message) do
    Logger.debug("EctoWatch | #{inspect(watcher_identifier)} | #{inspect(self())} | #{message}")
  end
end
