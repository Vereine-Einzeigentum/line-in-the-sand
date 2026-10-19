defmodule LineCore.CommandRouter do
  @moduledoc """
  Single entry point for player command execution.

  Prefix/system commands dispatch directly. In-world commands resolve verb
  objects through the MOO inheritance search before invoking trusted Elixir.
  """

  alias LineCore.{Dispatcher, Parser, VerbSearch}

  def dispatch(actor_id, raw, opts \\ []) when is_binary(raw) do
    case Parser.parse(raw) do
      {:ok, verb_module, args} ->
        Dispatcher.dispatch(actor_id, verb_module, args, raw, opts)

      {:world, command} ->
        case VerbSearch.resolve(actor_id, command) do
          {:ok, match} ->
            Dispatcher.dispatch_resolved(
              actor_id,
              match.module,
              match.args,
              raw,
              match.context.dobj,
              match.context.iobj,
              opts
            )

          {:error, :no_matching_verb} ->
            {:error, :unknown_verb}

          {:error, reason} ->
            {:error, reason}
        end

      {:empty, _} ->
        {:error, :empty_command}
    end
  end
end
