defmodule LineCore.Verbs.Password do
  @behaviour LineCore.Verb

  @min_password 8

  @impl true
  def execute(_ctx, []), do: {:error, :password_what}

  def execute(ctx, [new_password]) when is_binary(new_password) do
    trimmed = String.trim(new_password)

    cond do
      String.length(trimmed) < @min_password ->
        {:ok, [{:notify_actor, "Password must be at least #{@min_password} characters."}]}

      true ->
        hash = Bcrypt.hash_pwd_salt(trimmed)

        {:ok,
         [
           {:set_property, ctx.actor.id, "password_hash", hash},
           {:set_property, ctx.actor.id, "temp_password", false},
           {:notify_actor, "Password changed."}
         ]}
    end
  end

  def execute(_ctx, _args), do: {:error, :bad_args}
end
