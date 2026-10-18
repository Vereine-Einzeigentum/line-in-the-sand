defmodule LineCore.VerbInvocation do
  @moduledoc false

  def args(definition, command) do
    case definition.arg_mode do
      "none" ->
        []

      "rest" ->
        maybe_one(command.argstr)

      "target_optional" ->
        maybe_one(target_text(command))

      "target_required" ->
        maybe_one(target_text(command))

      "wield" ->
        case {command.dobjstr, command.modifier} do
          {nil, _} -> []
          {target, nil} -> [target]
          {target, hand} -> [target, hand]
        end

      "sell" ->
        object_pair(command)

      "container_get" ->
        object_pair(command)

      "container_put" ->
        object_pair(command)

      "object_pair" ->
        object_pair(command)

      _ ->
        maybe_one(command.argstr)
    end
  end

  defp object_pair(command) do
    case {command.dobjstr, command.iobjstr} do
      {nil, _} -> []
      {item, nil} -> [item]
      {item, container} -> [item, container]
    end
  end

  defp target_text(command), do: command.dobjstr || command.iobjstr

  defp maybe_one(nil), do: []
  defp maybe_one(""), do: []
  defp maybe_one(value), do: [value]
end
