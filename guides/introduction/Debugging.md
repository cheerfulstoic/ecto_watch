It is possible to get debug logs from EctoWatch by setting the `debug?` option, either globally:

```elixir
  # setup
  {EctoWatch,
   repo: MyApp.Repo,
   pub_sub: MyApp.PubSub,
   debug?: true
   watchers: [
     # ...
     {Comment, :deleted, extra_columns: [:post_id]},
     # ...
   ]}
```

Or on specific watchers:

```elixir
  # setup
  {EctoWatch,
   repo: MyApp.Repo,
   pub_sub: MyApp.PubSub,
   watchers: [
     # ...
     {Comment, :deleted, debug?: true, extra_columns: [:post_id]},
     # ...
   ]}
```

Debug logs will be written to the `:debug` log level.  They will output when:

 * A watcher server is starting up
 * A watcher server receives a message from PostgreSQL via a `pg_notify` channel
 * A watcher server broadcasts a message to `Phoenix.PubSub`
 * A process subscribes to a watcher

All debug logs have a PID associated as well as the identifier for the watcher server (either the label or a `{ecto_schema, update_type}` tuple).
