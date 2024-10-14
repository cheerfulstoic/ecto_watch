 * Support features of `CREATE TRIGGER`:
   * allow specifying a condition for when the trigger should fire
 * Allow watchers to support adapter pattern.  Potential adapters:
   * Phoenix PubSub (the default, would work like it does now)
   * GenStage producer
   * Creating a batch-processing GenServer to reduce queries to the database.
 * Allow for local broadcasting of Phoenix.PubSub messages

