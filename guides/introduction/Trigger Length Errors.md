`ecto_watch` uses functions and triggers to do it's work.  In PostgreSQL functions and triggers have names and those names are limited to a certain size.  By default `ecto_watch` will auto-generate these names for you, but if your module name is too long you can get the following error:

```text
              Schema module name is XXX character(s) too long for the auto-generated Postgres trigger name.

              You may want to use the `label` option
```

If you use the `label` option you'll need to change your subscriptions and `handle_info` callbacks to use the label.  See [the docs] for more information about using labels.

If your label is too long, you'll get the following error:

```text
              Label is XXX character(s) too long to be part of the Postgres trigger name.

```
