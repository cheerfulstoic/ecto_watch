defmodule EctoWatch.Options.WatcherOptions do
  alias EctoWatch.Helpers

  @moduledoc """
  Logic for processing the `EctoWatch` postgres notification watcher options
  which are passed in by the end user's config
  """
  defstruct [:schema_definition, :update_type, :label, :trigger_columns, :extra_columns]

  def validate_list(list) do
    Helpers.validate_list(list, &validate/1)
  end

  defmodule SchemaDefinition do
    @moduledoc """
    Generic representation of an app schema.  Contains important details about a postgres table,
    whether it's create from an Ecto schema module or from a map.
    """
    defstruct [
      :schema_prefix,
      :table_name,
      :primary_key,
      :columns,
      :association_columns,
      :label
    ]

    def new(schema_mod) when is_atom(schema_mod) do
      schema_prefix =
        case schema_mod.__schema__(:prefix) do
          nil -> "public"
          prefix -> prefix
        end

      table_name = "#{schema_mod.__schema__(:source)}"
      [primary_key] = schema_mod.__schema__(:primary_key)

      fields = schema_mod.__schema__(:fields)

      association_columns =
        schema_mod.__schema__(:associations)
        |> Enum.map(&schema_mod.__schema__(:association, &1))
        |> Enum.map(& &1.owner_key)

      %__MODULE__{
        schema_prefix: schema_prefix,
        table_name: table_name,
        primary_key: primary_key,
        columns: fields,
        association_columns: association_columns,
        label: schema_mod
      }
    end

    def new(%__MODULE__{}) do
      raise "There is a bug!  SchemaDefinition struct was passed to new/1"
    end

    def new(opts) when is_map(opts) do
      schema_prefix = opts[:schema_prefix] || "public"

      %__MODULE__{
        schema_prefix: to_string(schema_prefix),
        table_name: to_string(opts.table_name),
        primary_key: opts.primary_key,
        columns: opts.columns,
        association_columns: opts[:association_columns] || [],
        label: "#{schema_prefix}|#{opts.table_name}"
      }
    end
  end

  def validate({schema_definition, update_type}) do
    validate({schema_definition, update_type, []})
  end

  def validate({schema_definition, update_type, opts}) do
    with {:ok, schema_definition} <- validate_schema_definition(schema_definition, opts[:label]),
         {:ok, update_type} <- validate_update_type(update_type),
         {:ok, opts} <- validate_opts(opts, schema_definition, update_type) do
      {:ok, {schema_definition, update_type, opts}}
    end
  end

  def validate(other) do
    {:error,
     "should be either `{schema_definition, update_type}` or `{schema_definition, update_type, opts}`.  Got: #{inspect(other)}"}
  end

  def validate_schema_definition(schema_mod, _label_opt) when is_atom(schema_mod) do
    if EctoWatch.Helpers.ecto_schema_mod?(schema_mod) do
      {:ok, schema_mod}
    else
      {:error, "Expected atom to be an Ecto schema module. Got: #{inspect(schema_mod)}"}
    end
  end

  def validate_schema_definition(opts, label_opt) when is_map(opts) do
    schema = [
      schema_prefix: [
        type: {:or, ~w[string atom]a},
        required: false,
        default: :public
      ],
      table_name: [
        type: {:or, ~w[string atom]a},
        required: true
      ],
      primary_key: [
        type: :atom,
        required: false,
        default: :id
      ],
      columns: [
        type: {:list, :atom},
        required: false,
        default: []
      ],
      association_columns: [
        type: {:list, :atom},
        required: false,
        default: []
      ]
    ]

    if label_opt do
      with {:error, error} <- NimbleOptions.validate(opts, NimbleOptions.new!(schema)) do
        {:error, Exception.message(error)}
      end
    else
      {:error, "Label must be used when passing in a map for schema_definition"}
    end
  end

  def validate_schema_definition(_, _), do: {:error, "should be an ecto schema module name"}

  def validate_update_type(update_type) do
    if update_type in ~w[inserted updated deleted]a do
      {:ok, update_type}
    else
      {:error, "update_type was not one of :inserted, :updated, or :deleted"}
    end
  end

  def validate_opts(opts, schema_definition, update_type) do
    schema_definition = SchemaDefinition.new(schema_definition)

    schema = [
      label: [
        type: :atom,
        required: false
      ],
      trigger_columns: [
        type:
          {:custom, __MODULE__, :validate_trigger_columns,
           [opts[:label], schema_definition, update_type]},
        required: false
      ],
      extra_columns: [
        type: {:custom, __MODULE__, :validate_columns, [schema_definition]},
        required: false
      ]
    ]

    with {:error, error} <- NimbleOptions.validate(opts, schema) do
      {:error, Exception.message(error)}
    end
  end

  def validate_trigger_columns(columns, label, schema_definition, update_type) do
    cond do
      update_type != :updated ->
        {:error,
         "Cannot listen to trigger_columns for `#{update_type}` events (only for `#{:updated}` events."}

      label == nil ->
        {:error, "Label must be used when trigger_columns are specified."}

      true ->
        validate_columns(columns, schema_definition)
    end
  end

  def validate_columns([], _schema_mod),
    do: {:error, "List must not be empty"}

  def validate_columns(columns, schema_definition) do
    Helpers.validate_list(columns, fn
      column when is_atom(column) ->
        if column in schema_definition.columns do
          {:ok, column}
        else
          {:error,
           "Invalid column: #{inspect(column)} (expected to be in #{inspect(schema_definition.columns)})"}
        end

      column ->
        {:error, "Invalid column: #{inspect(column)} (expected to be an atom)"}
    end)
  end

  def new({schema_definition, update_type}) do
    new({schema_definition, update_type, []})
  end

  def new({schema_definition, update_type, opts}) do
    schema_definition = SchemaDefinition.new(schema_definition)

    %__MODULE__{
      schema_definition: schema_definition,
      update_type: update_type,
      label: opts[:label],
      trigger_columns: opts[:trigger_columns] || [],
      extra_columns: opts[:extra_columns] || []
    }
  end
end
