defmodule LineCore.Socials do
  @moduledoc """
  Canonical sanctioned social/emote definitions.

  These are textual socials only. They never apply game effects. The leading
  dot syntax selects this namespace before ordinary verb resolution, so a
  social such as `.hi` can never be interpreted as a prefix for `hit`.

  This registry is intentionally data-driven so it can later be moved into
  world objects without changing the Social verb contract.
  """

  @socials %{
    "hi" => %{
      actor: "You wave hello.",
      room: "%A waves hello.",
      actor_target: "You wave hello to %T.",
      room_target: "%A waves hello to %T."
    },
    "wave" => %{
      actor: "You wave.",
      room: "%A waves.",
      actor_target: "You wave to %T.",
      room_target: "%A waves to %T."
    },
    "nod" => %{
      actor: "You nod.",
      room: "%A nods.",
      actor_target: "You nod to %T.",
      room_target: "%A nods to %T."
    },
    "shrug" => %{
      actor: "You shrug.",
      room: "%A shrugs.",
      actor_target: "You shrug at %T.",
      room_target: "%A shrugs at %T."
    },
    "grin" => %{
      actor: "You grin.",
      room: "%A grins.",
      actor_target: "You grin at %T.",
      room_target: "%A grins at %T."
    },
    "smile" => %{
      actor: "You smile.",
      room: "%A smiles.",
      actor_target: "You smile at %T.",
      room_target: "%A smiles at %T."
    },
    "bow" => %{
      actor: "You bow.",
      room: "%A bows.",
      actor_target: "You bow to %T.",
      room_target: "%A bows to %T."
    },
    "salute" => %{
      actor: "You salute.",
      room: "%A salutes.",
      actor_target: "You salute %T.",
      room_target: "%A salutes %T."
    }
  }

  @spec fetch(binary()) :: {:ok, map()} | :error
  def fetch(name) when is_binary(name) do
    case Map.fetch(@socials, String.downcase(String.trim(name))) do
      {:ok, social} -> {:ok, social}
      :error -> :error
    end
  end

  @spec render(map(), struct(), struct() | nil) :: {binary(), binary()}
  def render(social, actor, nil) do
    {
      render_template(social.actor, actor, nil),
      render_template(social.room, actor, nil)
    }
  end

  def render(social, actor, target) do
    {
      render_template(social.actor_target, actor, target),
      render_template(social.room_target, actor, target)
    }
  end

  def names, do: @socials |> Map.keys() |> Enum.sort()

  defp render_template(template, actor, target) do
    template
    |> String.replace("%A", actor.name)
    |> maybe_replace_target(target)
  end

  defp maybe_replace_target(text, nil), do: text
  defp maybe_replace_target(text, target), do: String.replace(text, "%T", target.name)
end
