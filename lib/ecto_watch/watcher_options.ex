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
    opts =
      opts
      |> Keyword.put(:schema_mod, schema_mod)
      |> Keyword.put(:update_type, update_type)

    schema = [
      schema_mod: [
        type: {:custom, __MODULE__, :validate_schema_mod, []},
        required: true
      ],
      update_type: [
        type: {:in, ~w[inserted updated deleted]a},
        required: true
      ],
      label: [
        type: :atom,
        required: false
      ],
      columns: [
        type: {:custom, __MODULE__, :validate_columns, [opts[:label], schema_mod, update_type]},
        required: false
      ]
    ]

    with {:error, error} <- NimbleOptions.validate(opts, schema) do
      {:error, Exception.message(error)}
    end
  end

  def validate(other) do
    {:error,
     "should be either `{schema_mod, update_type}` or `{schema_mod, update_type, opts}`.  Got: #{inspect(other)}"}
  end

  def validate_schema_mod(schema_mod) when is_atom(schema_mod) do
    if EctoWatch.Helpers.is_ecto_schema_mod?(schema_mod) do
      {:ok, schema_mod}
    else
      {:error, "Expected schema_mod to be an Ecto schema module. Got: #{inspect(schema_mod)}"}
    end
  end

  def validate_schema_mod(_), do: {:error, "should be an atom"}

  def validate_columns([], _label, _schema_mod, _update_type),
    do: {:error, "List must not be empty"}

  def validate_columns(_columns, nil, _schema_mod, _update_type),
    do: {:error, "Label must be used when columns are specified"}

  def validate_columns(columns, _label, schema_mod, :updated) do
    schema_fields = schema_mod.__schema__(:fields)

    Enum.reject(columns, &(&1 in schema_fields))
    |> case do
      [] ->
        {:ok, columns}

      extra_fields ->
        {:error, "Invalid columns for #{inspect(schema_mod)}: #{inspect(extra_fields)}"}
    end
  end

  def validate_columns(_columns, _label, _schema_mod, update_type) do
    {:error, "Cannot listen to columns for `#{update_type}` events."}
  end

  def new({schema_mod, update_type}) do
    new({schema_mod, update_type, []})
  end

  def new({schema_mod, update_type, opts}) do
    %__MODULE__{schema_mod: schema_mod, update_type: update_type, opts: opts}
  end
end
