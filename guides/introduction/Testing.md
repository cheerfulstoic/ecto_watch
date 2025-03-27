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

  @impl true
  def start(_type, _args) do
    children = [
     {EctoWatch,
       repo: MyRepo,
       pub_sub: MyPubSub,
       watchers: [
         {record, :updated,
          trigger_columns: [:example_column], label: :notification}
       ]}
    ]


    opts = [strategy: :one_for_one, name: My.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

```elixir
# my_notifier.ex -> module to test
defmodule MyNotifier do
  use GenServer
  
  # Rest of the GenServer Code

  # Handle incoming notifications and update state
  def handle_info({:notification, %{id: id}}, state) do
    new_state = Map.update(state, :counter, 1, &(&1 + 1))
    {:noreply, new_state}
  end

  def handle_call(:get_state, _from, state), do: {:reply, state, state}
end
```

in our tests

```elixir
# my_notifier_test.exs
defmodule MyNotifierTest do
  use ExUnit.Case

  setup do
    # Ensure database changes are committed during tests
    Ecto.Adapters.SQL.Sandbox.checkout(Repo, sandbox: false)

    # Clean up database before running each test
    cleanup()
  end

  defp cleanup do
    # Add logic to remove test records from the database
  end

  test "receives a notification when the image description is updated" do
    # Subscribe to notifications for assertions
    :ok = EctoWatch.subscribe(:notification)

    # Based on our application config the following should emit the notification
    # event if committed
    record = record_fixture(%{})
    Records.update_record(record, %{key: "some_value"})

    assert_receive {:notification, %{id: ^record.id}}, 2000

    state = Notifier.get_state()
    assert Map.get(state, :counter) == 1  # Ensure core logic were executed
  end
```
