# EctoWatch

EctoWatch allows you to easily get Phoenix.PubSub notifications *directly* from postgresql.

Often in Elixir applications a `Phoenix.PubSub.broadcast` is inserted manually into the application code to notify other parts of the application about an inserts, updates, or deletions.  This has a few problems:

 * Ideally a single function is used in an application to update a type of record (e.g. `MyApp.Accounts.update_user`).  This function is generally where a broadcast is done after updating, but developers may forget to call this function and make updates directly through `MyApp.Repo.update`.
 * PubSub messages can be sent in a lot of ways so having a standard which has been thought-through is useful:
   * Having a single topic (e.g. `users`) means that all messages are sent to all subscribers, which can be inefficient.
   * Having a topic per record (e.g. `users:1`, `users:2`, etc.) means that a subscriber needs to subscribe to every record, which can be inefficient.
   * There may be inconsistancy in pluralization of topics (e.g. `user` and `packages` topics) which can be confusing and lead to bugs.
   * Having a message that is just `{:updated, id}` doesn't make it clear which schema was updated, using `{schema, id}` doesn't make it clear which operation happened.
 * Often full records are sent which can scale poorly since messages in Elixir are copied in memory when sent.
 * Sometimes records are sent preloaded with different associations in different cases, requiring either careful coordination or a sending of all associations regardless of where they are needed.

EctoWatch solves these problems by getting updates directly from postgresql.  This ensures that messages are sent for *every* update.  EctoWatch also establishes a simple standardized set of messages for inserts, updates, and deletes so that there can be consistency across your application.  Only the id of the record is sent which

 * makes for a small message
 * ensures that the record and associations are loaded only when needed

## Usage

To use EctoWatch, you need to add it to your supervision tree and specify the ecto schemas that you want to monitor.  You can do this by adding something like the following to your `application.ex` file (after your `MyApp.Repo` and `MyApp.PubSub` are loaded):

```elixir
  {EctoWatch, {MyApp.Repo, MyApp.PubSub, [
    MyApp.Accounts.User,
    {MyApp.Shipping.Package, [:inserted, :updated]}
  ]}},
```

This will setup:

 * triggers in postgresql on application startup
 * an Elixir process which listens for notifications and broadcasts them via `Phoenix.PubSub`

Then any process (e.g. a GenServer, a LiveView, or a Phoenix channel) can subscribe to messages like so:

```elixir
  EctoWatch.subscribe(MyApp.Accounts.User, :inserted)
  EctoWatch.subscribe(MyApp.Accounts.User, :updated)
  EctoWatch.subscribe(MyApp.Accounts.User, :deleted)

  EctoWatch.subscribe(MyApp.Shipping.Package, :inserted)
  EctoWatch.subscribe(MyApp.Shipping.Package, :updated)
```

(note that if you are subscribing in a LiveView `mount` callback you should subscribe inside of a `if connected?(socket) do` to avoid subscribing twice).

You can also subscribe to individual records:

```elixir
  EctoWatch.subscribe(MyApp.Accounts.Package, :updated, package.id)
  EctoWatch.subscribe(MyApp.Accounts.Package, :deleted, package.id)
```

Once a process is subscribed messages can be handled like so (LiveView example given here but `handle_info` callbacks can be used elsewhere as well):

```elixir
  def handle_info({:inserted, MyApp.Accounts.User, id}, socket) do
    user = Accounts.get_user(id)
    socket = stream_insert(socket, :users, user)

    {:noreply, socket}
  end

  def handle_info({:updated, MyApp.Accounts.User, id}, socket) do
    user = Accounts.get_user(id)
    socket = stream_insert(socket, :users, user)

    {:noreply, socket}
  end

  def handle_info({:deleted, MyApp.Accounts.User, id}, socket) do
    user = Accounts.get_user(id)
    socket = stream_delete(socket, :users, user)

    {:noreply, socket}
  end
```

## Notes

### Why only send the id and not the full record?

The main reason: The `pg_notify` function has a limit of 8000 characters and wasn't created to send full-records on updates.

Also if many updates are done in quick succession to the same record, subscribers will need to process all of the old results before getting to the newest one.  For example if a LiveView is a subscriber it may get 10 updates about a record to the browser.  If the LiveView has to make a query then it will be more likely to get the latest data.  Since LiveView doesn't send updates when nothing has changed in the view for the user, this will mean less traffic to the browsers.

### Scaling of queries

If you have many processes which are subscribed to updates and each process, on receiving the message, makes a query to the database, this can lead to many queries.  You may solve this by creating a GenServer which listens for messages and then makes a single query to the database (e.g. every X milliseconds) to get all the records that need to be updated, passing them on via another `PubSub` message.

This may be added later as a feature of `EctoWatch`.

### Sometimes you may not want updates whenever there's an update from the database

If you have a task or a migration that needs to update the database **without** triggering updates in the rest of the application there are a few solutions (see [this StackOverflow question](https://stackoverflow.com/questions/37730870/how-to-disable-postgresql-triggers-in-one-transaction-only).  One solutions is to set `session_replication_role` to `replica` temporarily in a transaction:

```
BEGIN
SET session_replication_role = replica;
-- do changes here --
SET session_replication_role = DEFAULT;
COMMIT
```

Disabling the triggers can lock the table in a transaction and so should be used with caution.  Disabling the triggers outside of a transaction may cause updates to be missed.

## Potential TODOs

 * Support features of `CREATE TRIGGER`:
   * allow specifying a condition for when the trigger should fire
   * allow specifying which columns the trigger should be run on
 * Creating a batch-processing GenServer to reduce queries to the database.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `ecto_watch` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ecto_watch, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/ecto_watch>.

