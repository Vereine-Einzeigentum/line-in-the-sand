defmodule LineCore.PronounsTest do
  use ExUnit.Case, async: true

  alias LineCore.Pronouns

  describe "resolve/2" do
    test "she pronouns" do
      assert Pronouns.resolve("%P has tiny feet.", "she") == "She has tiny feet."
      assert Pronouns.resolve("%o face is scarred.", "she") == "her face is scarred."
      assert Pronouns.resolve("%O hands are calloused.", "she") == "Her hands are calloused."
    end

    test "he pronouns" do
      assert Pronouns.resolve("%P has tiny feet.", "he") == "He has tiny feet."
      assert Pronouns.resolve("%o face is scarred.", "he") == "his face is scarred."
    end

    test "they pronouns" do
      assert Pronouns.resolve("%P has tiny feet.", "they") == "They has tiny feet."
      assert Pronouns.resolve("%o face is scarred.", "they") == "their face is scarred."
    end

    test "it pronouns" do
      assert Pronouns.resolve("%P has tiny feet.", "it") == "It has tiny feet."
      assert Pronouns.resolve("%o face is scarred.", "it") == "its face is scarred."
    end

    test "nil defaults to they" do
      assert Pronouns.resolve("%P has tiny feet.", nil) == "They has tiny feet."
    end

    test "unknown key defaults to they" do
      assert Pronouns.resolve("%P walks.", "xey") == "They walks."
    end

    test "case insensitive key" do
      assert Pronouns.resolve("%P walks.", "She") == "She walks."
      assert Pronouns.resolve("%P walks.", "HE") == "He walks."
    end

    test "multiple tokens in one string" do
      assert Pronouns.resolve("%P adjusts %o collar.", "he") == "He adjusts his collar."
    end

    test "no tokens returns string unchanged" do
      assert Pronouns.resolve("Just plain text.", "she") == "Just plain text."
    end

    test "preserves unrecognized percent sequences" do
      assert Pronouns.resolve("%Z walks.", "she") == "%Z walks."
    end
  end

  describe "known_keys/0" do
    test "returns all pronoun set keys" do
      keys = Pronouns.known_keys()
      assert "she" in keys
      assert "he" in keys
      assert "they" in keys
      assert "it" in keys
    end
  end
end
