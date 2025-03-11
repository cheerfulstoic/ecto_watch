defmodule EctoWatch.Adapter do
  @moduledoc false
  @type watcher_identifier() :: {atom(), atom()} | atom()

  @callback subscribe(watcher_identifier(), term()) :: :ok | {:error, term()}
  @callback unsubscribe(watcher_identifier(), term()) :: :ok
  @callback subscription_channel(String.t(), atom(), term()) :: term()
  @callback dispatch(atom(), term(), {atom(), map()}) :: :ok
  @callback validate(map()) :: :ok | {:error, term()}
end
