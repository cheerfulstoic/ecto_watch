defmodule EctoWatch.WatcherOptions do
  defstruct [:schema_mod, :update_type, :opts]

  def validate_list([]) do
    {:error, "requires at least one watcher"}
  end

  def validate_list(list) when is_list(list) do
    result =
      list
      |> Enum.map(&validate/1)
      |> Enum.find(&match?({:error, _}, &1))

    result || {:ok, list}
  end

  def validate_list(_) do
    {:error, "should be a list"}
  end

  def validate({schema_mod, update_type}) do
    validate({schema_mod, update_type, []})
  end

  def validate({schema_mod, update_type, opts}) do
    if EctoWatch.Helpers.is_ecto_schema_mod?(schema_mod) do
      if update_type in [:inserted, :updated, :deleted] do
        if opts[:columns] do
          if update_type == :updated do
            schema_fields = schema_mod.__schema__(:fields)

            Enum.reject(opts[:columns], &(&1 in schema_fields))
            |> case do
              [] ->
                {:ok, {schema_mod, update_type}}

              extra_fields ->
                {:error, "Invalid columns for #{inspect(schema_mod)}: #{inspect(extra_fields)}"}
            end
          else
            {:error, "Cannot subscribe to columns for #{update_type} events."}
          end
        end
      else
        {:error,
         "Unexpected update_type to be one of :inserted, :updated, or :deleted. Got: #{inspect(update_type)}"}
      end
    else
      {:error, "Expected schema_mod to be an Ecto schema module. Got: #{inspect(schema_mod)}"}
    end
  end

  def validate(other) do
    {:error,
     "should be either `{schema_mod, update_type}` or `{schema_mod, update_type, opts}`.  Got: #{inspect(other)}"}
  end

  def new({schema_mod, update_type}) do
    new({schema_mod, update_type, []})
  end

  def new({schema_mod, update_type, opts}) do
    %__MODULE__{schema_mod: schema_mod, update_type: update_type, opts: opts}
  end
end
