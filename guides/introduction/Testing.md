As mentioned in the `README`, it's recommended to not run `EctoWatch` in test mode **by default**:

```elixir
defmodule MyApp.Application do
  alias MyApp.Accounts.User
  alias MyApp.Accounts.Package

  def start(_type, _args) do
    # ...

    children = [
      # ...
      # Recommended to not run in `test` mode
      if Mix.env != :test do
        {EctoWatch,
        repo: MyApp.Repo,
        pub_sub: MyApp.PubSub,
        watchers: [
          # ...
        ]}
      else
        :ignore
      end
      # ...
```

It's recommended to use [start_supervised/2](https://hexdocs.pm/ex_unit/ExUnit.Callbacks.html#start_supervised/2) to start up `EctoWatch` in the tests where it makes sense to do so.

If you want to make sure you're always giving the same configuration in your `Application` as you do to `start_supervised/2`, it is recommended that you create a separate module (potentially a `Supervisor`) to DRY up the logic for creating `EctoWatch` watchers.

# When running `EctoWatch` in test mode

If you need to verify that your application correctly receives `ecto_watch` events, consider the following:  

- **PostgreSQL, not Ecto, emits the notifications.** This means that for your test to capture notifications, the transaction that triggers them **must be committed**.

- **By default, transactions in tests are not committed.** The [`Ecto.Adapters.SQL.Sandbox`](https://hexdocs.pm/ecto_sql/Ecto.Adapters.SQL.Sandbox.html) ensures test transactions are rolled back unless explicitly overridden.

- **To ensure notifications are sent, disable the sandbox mode for the test:**

```elixir
Ecto.Adapters.SQL.Sandbox.checkout(MyRepo, sandbox: false)
```

This forces all database changes to be persisted, so notifications will be emitted. However, be mindful that you may need to manually clean up test records.

You don't need to disable transactions in *all* test modules, just those where you need to test your integration with `ecto_watch`.

### Example

```elixir
defmodule MyApp.Application do
  use Application

  alias MyApp.Records

  @impl true
  def start(_type, _args) do
    children = [
     {EctoWatch,
       repo: MyApp.Repo,
       pub_sub: MyApp.PubSub,
       watchers: [ 
        {Records.Record, :updated}
       ]},
      # Ensure that your module is started after EctoWatch
      {MyApp.UpdateCounter, []}
    ]


    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

```elixir
# update_counter.ex -> module to test
defmodule MyApp.UpdateCounter do
  use GenServer
  
  alias MyApp.Records

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_opts) do
    :ok = EctoWatch.subscribe({Records.Record, :updated})
    {:ok, %{}}
  end

  def get_total_counts do
    GenServer.call(__MODULE__, :get_total_counts)
  end

  def get_count(id) do
    GenServer.call(__MODULE__, {:get_count, id})
  end

  # Handle incoming notifications and update state
  def handle_info({Records.Record, :updated}, counts) do
    {:noreply, Map.update(counts, id, 1, &(&1 + 1))}
  end

  def handle_call(:get_total_counts, _from, counts) do
    total =
      counts
      |> Map.values()
      |> Enum.sum()

    {:reply, total, counts}
  end

  def handle_call({:get_count, id}, _from, counts) do
    {:reply, Map.get(counts, id, 0), counts}
  end
end
```

in our tests

```elixir
# update_counter_test.exs
defmodule MyApp.UpdateCounterTest do
  use ExUnit.Case

  alias MyApp.Records

  setup do
    # Ensure database changes are committed during tests
    Ecto.Adapters.SQL.Sandbox.checkout(MyApp.Repo, sandbox: false)

    # Clean up database before running each test
    cleanup()
  end

  defp cleanup do
    # Add logic to remove test records from the database
  end

test "counter increments whenever a record is updated" do  
    record_1 = record_fixture()
    record_2 = record_fixture()

    assert UpdateCounter.get_count(record_1.id) == 0
    assert UpdateCounter.get_count(record_2.id) == 0
    assert UpdateCounter.get_total_counts() == 0

    # Based on our application config the following should emit the notifications
    # events if committed
    Records.update_record(record_1, %{key: "some_value"})
    Records.update_record(record_2, %{key: "some_value"})

    # Ensure core logic was executed
    assert UpdateCounter.get_count(record_1.id) == 1
    assert UpdateCounter.get_count(record_2.id) == 1
    assert UpdateCounter.get_count("non_existing_id") == 0
    assert UpdateCounter.get_total_counts() == 2
  end
```
