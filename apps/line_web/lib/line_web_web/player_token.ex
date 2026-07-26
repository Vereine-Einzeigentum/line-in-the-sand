defmodule LineWebWeb.PlayerToken do
  @moduledoc """
  Signed, expiring tokens that authenticate a websocket connection.

  Phase 0 authenticated sockets by passing the raw player UUID, which made the
  identifier itself the credential: whoever held it was that player, forever,
  with no expiry, rotation, or revocation. That became untenable once the
  gameplay journal started recording `actor_id` on every dispatch — the log
  would be a store of live credentials, and the world model is meant to read
  that log.

  These tokens separate identity from credential. The UUID goes back to being
  an identifier that is safe to log, broadcast in `who`, and feed to a model;
  the token is the credential, signed with the endpoint's `secret_key_base`
  and valid only for a bounded window.

  Note this authenticates *who is connecting*, not *what client they run*.
  Client attestation is neither achievable nor needed here: the dispatcher is
  server-authoritative, so a hostile client can submit commands but cannot
  fabricate events.
  """

  @salt "player socket auth"

  # Long enough that a playtester reconnecting after a break does not need a
  # new token; short enough that a leaked one stops working.
  @max_age 86_400

  @doc "Mint a token authenticating the given player id."
  def sign(player_id) when is_binary(player_id) do
    Phoenix.Token.sign(LineWebWeb.Endpoint, @salt, player_id)
  end

  @doc """
  Verify a token, returning the player id it authenticates.

  Returns `{:error, :expired}` past `max_age/0` and `{:error, :invalid}` for
  anything malformed or signed with a different key.
  """
  def verify(token) when is_binary(token) do
    Phoenix.Token.verify(LineWebWeb.Endpoint, @salt, token, max_age: @max_age)
  end

  def verify(_), do: {:error, :invalid}

  @doc "Token lifetime in seconds."
  def max_age, do: @max_age
end
