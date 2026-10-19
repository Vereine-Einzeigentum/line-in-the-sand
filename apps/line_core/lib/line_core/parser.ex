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
    "commands" => Verbs.Help,
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
    "@addalias" => Verbs.BuilderAddAlias,
    "@rmalias" => Verbs.BuilderRmAlias,
    "@aliases" => Verbs.BuilderAliases,
    "@property" => Verbs.BuilderProperty,
    "@prop" => Verbs.BuilderProperty,
    "@rmproperty" => Verbs.BuilderRmProperty,
    "@rmprop" => Verbs.BuilderRmProperty,
    "@create" => Verbs.BuilderCreate,
    "@dig" => Verbs.BuilderDig,
    "@open" => Verbs.BuilderOpen,
    "@link" => Verbs.BuilderLink,
    "@unlink" => Verbs.BuilderUnlink,
    "@examine" => Verbs.BuilderInspect,
    "@show" => Verbs.BuilderInspect,
    "@display" => Verbs.BuilderInspect,
    "@contents" => Verbs.BuilderContents,
    "@parents" => Verbs.BuilderParents,
    "@parent" => Verbs.BuilderParents,
    "@kids" => Verbs.BuilderKids,
    "@children" => Verbs.BuilderKids,
    "@verbs" => Verbs.BuilderVerbs,
    "@properties" => Verbs.BuilderProperties,
    "@props" => Verbs.BuilderProperties,
    "@owned" => Verbs.BuilderAudit,
    "@chparent" => Verbs.BuilderChparent,
    "@set" => Verbs.BuilderSet,
    "@clear" => Verbs.BuilderClear,
    "@count" => Verbs.BuilderCount,
    "@audit" => Verbs.BuilderAudit,
    "@classes" => Verbs.BuilderClasses,
    "@quota" => Verbs.BuilderQuota,
    "@move" => Verbs.BuilderMove,
    "@eject" => Verbs.BuilderEject,
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

        case system_module(verb_down) do
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
    generic_world_command(verb, rest, raw)
  end

  defp build_world_command(verb, rest, raw) do
    generic_world_command(verb, rest, raw)
  end

  defp generic_world_command(verb, rest, raw) do
    case split_preposition(rest) || split_leading_preposition(rest) do
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
      ~r/^(.+?)\s+(in front of|on top of|from inside|out of|off of|underneath|beneath|inside|into|onto|upon|using|with|through|under|behind|beside|about|for|over|from|off|on|in|at|to|is|as)\s+(.+)$/i

    case Regex.run(pattern, rest) do
      [_, dobj, prep, iobj] ->
        {String.trim(dobj), canonical_prep(prep), String.trim(iobj)}

      _ ->
        nil
    end
  end

  defp split_leading_preposition(""), do: nil

  defp split_leading_preposition(rest) do
    pattern =
      ~r/^(in front of|on top of|from inside|out of|off of|underneath|beneath|inside|into|onto|upon|using|with|through|under|behind|beside|about|for|over|from|off|on|in|at|to|is|as)\s+(.+)$/i

    case Regex.run(pattern, rest) do
      [_, prep, iobj] ->
        {nil, canonical_prep(prep), String.trim(iobj)}

      _ ->
        nil
    end
  end

  defp canonical_prep(prep) do
    case String.downcase(prep) do
      p when p in ["inside", "into", "in"] -> "in"
      p when p in ["on top of", "onto", "upon", "on"] -> "on"
      p when p in ["using", "with"] -> "with"
      p when p in ["out of", "from inside", "from"] -> "from"
      p when p in ["off of", "off"] -> "off"
      p when p in ["underneath", "beneath", "under"] -> "under"
      p when p in ["about", "for"] -> "for"
      "in front of" -> "in front of"
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

  defp parse_system_args(module, rest) when module in [Verbs.BuilderMove, Verbs.BuilderLink] do
    case Regex.run(~r/^(.+?)\s+to\s+(.+)$/i, rest) do
      [_, object, destination] -> [String.trim(object), String.trim(destination)]
      _ -> [rest]
    end
  end

  defp parse_system_args(module, rest) when module in [Verbs.BuilderDig, Verbs.BuilderOpen] do
    case Regex.run(~r/^(.+?)\s+to\s+(.+)$/i, rest) do
      [_, exit_spec, destination] ->
        [String.trim(exit_spec), strip_quotes(destination)]

      _ ->
        [strip_quotes(rest)]
    end
  end

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

  defp system_module(verb) do
    case Map.fetch(@system_map, verb) do
      {:ok, module} ->
        module

      :error ->
        if String.starts_with?(verb, "@") do
          matches =
            @system_map
            |> Enum.filter(fn {name, _module} -> String.starts_with?(name, verb) end)
            |> Enum.map(fn {_name, module} -> module end)
            |> Enum.uniq()

          case matches do
            [module] -> module
            _ -> nil
          end
        end
    end
  end

  def verb_map, do: @system_map

  def known_verbs do
    (@system_map |> Map.values()) ++ [Verbs.Say, Verbs.Emote, Verbs.Social]
    |> Enum.uniq()
  end
end
