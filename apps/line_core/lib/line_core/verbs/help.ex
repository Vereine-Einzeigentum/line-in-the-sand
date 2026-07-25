defmodule LineCore.Verbs.Help do
  @moduledoc """
  `help` — list all available commands.
  `help <verb>` — show details for a specific verb.

  Pure: produces a single notify_actor event with the help text.
  """

  @behaviour LineCore.Verb

  alias LineCore.Parser

  @impl true
  def execute(_ctx, []) do
    # Bare help: list all available verbs
    verbs = available_verbs()
    verb_list = Enum.map_join(verbs, ", ", &"`#{&1}`")
    text = "Available commands: #{verb_list}. Type `help <command>` for details."
    {:ok, [{:notify_actor, text}]}
  end

  def execute(_ctx, [verb_name]) do
    verb_down = String.downcase(verb_name)

    case verb_for_name(verb_down) do
      nil ->
        {:error, :unknown_verb}

      verb_module ->
        text = verb_help_text(verb_module)
        {:ok, [{:notify_actor, text}]}
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}

  ## Helpers

  # Get unique verb aliases from the Parser's verb_map
  defp available_verbs do
    Parser.verb_map()
    |> Map.keys()
    |> Enum.uniq()
    |> Enum.sort()
  end

  # Look up a verb module by name/alias
  defp verb_for_name(name_down) do
    Map.get(Parser.verb_map(), name_down)
  end

  # Get help text for a verb module
  # Try to fetch @moduledoc via Code.fetch_docs/1, fallback to descriptions map
  defp verb_help_text(verb_module) do
    case fetch_moduledoc(verb_module) do
      {:ok, doc} -> doc
      :error -> descriptions()[verb_module] || "No documentation available."
    end
  end

  # Try to fetch the @moduledoc from a verb module
  defp fetch_moduledoc(module) do
    case Code.fetch_docs(module) do
      {:ok, {_line, _kind, _format, doc_content}} ->
        # Extract text from the moduledoc structure
        # doc_content is a list of tuples; we want the text from the first entry
        case Enum.find(doc_content, fn {_type, _meta, _content} -> true end) do
          {_, _, content} when is_binary(content) ->
            {:ok, content}

          _ ->
            :error
        end

      _ ->
        :error
    end
  rescue
    _ -> :error
  end

  # Fallback descriptions for verbs without @moduledoc
  defp descriptions do
    %{
      LineCore.Verbs.Look => "Look around the current room and nearby items.",
      LineCore.Verbs.Examine => "Examine an object in detail.",
      LineCore.Verbs.Go => "Move in a direction (n, s, e, w, u, d, etc.).",
      LineCore.Verbs.Inventory => "Check your inventory.",
      LineCore.Verbs.Get => "Pick up an item.",
      LineCore.Verbs.Drop => "Drop an item from your inventory.",
      LineCore.Verbs.Say => "Say something aloud to others in the room.",
      LineCore.Verbs.Emote => "Perform an emote or action.",
      LineCore.Verbs.Text => "Send a private message to another player.",
      LineCore.Verbs.Who => "See who else is playing.",
      LineCore.Verbs.Desc => "Describe yourself or an object.",
      LineCore.Verbs.Attack => "Attack another creature or player.",
      LineCore.Verbs.Wield => "Wield a weapon in your main or off hand.",
      LineCore.Verbs.Unwield => "Stop wielding a weapon.",
      LineCore.Verbs.Scrap => "Scrap an item for resources.",
      LineCore.Verbs.Sell => "Sell an item to an NPC.",
      LineCore.Verbs.Give => "Give an item to another player.",
      LineCore.Verbs.Score => "Check your character statistics.",
      LineCore.Verbs.Help => "Display this help text."
    }
  end
end
