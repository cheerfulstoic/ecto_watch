defmodule EctoWatch.Label do
  alias EctoWatch.Helpers
  alias EctoWatch.Options.WatcherOptions

  @doc """
  To make things simple: generate a single string which is unique for each watcher
  that can be used as the watcher process name, trigger name, trigger function name,
  and Phoenix.PubSub channel name.
  """
  def unique_label(%WatcherOptions{} = options) do
    options
    |> identifier()
    |> unique_label()
  end

  def unique_label({schema_mod, update_type}) do
    update_type = short_update_type(update_type)
    :"ew_#{update_type}_for_#{truncated_label(schema_mod)}"
  end

  def unique_label(label) do
    :"ew_for_#{truncated_label(label)}"
  end

  def identifier(%WatcherOptions{} = options) do
    if options.label do
      options.label
    else
      {options.schema_definition.label, options.update_type}
    end
  end

  defp short_update_type(update_type) do
    case update_type do
      :inserted -> "i"
      :updated -> "u"
      :deleted -> "d"
    end
  end

  defp truncated_label(label) do
    label = label(label)
    string_label = to_string(label)
    chsum = :erlang.phash2(string_label) |> to_string()
    length = String.length(string_label)

    if length > 63 - 9 do
      # 63 = max length of a postgres identifier
      # 9  = ew_for_ + update_type + underscores
      # 5  = _func / _trig
      max_length = 63 - 9 - String.length(chsum) - 5
      sublabel = String.slice(string_label, 0, max_length)
      "#{sublabel}_#{chsum}"
    else
      string_label
    end
  end

  defp label(schema_mod_or_label) do
    if Helpers.ecto_schema_mod?(schema_mod_or_label) do
      module_to_label(schema_mod_or_label)
    else
      schema_mod_or_label
    end
  end

  defp module_to_label(module) do
    module
    |> Module.split()
    |> Enum.join("_")
    |> String.downcase()
  end
end
