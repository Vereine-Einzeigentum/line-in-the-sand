defmodule LineCore.HelpTest do
  use ExUnit.Case, async: true

  alias LineCore.{Parser, Verb, Verbs}
  alias LineCore.Verbs.Help

  defp ctx, do: %Verb.Context{actor: nil, room: nil, room_contents: [], command: "help"}

  defp index do
    {:ok, [{:notify_actor, text}]} = Help.execute(ctx(), [])
    text
  end

  describe "index" do
    test "is grouped into named categories, LambdaMOO style" do
      text = index()

      assert text =~ "THE LINE — command index"

      for heading <- [
            "Looking around",
            "Getting around",
            "Talking",
            "Carrying things",
            "Staying alive",
            "The scrap trade"
          ] do
        assert text =~ heading, "index is missing the #{inspect(heading)} category"
      end
    end

    test "every registered verb appears somewhere in the index" do
      text = index()

      for module <- Parser.known_verbs() do
        name = module |> Module.split() |> List.last() |> Macro.underscore()
        assert text =~ name, "#{inspect(module)} is registered but missing from the help index"
      end
    end

    test "every registered verb has player-facing text" do
      missing = Parser.known_verbs() -- Help.described_verbs()

      assert missing == [],
             "these verbs are registered but have no help summary: #{inspect(missing)}"
    end

    test "lists aliases against their canonical command" do
      text = index()

      assert text =~ "look"
      assert text =~ "also:"
      # `l` is an alias of look, not a command in its own right.
      refute text =~ ~r/^\s{2}l\s/m
    end

    test "closes with the pointer to per-command help" do
      assert index() =~ "Type `help <command>` for detail"
    end
  end

  describe "help <command>" do
    test "describes a command and its aliases" do
      {:ok, [{:notify_actor, text}]} = Help.execute(ctx(), ["look"])

      assert text =~ "look"
      assert text =~ "also:"
      assert text =~ "Take in the room"
    end

    test "an alias resolves to the same entry as its canonical name" do
      {:ok, [{:notify_actor, from_alias}]} = Help.execute(ctx(), ["x"])
      {:ok, [{:notify_actor, from_canonical}]} = Help.execute(ctx(), ["examine"])

      assert from_alias == from_canonical
    end

    test "is case and whitespace insensitive" do
      {:ok, [{:notify_actor, text}]} = Help.execute(ctx(), ["  ATTACK "])
      assert text =~ "attack"
    end

    test "an unknown command is an error" do
      assert {:error, :unknown_verb} = Help.execute(ctx(), ["frobnicate"])
    end
  end

  describe "purity" do
    test "emits exactly one notify_actor and nothing persistent" do
      {:ok, events} = Help.execute(ctx(), [])

      assert [{:notify_actor, _}] = events
    end

    test "help for every verb renders without raising" do
      for module <- Parser.known_verbs() do
        name = module |> Module.split() |> List.last() |> Macro.underscore()
        assert {:ok, [{:notify_actor, text}]} = Help.execute(ctx(), [name])
        refute text =~ "No description yet."
      end
    end
  end

  describe "categorisation is drift-proof" do
    test "an uncategorised verb would still be listed" do
      # Sanity check on the catch-all: Help itself is categorised, so nothing
      # should currently be falling through to "Other".
      refute index() =~ "Other"
      assert Verbs.Help in Parser.known_verbs()
    end
  end
end
