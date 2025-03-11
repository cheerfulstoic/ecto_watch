defmodule EctoWatch.Adapter.PubSub do
  @behaviour EctoWatch.Adapter

  @impl true
  def subscribe(pub_sub_mod, channel_name) do
    Phoenix.PubSub.subscribe(pub_sub_mod, channel_name)
  end

  @impl true
  def unsubscribe(pub_sub_mod, channel_name) do
    Phoenix.PubSub.unsubscribe(pub_sub_mod, channel_name)
  end

  @impl true
  def dispatch(pub_sub_mod, topic, message) do
    Phoenix.PubSub.broadcast(pub_sub_mod, topic, message)
  end

  @impl true
  def subscription_channel(unique_label, column, value) do
    if column && value do
      "#{unique_label}|#{column}|#{value}"
    else
      "#{unique_label}"
    end
  end

  def validate(options) do
    Phoenix.PubSub.node_name(options.pub_sub_mod)

    :ok
  rescue
    _ ->
      {:error,
       "#{inspect(options.pub_sub_mod)} was not a currently running Phoenix PubSub module"}
  end
end
