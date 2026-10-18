defmodule LineCore.Container do
  @moduledoc """
  Generic containment rules shared by container verbs.

  Containers are ordinary objects. Accessibility is local/inherited object
  state; no corpse-, bag-, locker-, or robot-specific subsystem is involved.
  """

  alias LineCore.Object

  def accessible?(container_id) do
    cond do
      Object.get_property(container_id, "locked", false) == true ->
        {:error, :container_locked}

      Object.get_property(container_id, "open", true) == false ->
        {:error, :container_closed}

      true ->
        :ok
    end
  end

  def would_cycle?(object_id, container_id) do
    object_id == container_id or Object.contained_by?(container_id, object_id)
  end
end
