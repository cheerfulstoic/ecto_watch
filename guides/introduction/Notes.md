### Dealing with leftover PostgreSQL triggers

Because of the nature of delegating to a trigger in PostgreSQL, you can end up with leftover triggers and functions in the database (e.g. if you remove a watcher or change a watcher's label).  If you have `EctoWatch` in your application tree (even with an empty list of watchers) it will (starting in version `0.9.0`) output (error-level) logs to warn you about any extra triggers and functions.  If you would like to clean these up you can start your application with the `ECTO_WATCH_CLEANUP` environment variable set to `cleanup` and `EctoWatch` will delete any triggers and functions which wouldn't be created by the current watcher configuration.

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

