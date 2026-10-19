defmodule LineCore.Adminland do
  @moduledoc """
  The isolated one-tile administrative space.

  Adminland is a real room in the object graph, but it has no exits and is
  marked as system/admin-only space. Administrative logins are loaded here
  explicitly; ordinary players are never moved here by this module.
  """

  import Ecto.Query

  alias LineCore.{Object, Repo}
  alias LineCore.Schemas.Object, as: ObjSchema

  @name "ADMINLAND"

  @spec ensure() :: {:ok, struct()} | {:error, term()}
  def ensure do
    case existing_room() do
      nil ->
        with {:ok, room} <-
               Object.create(:room, @name, %{
                 description:
                   "A single administrative tile outside the ordinary world graph. No exits. No scenery. Just the controls."
               }),
             {:ok, _} <- Object.set_property(room.id, "admin_only", true),
             {:ok, _} <- Object.set_property(room.id, "system_space", true),
             {:ok, _} <- Object.set_property(room.id, "map_tile", "adminland") do
          {:ok, room}
        end

      room ->
        # Keep the semantic markers repaired if an older seed omitted them.
        with {:ok, _} <- Object.set_property(room.id, "admin_only", true),
             {:ok, _} <- Object.set_property(room.id, "system_space", true),
             {:ok, _} <- Object.set_property(room.id, "map_tile", "adminland") do
          {:ok, room}
        end
    end
  end

  @spec load_if_admin(binary()) :: :not_admin | {:ok, struct()} | {:error, term()}
  def load_if_admin(player_id) when is_binary(player_id) do
    if Object.get_property(player_id, "admin") == true do
      with {:ok, room} <- ensure(),
           :ok <- move_to_room(player_id, room.id) do
        {:ok, room}
      end
    else
      :not_admin
    end
  end

  defp move_to_room(player_id, room_id) do
    case Object.container_of(player_id) do
      %{id: ^room_id} ->
        :ok

      nil ->
        case Object.relate(room_id, player_id, :contains) do
          {:ok, _relationship} -> :ok
          {:error, reason} -> {:error, reason}
        end

      _other ->
        case Object.move(player_id, room_id) do
          {:ok, {:ok, _relationship}} -> :ok
          {:ok, _other_result} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp existing_room do
    from(o in ObjSchema,
      where: o.type == :room and o.name == ^@name and is_nil(o.deleted_at),
      limit: 1
    )
    |> Repo.one()
  end
end
