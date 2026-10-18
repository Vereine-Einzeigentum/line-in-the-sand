defmodule LineCore.CommandRouter do
  @moduledoc """
  Single entry point for player command execution.

  Prefix/system commands dispatch directly. In-world commands resolve verb
  objects through the MOO inheritance search before invoking trusted Elixir.
  """

  alias LineCore.{Dispatcher, Parser, VerbSearch}

  def dispatch(actor_id, raw) when is_binary(raw) do
    case Parser.parse(raw) do
      {:ok, verb_module, args} ->
        Dispatcher.dispatch(actor_id, verb_module, args, raw)

      {:world, command} ->
        with {:ok, match} <- VerbSearch.resolve(actor_id, command) do
          Dispatcher.dispatch_resolved(
            actor_id,
            match.module,
            match.args,
            raw,
            match.context.dobj,
            match.context.iobj
          )
        end

      {:empty, _} ->
        :ok
    end
  end
end
