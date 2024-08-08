
If you would like to get more than just the `id` from the record, you can use the `extra_columns` option.

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
  EctoWatch.subscribe({Comment, :deleted})

  # handling messages
  def handle_info({{Comment, :deleted}, %{id: id, post_id: post_id}}, socket) do
    Posts.refresh_cache(post_id)

    # ...
```

