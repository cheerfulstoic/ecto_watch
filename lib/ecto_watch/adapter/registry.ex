defmodule EctoWatch.Adapter.Registry do
  @behaviour EctoWatch.Adapter

  @impl true
  def subscribe(pub_sub_mod, channel_name) do
    if Registry.count_match(pub_sub_mod, channel_name, :_) == 0 do
      Registry.register(pub_sub_mod, channel_name, [])
    end
  end

  @impl true
  def unsubscribe(pub_sub_mod, channel_name) do
    Registry.unregister(pub_sub_mod, channel_name)
  end

  @impl true
  def dispatch(pub_sub_mod, topic, message) do
    Registry.dispatch(pub_sub_mod, topic, fn pids ->
      for {pid, _} <- pids do
        send(pid, message)
      end
    end)
  end

  @impl true
  def subscription_channel(unique_label, column, value) do
    if column && value do
      "#{unique_label}|#{column}|#{value}"
    else
      "#{unique_label}"
    end
  end

  @impl true
  def validate(options) do
    Registry.meta(options.pub_sub_mod, :keys)

    :ok
  rescue
    _ ->
      {:error, "#{inspect(options.pub_sub_mod)} was not a currently running a Registry"}
  end
end
