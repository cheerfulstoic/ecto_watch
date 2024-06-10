defmodule EctoWatch.Helpers do
  def is_ecto_schema_mod?(schema_mod) do
    schema_mod.__schema__(:fields)

    true
  rescue
    UndefinedFunctionError -> false
  end
end
