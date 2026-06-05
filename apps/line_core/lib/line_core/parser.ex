defmodule LineCore.Parser do
  @moduledoc """
  Translates raw command strings into `{verb_module, args}` tuples.

  The parser is the entry point for any text-based input — websocket commands,
  the HTTP playtest API's `raw` field, etc. It handles:

  - Verb aliases (`k`/`kill`/`attack`/`hit` → Attack)
  - Bare directions (`n`, `north` → Go with that direction)
  - Speak prefix (`"hello there` → Say "hello there")
  - Multi-word arguments (`get rusty knife` → Get with arg "rusty knife")
  - Two-object syntax (`use knife on door` → reserved, currently unparsed)
  - Hand specification (`wield knife main`, `hold pistol off`)

  Unknown verbs fall through to a generic `:unknown` result. The caller decides
  whether to route those to the narrative LM (Phase 1+) or return an error.

  ## Returns

      {:ok, verb_module, args}    — successful parse
      {:unknown, verb, raw_input} — verb not recognized
      {:empty, _}                 — empty input
  """

  alias LineCore.Verbs

  @directions ~w(n north s south e east w west u up d down ne northeast nw northwest se southeast sw southwest in out)

  # Verb aliases → canonical verb module.
  # Extend this map as new verbs ship.
  @verb_map %{
    # Look
    "look" => Verbs.Look,
    "l" => Verbs.Look,

    # Examine
    "examine" => Verbs.Examine,
    "ex" => Verbs.Examine,
    "x" => Verbs.Examine,

    # Movement
    "go" => Verbs.Go,
    "move" => Verbs.Go,

    # Inventory
    "inventory" => Verbs.Inventory,
    "inv" => Verbs.Inventory,
    "i" => Verbs.Inventory,

    # Get
    "get" => Verbs.Get,
    "grab" => Verbs.Get,
    "gather" => Verbs.Get,
    "pickup" => Verbs.Get,
    "take" => Verbs.Get,

    # Drop
    "drop" => Verbs.Drop,
    "leave" => Verbs.Drop,
    "put" => Verbs.Drop,
    "discard" => Verbs.Drop,

    # Communication
    "say" => Verbs.Say,
    "text" => Verbs.Text,
    "txt" => Verbs.Text,
    "tell" => Verbs.Text,

    # Identity
    "who" => Verbs.Who,
    "desc" => Verbs.Desc,
    "describe" => Verbs.Desc
  }

  @doc """
  Parse a raw command string.

  Returns `{:ok, module, args}` on success.
  """
  def parse(input) when is_binary(input) do
    trimmed = String.trim(input)

    cond do
      trimmed == "" ->
        {:empty, ""}

      # Speak prefix: " starts a say
      String.starts_with?(trimmed, "\"") ->
        message = String.trim_leading(trimmed, "\"") |> String.trim()
        {:ok, Verbs.Say, [message]}

      # Bare direction: "n", "north", "ne" → Go
      String.downcase(trimmed) in @directions ->
        {:ok, Verbs.Go, [String.downcase(trimmed)]}

      true ->
        parse_verb(trimmed)
    end
  end

  ## Internal

  defp parse_verb(input) do
    {verb, rest} = split_verb(input)
    verb_down = String.downcase(verb)

    case Map.get(@verb_map, verb_down) do
      nil ->
        {:unknown, verb_down, input}

      module ->
        args = parse_args(module, rest)
        {:ok, module, args}
    end
  end

  defp split_verb(input) do
    case String.split(input, " ", parts: 2) do
      [verb] -> {verb, ""}
      [verb, rest] -> {verb, String.trim(rest)}
    end
  end

  # Argument parsing per verb.
  defp parse_args(_module, ""), do: []

  defp parse_args(Verbs.Text, rest) do
    # text <player> <message>
    case String.split(rest, " ", parts: 2) do
      [target] -> [target]
      [target, message] -> [target, message]
    end
  end

  defp parse_args(Verbs.Desc, rest) do
    # desc me as <description>  →  [description]
    # desc <object> as <description>  →  [object, description]
    case Regex.run(~r/^(.+?)\s+as\s+(.+)$/i, rest) do
      [_, "me", description] -> [description]
      [_, "self", description] -> [description]
      [_, object, description] -> [object, description]
      _ -> [rest]
    end
  end

  defp parse_args(Verbs.Who, rest) do
    # who → no args (list everyone)
    # who <player> → single arg
    case rest do
      "" -> []
      name -> [name]
    end
  end

  defp parse_args(Verbs.Go, rest) do
    # go <direction>
    [String.downcase(rest)]
  end

  defp parse_args(Verbs.Inventory, _rest), do: []

  defp parse_args(_module, rest) do
    # Default: single string arg with multi-word content preserved.
    [rest]
  end

  @doc "Get the full verb map (for introspection / testing)."
  def verb_map, do: @verb_map

  @doc "Get the canonical verb names (deduplicated module list)."
  def known_verbs, do: @verb_map |> Map.values() |> Enum.uniq()
end
