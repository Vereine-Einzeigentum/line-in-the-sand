defmodule LineCore.Parser do
  @moduledoc """
  Splits input into system commands or structured in-world commands.

  System commands remain a deliberately small registry. Ordinary game verbs
  are not mapped to Elixir modules here; they are resolved from verb objects
  attached to the world inheritance tree.
  """

  alias LineCore.{Verbs, WorldCommand}

  @directions ~w(n north s south e east w west u up d down ne northeast nw northwest se southeast sw southwest in out)

  @system_map %{
    "help" => Verbs.Help,
    "info" => Verbs.Help,
    "information" => Verbs.Help,
    "?" => Verbs.Help,
    "text" => Verbs.Text,
    "txt" => Verbs.Text,
    "tell" => Verbs.Text,
    "page" => Verbs.Page,
    "whereis" => Verbs.WhereIs,
    "who" => Verbs.Who,
    "@who" => Verbs.Who,
    "@desc" => Verbs.Desc,
    "@describe" => Verbs.Desc,
    "@rename" => Verbs.Rename,
    "@create" => Verbs.BuilderCreate,
    "@dig" => Verbs.BuilderDig,
    "@count" => Verbs.BuilderCount,
    "@audit" => Verbs.BuilderAudit,
    "@classes" => Verbs.BuilderClasses,
    "@quota" => Verbs.BuilderQuota,
    "@move" => Verbs.BuilderMove,
    "@open" => Verbs.BuilderOpen,
    "@recycle" => Verbs.BuilderRecycle,
    "@bare" => Verbs.Bare,
    "@gender" => Verbs.Gender,
    "@password" => Verbs.Password
  }

  def parse(input) when is_binary(input) do
    trimmed = String.trim(input)

    cond do
      trimmed == "" ->
        {:empty, ""}

      String.starts_with?(trimmed, "\"") ->
        message = String.trim_leading(trimmed, "\"") |> String.trim()
        {:ok, Verbs.Say, [message]}

      String.starts_with?(trimmed, ":") ->
        pose = String.trim_leading(trimmed, ":") |> String.trim()
        {:ok, Verbs.Emote, [pose]}

      String.starts_with?(trimmed, ".") ->
        parse_social(trimmed)

      String.downcase(trimmed) in @directions ->
        {:ok, command} = parse_world(trimmed)
        {:world, command}

      true ->
        {verb, rest} = split_verb(trimmed)
        verb_down = String.downcase(verb)

        case Map.get(@system_map, verb_down) do
          nil ->
            {:ok, command} = parse_world(trimmed)
            {:world, command}

          module ->
            {:ok, module, parse_system_args(module, rest)}
        end
    end
  end

  @doc "Parse any ordinary in-world command without consulting the system registry."
  def parse_world(input) when is_binary(input) do
    raw = String.trim(input)

    cond do
      raw == "" ->
        {:error, :empty_command}

      String.downcase(raw) in @directions ->
        direction = String.downcase(raw)

        {:ok,
         %WorldCommand{
           verb: "go",
           argstr: direction,
           dobjstr: nil,
           prepstr: nil,
           iobjstr: nil,
           modifier: nil,
           raw: raw
         }}

      true ->
        {verb, rest} = split_verb(raw)
        {:ok, build_world_command(String.downcase(verb), rest, raw)}
    end
  end

  defp build_world_command(verb, rest, raw) when verb in ["go", "move"] do
    %WorldCommand{
      verb: verb,
      argstr: String.downcase(rest),
      raw: raw
    }
  end

  defp build_world_command(verb, rest, raw) when verb in ["inventory", "inv", "i"] do
    %WorldCommand{verb: verb, argstr: rest, raw: raw}
  end

  defp build_world_command(verb, rest, raw) when verb in ["wield", "hold", "equip"] do
    {target, modifier} =
      case Regex.run(~r/^(.+?)\s+(main|off)$/i, rest) do
        [_, target, hand] -> {String.trim(target), String.downcase(hand)}
        _ -> {blank_to_nil(rest), nil}
      end

    %WorldCommand{
      verb: verb,
      argstr: rest,
      dobjstr: target,
      modifier: modifier,
      raw: raw
    }
  end

  defp build_world_command(verb, rest, raw) when verb in ["sell", "fence"] do
    case Regex.run(~r/^(.+?)\s+(to|at)\s+(.+)$/i, rest) do
      [_, dobj, prep, iobj] ->
        %WorldCommand{
          verb: verb,
          argstr: rest,
          dobjstr: String.trim(dobj),
          prepstr: String.downcase(prep),
          iobjstr: String.trim(iobj),
          raw: raw
        }

      _ ->
        %WorldCommand{verb: verb, argstr: rest, dobjstr: blank_to_nil(rest), raw: raw}
    end
  end

  defp build_world_command(verb, rest, raw) when verb in ["look", "l"] do
    cond do
      match = Regex.run(~r/^at\s+(.+)$/i, rest) ->
        [_, target] = match

        %WorldCommand{
          verb: verb,
          argstr: rest,
          dobjstr: String.trim(target),
          prepstr: "at",
          raw: raw
        }

      match = Regex.run(~r/^in(?:side)?\s+(.+)$/i, rest) ->
        [_, target] = match

        %WorldCommand{
          verb: verb,
          argstr: rest,
          dobjstr: nil,
          prepstr: "in",
          iobjstr: String.trim(target),
          raw: raw
        }

      true ->
        generic_world_command(verb, rest, raw)
    end
  end

  defp build_world_command(verb, rest, raw) do
    generic_world_command(verb, rest, raw)
  end

  defp generic_world_command(verb, rest, raw) do
    case split_preposition(rest) do
      {dobj, prep, iobj} ->
        %WorldCommand{
          verb: verb,
          argstr: rest,
          dobjstr: dobj,
          prepstr: prep,
          iobjstr: iobj,
          raw: raw
        }

      nil ->
        %WorldCommand{
          verb: verb,
          argstr: rest,
          dobjstr: blank_to_nil(rest),
          raw: raw
        }
    end
  end

  defp split_preposition(""), do: nil

  defp split_preposition(rest) do
    pattern =
      ~r/^(.+?)\s+(to|at|in|inside|into|on|onto|upon|with|using|from|out of|from inside|off|off of)\s+(.+)$/i

    case Regex.run(pattern, rest) do
      [_, dobj, prep, iobj] ->
        {String.trim(dobj), canonical_prep(prep), String.trim(iobj)}

      _ ->
        nil
    end
  end

  defp canonical_prep(prep) do
    case String.downcase(prep) do
      p when p in ["inside", "into", "in"] -> "in"
      p when p in ["onto", "upon", "on"] -> "on"
      p when p in ["using", "with"] -> "with"
      p when p in ["out of", "from inside", "from"] -> "from"
      p when p in ["off of", "off"] -> "off"
      other -> other
    end
  end

  defp parse_social(input) do
    body = input |> String.trim_leading(".") |> String.trim()

    case String.split(body, ~r/\s+/, parts: 2, trim: true) do
      [] -> {:ok, Verbs.Social, []}
      [name] -> {:ok, Verbs.Social, [String.downcase(name)]}
      [name, target] -> {:ok, Verbs.Social, [String.downcase(name), String.trim(target)]}
    end
  end

  defp split_verb(input) do
    case String.split(input, ~r/\s+/, parts: 2, trim: true) do
      [verb] -> {verb, ""}
      [verb, rest] -> {verb, String.trim(rest)}
    end
  end

  defp parse_system_args(_module, ""), do: []

  defp parse_system_args(module, rest) when module in [Verbs.Text, Verbs.Page] do
    case String.split(rest, ~r/\s+/, parts: 2, trim: true) do
      [] -> []
      [target] -> [target]
      [target, message] -> [target, message]
    end
  end

  defp parse_system_args(Verbs.Desc, rest) do
    case Regex.run(~r/^(.+?)\s+as\s+(.+)$/i, rest) do
      [_, "me", description] -> [description]
      [_, "self", description] -> [description]
      [_, object, description] -> [object, description]
      _ -> [rest]
    end
  end

  defp parse_system_args(Verbs.Who, rest), do: [rest]

  defp parse_system_args(Verbs.Rename, rest) do
    case Regex.run(~r/^(.+?)\s+to\s+(.+)$/i, rest) do
      [_, object, name] -> [String.trim(object), strip_quotes(name)]
      _ -> [rest]
    end
  end

  defp parse_system_args(Verbs.BuilderCreate, rest) do
    case Regex.run(~r/^(\S+)\s+named\s+(.+)$/i, rest) do
      [_, parent, name] -> [String.downcase(parent), strip_quotes(name)]
      _ -> [rest]
    end
  end

  defp parse_system_args(module, rest) when module in [Verbs.BuilderMove, Verbs.BuilderOpen] do
    case Regex.run(~r/^(.+?)\s+to\s+(.+)$/i, rest) do
      [_, object, destination] -> [String.trim(object), String.trim(destination)]
      _ -> [rest]
    end
  end

  defp parse_system_args(Verbs.BuilderDig, rest), do: [strip_quotes(rest)]

  defp parse_system_args(Verbs.Bare, rest) do
    case Regex.run(~r/^(.+?)\s+as\s+(.+)$/i, rest) do
      [_, part, description] -> [part, description]
      _ -> [rest]
    end
  end

  defp parse_system_args(Verbs.Gender, rest) do
    case Regex.run(~r/^me\s+as\s+(.+)$/i, rest) do
      [_, gender] -> [gender]
      _ -> []
    end
  end

  defp parse_system_args(Verbs.Password, rest) do
    case Regex.run(~r/^me\s+as\s+(.+)$/i, rest) do
      [_, password] -> [password]
      _ -> []
    end
  end

  defp parse_system_args(_module, rest), do: [rest]

  defp strip_quotes(value) do
    value
    |> String.trim()
    |> String.trim_leading(~s("))
    |> String.trim_trailing(~s("))
  end

  defp blank_to_nil(value) do
    case String.trim(value) do
      "" -> nil
      text -> text
    end
  end

  def verb_map, do: @system_map

  def known_verbs do
    (@system_map |> Map.values()) ++ [Verbs.Say, Verbs.Emote, Verbs.Social]
    |> Enum.uniq()
  end
end
