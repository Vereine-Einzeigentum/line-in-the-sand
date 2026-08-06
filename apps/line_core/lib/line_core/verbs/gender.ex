defmodule LineCore.Verbs.Gender do
  @behaviour LineCore.Verb

  alias LineCore.Pronouns

  @impl true
  def execute(_ctx, []), do: {:error, :gender_what}

  def execute(ctx, [gender]) when is_binary(gender) do
    key = gender |> String.trim() |> String.downcase()

    if key in Pronouns.known_keys() do
      {:ok,
       [
         {:set_property, ctx.actor.id, "pronouns", key},
         {:notify_actor, "Pronouns set to #{key}."}
       ]}
    else
      known = Pronouns.known_keys() |> Enum.join(", ")
      {:ok, [{:notify_actor, "Unknown gender. Options: #{known}"}]}
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}
end
