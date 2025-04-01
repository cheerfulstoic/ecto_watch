If you need to verify that your application correctly receives `ecto_watch` events, consider the following:  

- **PostgreSQL, not Ecto, emits the notifications.** This means that for your test to capture notifications, the transaction that triggers them **must be committed**.

- **By default, transactions in tests are not committed.** The [`Ecto.Adapters.SQL.Sandbox`](https://hexdocs.pm/ecto_sql/Ecto.Adapters.SQL.Sandbox.html) ensures test transactions are rolled back unless explicitly overridden.  

- **To ensure notifications are sent, disable the sandbox mode for the test:** 
```elixir
Ecto.Adapters.SQL.Sandbox.checkout(MyRepo, sandbox: false)

```
This forces all database changes to be persisted, so notifications will be emitted. However, be mindful that you may need to manually clean up test records.

### Example

```elixir
defmodule My.Application do
  use Application

  alias MyApp.Records

  @impl true
  def start(_type, _args) do
    children = [
     {EctoWatch,
       repo: MyRepo,
       pub_sub: MyPubSub,
       watchers: [ 
        {Records.Record, :updated}
       ]},
      # Ensure that your module is started after EctoWatch
      {MyApp.UpdateCounter, []}
    ]


    opts = [strategy: :one_for_one, name: My.Supervisor]
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
    :ok = EctoWatch.subscribe(:notification)
    {:ok, %{}}
  end

  def get_total_counts() do
    GenServer.call(__MODULE__, :get_counts)
  end

  def get_total_counts_by_id(id) do
    GenServer.call(__MODULE__, {:get_counts, id})
  end

  # Handle incoming notifications and update state
  def handle_info({Records.Record, :updated}, counts) do
    {:noreply, Map.update(counts, id, 1, &(&1 + 1))}
  end

  def handle_call({:get_count, id}, _from, counts), do: {:reply, Map.get(counts, id), counts}

  def handle_call(:get_counts, _from, counts) do
    total =
      counts
      |> Map.values()
      |> Enum.sum()

    {:reply, total, counts}
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
    Ecto.Adapters.SQL.Sandbox.checkout(MyRepo, sandbox: false)

    # Clean up database before running each test
    cleanup()
  end

  defp cleanup do
    # Add logic to remove test records from the database
  end

test "counter increments whenever a record is updated" do  
    assert UpdateCounter.get_total_counts == 0

    # Based on our application config the following should emit the notifications  
    # events if committed  
    record_1 = record_fixture()
    record_2 = record_fixture()
    Records.update_record(record_1, %{key: "some_value"})  
    Records.update_record(record_2, %{key: "some_value"})  

    # Ensure core logic was executed  
    assert UpdateCounter.get_total_counts_by_id(record_1.id) == 1
    assert UpdateCounter.get_total_counts_by_id(record_2.id) == 1
    refute UpdateCounter.get_total_counts_by_id("non_existing_id")
    assert UpdateCounter.get_total_counts() == 2

  end  
```
