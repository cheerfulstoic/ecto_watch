defmodule EctoWatch.WatcherOptions do
  defstruct [:schema_mod, :update_type, :opts]

  def new({schema_mod, update_type}) do
    new({schema_mod, update_type, []})
  end

  def new({schema_mod, update_type, opts}) do
    %__MODULE__{schema_mod: schema_mod, update_type: update_type, opts: opts}
  end
end
