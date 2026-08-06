defmodule LineCore.Pronouns do
  @moduledoc """
  Pronoun token substitution for player-authored descriptions.

  Tokens: %P/%p (subject), %O/%o (possessive adjective).
  Resolved at render time based on the described object's `pronouns` property.
  """

  @pronoun_table %{
    "she"  => %{"P" => "She",  "p" => "she",  "O" => "Her",   "o" => "her"},
    "he"   => %{"P" => "He",   "p" => "he",   "O" => "His",   "o" => "his"},
    "they" => %{"P" => "They", "p" => "they",  "O" => "Their", "o" => "their"},
    "it"   => %{"P" => "It",   "p" => "it",   "O" => "Its",   "o" => "its"}
  }

  @default_key "they"

  @token_pattern ~r/%([POpo])/

  def resolve(template, nil), do: resolve(template, @default_key)

  def resolve(template, pronoun_key) when is_binary(template) and is_binary(pronoun_key) do
    set = Map.get(@pronoun_table, String.downcase(pronoun_key), @pronoun_table[@default_key])

    Regex.replace(@token_pattern, template, fn _, token ->
      Map.get(set, token, "%#{token}")
    end)
  end

  def known_keys, do: Map.keys(@pronoun_table)
end
