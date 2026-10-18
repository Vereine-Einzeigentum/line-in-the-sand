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
        case {command.dobjstr, command.iobjstr} do
          {nil, _} -> []
          {item, nil} -> [item]
          {item, buyer} -> [item, buyer]
        end

      _ ->
        maybe_one(command.argstr)
    end
  end

  defp target_text(command), do: command.dobjstr || command.iobjstr

  defp maybe_one(nil), do: []
  defp maybe_one(""), do: []
  defp maybe_one(value), do: [value]
end
