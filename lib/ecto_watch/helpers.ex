defmodule EctoWatch.Helpers do
  @moduledoc """
  General helpers useful throughout the `ecto_watch` library
  """

  def label(schema_mod_or_label) do
    if ecto_schema_mod?(schema_mod_or_label) do
      module_to_label(schema_mod_or_label)
    else
      schema_mod_or_label
    end
  end

  def module_to_label(module) do
    module
    |> Module.split()
    |> Enum.join("_")
    |> String.downcase()
  end

  def ecto_schema_mod?(schema_mod) do
    schema_mod.__schema__(:fields)

    true
  rescue
    UndefinedFunctionError -> false
  end
end
