defmodule LineCore.BootstrapAdmin do
  @moduledoc """
  One-time, idempotent alpha bootstrap for an administrative login.

  This is deliberately transitional: the current auth system authenticates
  player objects directly, while the target architecture separates access
  identities from world bodies and gives moderators their own $mod ancestry.

  Re-running the bootstrap promotes an existing named login to admin but never
  rewrites its password. That lets a bootstrap secret be used for first deploy
  without becoming a standing password-reset mechanism.
  """

  alias LineCore.{Object, Repo}

  @role_key "account_role"
  @admin_key "admin"

  @spec ensure(binary(), binary(), keyword()) ::
          {:ok, {:created | :existing, LineCore.Schemas.Object.t()}} | {:error, term()}
  def ensure(name, password, opts \\ [])
      when is_binary(name) and is_binary(password) and is_list(opts) do
    name = String.trim(name)
    password = String.trim(password)
    email = opts |> Keyword.get(:email) |> normalize_optional()

    cond do
      name == "" ->
        {:error, :empty_name}

      password == "" ->
        {:error, :empty_password}

      true ->
        Repo.transaction(fn ->
          case Object.find_player_by_name(name) do
            nil ->
              create_admin!(name, password, email)

            admin ->
              mark_admin!(admin, email)
              {:existing, admin}
          end
        end)
    end
  end

  @doc """
  Bootstraps from environment variables.

  Required:
    * ADMIN_BOOTSTRAP_NAME
    * ADMIN_BOOTSTRAP_PASSWORD

  Optional:
    * ADMIN_BOOTSTRAP_EMAIL
  """
  @spec bootstrap_from_env() :: :skip | {:ok, {:created | :existing, LineCore.Schemas.Object.t()}}
  def bootstrap_from_env do
    name = System.get_env("ADMIN_BOOTSTRAP_NAME") |> normalize_optional()
    password = System.get_env("ADMIN_BOOTSTRAP_PASSWORD") |> normalize_optional()
    email = System.get_env("ADMIN_BOOTSTRAP_EMAIL") |> normalize_optional()

    if name && password do
      ensure(name, password, email: email)
    else
      :skip
    end
  end

  defp create_admin!(name, password, email) do
    hash = Bcrypt.hash_pwd_salt(password)

    admin =
      case Object.create(:player, name) do
        {:ok, player} -> player
        {:error, reason} -> Repo.rollback(reason)
      end

    put!(admin.id, "password_hash", hash)
    put!(admin.id, "temp_password", false)
    mark_admin!(admin, email)

    {:created, admin}
  end

  defp mark_admin!(admin, email) do
    put!(admin.id, @role_key, "admin")
    put!(admin.id, @admin_key, true)

    if email do
      put!(admin.id, "email", email)
    end

    :ok
  end

  defp put!(object_id, key, value) do
    case Object.set_property(object_id, key, value) do
      {:ok, _property} -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp normalize_optional(nil), do: nil

  defp normalize_optional(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
