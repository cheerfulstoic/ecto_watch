# EctoWatch

<sub>(Thanks to [Erlang Solutions](https://www.erlang-solutions.com) for sponsoring this project)</sub>

EctoWatch allows you to easily setup notifications of database changes *directly* from PostgreSQL.

Often in Elixir applications a `Phoenix.PubSub.broadcast` is inserted into the application code to notify the rest of the application about inserts, updates, or deletions (e.g. `Accounts.insert_user`/`Accounts.update_user`/`Accounts.delete_user`).  This has a few potential problems:

 * Developers may forget to call these functions and make updates directly through `MyApp.Repo.*`.
 * Often different standards of PubSub messages are used. [^1]
 * Often full records are used which can scale poorly since messages in Elixir are copied in memory when sent.
 * Sometimes records are sent preloaded with different associations in different cases, requiring either careful coordination or sending all associations regardless of where they are needed.

By getting updates directly from PostgreSQL, EctoWatch ensures that messages are sent for *every* change (even changes from other clients of the database).  EctoWatch also establishes a simple, standardized set of messages for inserts, updates, and deletes so that there can be consistency across your application.  By default only the id of the record is sent (makeing for smaller messages).

## Example use-cases for `EctoWatch`

 * Updating LiveView in real-time
 * Sending emails when a record is updated
 * Updating a cache when a record is updated
 * Sending a webhook request to inform another system about a change

## Usage

To use EctoWatch, you need to add it to your supervision tree and specify watchers for Ecto schemas and update types.  It would look something like this in your `application.ex` file (after `MyApp.Repo` and `MyApp.PubSub`):

```elixir
  alias MyApp.Accounts.User
  alias MyApp.Accounts.Package

  {EctoWatch,
   repo: MyApp.Repo,
   pub_sub: MyApp.PubSub,
   watchers: [
     {User, :inserted},
     {User, :updated},
     {User, :deleted},
     {Package, :inserted},
     {Package, :updated}
   ]}
```

This will setup:

 * triggers in PostgreSQL during application startup
 * an Elixir process for each watcher which listens for notifications and broadcasts them via `Phoenix.PubSub`

Then any process (e.g. a GenServer, a LiveView, a Phoenix channel, etc...) can subscribe to messages like so:

```elixir
  EctoWatch.subscribe(User, :inserted)
  EctoWatch.subscribe(User, :updated)
  EctoWatch.subscribe(User, :deleted)

  EctoWatch.subscribe(Package, :inserted)
  EctoWatch.subscribe(Package, :updated)
```

(note that if you are subscribing in a LiveView `mount` callback you should subscribe inside of a `if connected?(socket) do` to avoid subscribing twice).

You can also subscribe to individual records:

```elixir
  EctoWatch.subscribe(User, :updated, user.id)
  EctoWatch.subscribe(User, :deleted, user.id)
```

... OR you can subscribe to records by an association column (but the given column must be in the `extra_columns` list for the watcher! See below for more info on the `extra_columns` option):

```elixir
  EctoWatch.subscribe(User, :updated, {:role_id, role.id})
  EctoWatch.subscribe(User, :deleted, {:role_id, role.id})
```

Once subscribed, messages can be handled like so (LiveView example are given here but `handle_info` callbacks can be used elsewhere as well):

```elixir
  def handle_info({{User, :inserted}, %{id: id}}, socket) do
    user = Accounts.get_user(id)
    socket = stream_insert(socket, :users, user)

    {:noreply, socket}
  end

  def handle_info({{User, :updated}, %{id: id}}, socket) do
    user = Accounts.get_user(id)
    socket = stream_insert(socket, :users, user)

    {:noreply, socket}
  end

  def handle_info({{User, :deleted}, %{id: id}}, socket) do
    socket = stream_delete_by_dom_id(socket, :songs, "users-#{id}")

    {:noreply, socket}
  end
```

## Tracking specific columns and using labels

You can also setup the database to trigger only on specific column changes on `:updated` watchers.  When doing this a `label` required:

```elixir
  # setup
  {EctoWatch,
   repo: MyApp.Repo,
   pub_sub: MyApp.PubSub,
   watchers: [
     # ...
     {User, :updated, trigger_columns: [:email, :phone], label: :user_contact_info_updated},
     # ...
   ]}

  # subscribing
  EctoWatch.subscribe(:user_contact_info_updated)
  # or...
  EctoWatch.subscribe(:user_contact_info_updated, package.id)

  # handling messages
  def handle_info({:user_contact_info_updated, %{id: id}}, socket) do
```

A label is required for two reasons:

 * When handling the message it makes it clear that the message isn't for general schema updates but is for specific columns
 * The same schema can be watched for different sets of columns, so the label is used to differentiate between them.

You can also use labels in general without tracking specific columns:

```elixir
  # setup
  {EctoWatch,
   repo: MyApp.Repo,
   pub_sub: MyApp.PubSub,
   watchers: [
     # ...
     {User, :updated, label: :user_update},
     # ...
   ]}

  # subscribing
  EctoWatch.subscribe(:user_update)
  # or...
  EctoWatch.subscribe(:user_update, package.id)

  # handling messages
  def handle_info({:user_update, %{id: id}}, socket) do
```

## Getting additional values

If you would like to get more than just the `id` from the record, you can use the `extra_columns` option.

> [!IMPORTANT]
> The `extra_columns` option should be used with care because:
> 
>  * The `pg_notify` function has a limit of 8000 characters and wasn't created to send full-records on updates.
>  * If many updates are done in quick succession to the same record, subscribers will need to process all of the old results before getting to the newest one.
>
> Thus using `extra_columns` with columns that change often may not be what you want.
>
> One use-case where using `extra_columns` may be particularly useful is if you want to receive updates about the deletion of a record and you need to know one of it's foreign keys.  E.g. in a blog, if a `Comment` is deleted you might want to get the `post_id` to refresh any caches related to comments.

```elixir
  # setup
  {EctoWatch,
   repo: MyApp.Repo,
   pub_sub: MyApp.PubSub,
   watchers: [
     # ...
     {Comment, :deleted, extra_columns: [:post_id]},
     # ...
   ]}

  # subscribing
  EctoWatch.subscribe(Comment, :deleted)

  # handling messages
  def handle_info({{Comment, :deleted}, %{id: id, post_id: post_id}}, socket) do
    Posts.refresh_cache(post_id)
```

## Watching without a schema

Since ecto supports working with tables withoun needed a schema, you may also want to create EctoWatch watchers without needing to create a schema like so:

```elixir
  # setup
  {EctoWatch,
   repo: MyApp.Repo,
   pub_sub: MyApp.PubSub,
   watchers: [
    {
      %{
        table_name: "comments",
        primary_key: :ID,
        columns: [:title, :body, :author_id, :post_id],
        association_columns: [:author_id, :post_id]
      }, :updated, extra_columns: [:post_id]
    }
   ]}
```

Everything works the same as with a schema, though make sure to specify your association columns if you want to subscribe to an association column.

Supported keys for configuring a table without a schema:

 * `schema_prefix` (optional, defaults to `public`)
 * `table_name` (required)
 * `primary_key` (optional, defaults to `id`)
 * `columns` (optional, defaults to `[]`)
 * `association_columns` (optional, defaults to `[]`)

## Notes

### Why only send the id and not the full record?

The main reason: The `pg_notify` function has a limit of 8000 characters and wasn't created to send full-records on updates.

Also if many updates are done in quick succession to the same record, subscribers will need to process all of the old results before getting to the newest one.  For example if a LiveView is a subscriber it may get 10 updates about a record to the browser.  If the LiveView has to make a query then it will be more likely to get the latest data.  Since LiveView doesn't send updates when nothing has changed in the view for the user, this will mean less traffic to the browsers.

### Why not send the values inside of a schema struct?

If an application were to take the extra data from an event and pass it to some other part of the app, it may seem like the missing fields were actually missing from the database.  Since the data sent due to `extra_columns` isn't a complete load of the record, it doesn't make sense to send the whole struct.

### Scaling of queries

If you have many processes which are subscribed to updates and each process makes a DB query on receiving the message this could lead to many queries.  You may solve this by creating a GenServer which listens for messages and then makes a single query to the database (e.g. every X milliseconds) to get all the records that need to be updated, passing them on via another `PubSub` message.

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
 * Creating a batch-processing GenServer to reduce queries to the database.
 * Make watchers more generic (?).  Don't need dependency on PubSub, but could make it an adapter or something
 * Allow for local broadcasting of Phoenix.PubSub messages

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `ecto_watch` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ecto_watch, "~> 0.8.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/ecto_watch>.

[^1]: more info about PubSub message standards:
  - Having a single topic (e.g. `users`) means that all messages are sent to all subscribers, which can be inefficient.
  - Having a topic per record (e.g. `users:1`, `users:2`, etc.) means that a subscriber needs to subscribe to every record, which can be inefficient.
  - There may be inconsistancy in pluralization of topics (e.g. a `user` vs. `packages` topics) which can be confusing and lead to bugs.
  - Having a message that is just `{:updated, id}` doesn't make it clear which schema was updated, using `{schema, id}` doesn't make it clear which operation happened.
