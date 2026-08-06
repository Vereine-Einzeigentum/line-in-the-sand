defmodule LineCore.Verbs.Bare do
  @behaviour LineCore.Verb

  @body_parts ~w(head face neck torso arms hands waist legs feet back)

  def body_parts, do: @body_parts

  @impl true
  def execute(_ctx, []), do: {:error, :bare_what}

  def execute(ctx, [body_part, description]) when is_binary(body_part) and is_binary(description) do
    part = body_part |> String.trim() |> String.downcase()
    desc = String.trim(description)

    cond do
      part not in @body_parts ->
        {:ok, [{:notify_actor, "Not a body part. Options: #{Enum.join(@body_parts, ", ")}"}]}

      desc == "" ->
        {:error, :empty_description}

      true ->
        {:ok,
         [
           {:set_property, ctx.actor.id, "bare:#{part}", desc},
           {:notify_actor, "You set your #{part} description."}
         ]}
    end
  end

  def execute(_ctx, [_body_part]), do: {:error, :bare_as_what}

  def execute(_ctx, _args), do: {:error, :bad_args}
end
