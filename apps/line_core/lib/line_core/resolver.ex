defmodule LineCore.Resolver do
  @moduledoc """
  Shared visible-object resolution for command verbs.

  Resolution scope is deliberately local:
  - `self` / `me` -> actor
  - `here` -> current room
  - current room by name
  - objects in the current room
  - objects directly carried by the actor

  This is the first common resolver behind MOO-style direct-object commands.
  """

  alias LineCore.Object

  @spec visible(struct(), binary()) :: struct() | nil
  def visible(ctx, name) when is_binary(name) do
    normalized = name |> String.trim() |> String.downcase()

    case normalized do
      "self" ->
        ctx.actor

      "me" ->
        ctx.actor

      "here" ->
        ctx.room

      _ ->
        Object.find_by_name([ctx.room], name) ||
          Object.find_by_name(ctx.room_contents, name) ||
          Object.find_by_name(Object.contents(ctx.actor.id), name)
    end
  end

  @doc "Resolve a named object directly inside a specific container."
  def within(container, name) when is_binary(name) do
    container.id
    |> Object.contents()
    |> Object.find_by_name(name)
  end
end
