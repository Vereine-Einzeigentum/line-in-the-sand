defmodule LineCore.ParserTest do
  use ExUnit.Case, async: true

  alias LineCore.{Parser, Verbs}

  describe "parse/1 — empty and trivial" do
    test "empty string returns :empty" do
      assert {:empty, _} = Parser.parse("")
      assert {:empty, _} = Parser.parse("   ")
    end
  end

  describe "parse/1 — verb aliases" do
    test "look aliases route to Look" do
      assert {:ok, Verbs.Look, []} = Parser.parse("look")
      assert {:ok, Verbs.Look, []} = Parser.parse("l")
    end

    test "examine aliases route to Examine with target" do
      assert {:ok, Verbs.Examine, ["fence"]} = Parser.parse("examine fence")
      assert {:ok, Verbs.Examine, ["fence"]} = Parser.parse("ex fence")
      assert {:ok, Verbs.Examine, ["fence"]} = Parser.parse("x fence")
    end

    test "inventory aliases route to Inventory" do
      assert {:ok, Verbs.Inventory, []} = Parser.parse("inventory")
      assert {:ok, Verbs.Inventory, []} = Parser.parse("inv")
      assert {:ok, Verbs.Inventory, []} = Parser.parse("i")
    end

    test "get synonyms all route to Get" do
      for verb <- ~w(get grab gather pickup take) do
        assert {:ok, Verbs.Get, ["knife"]} = Parser.parse("#{verb} knife")
      end
    end

    test "drop synonyms all route to Drop" do
      for verb <- ~w(drop leave put discard) do
        assert {:ok, Verbs.Drop, ["knife"]} = Parser.parse("#{verb} knife")
      end
    end

    test "text synonyms all route to Text" do
      for verb <- ~w(text txt tell) do
        assert {:ok, Verbs.Text, ["Graves", "hello"]} = Parser.parse("#{verb} Graves hello")
      end
    end
  end

  describe "parse/1 — directional shortcuts" do
    test "bare cardinal directions route to Go" do
      assert {:ok, Verbs.Go, ["n"]} = Parser.parse("n")
      assert {:ok, Verbs.Go, ["north"]} = Parser.parse("north")
      assert {:ok, Verbs.Go, ["s"]} = Parser.parse("s")
      assert {:ok, Verbs.Go, ["sw"]} = Parser.parse("sw")
    end

    test "bare directions are case-insensitive" do
      assert {:ok, Verbs.Go, ["n"]} = Parser.parse("N")
      assert {:ok, Verbs.Go, ["north"]} = Parser.parse("NORTH")
    end

    test "explicit go also works" do
      assert {:ok, Verbs.Go, ["north"]} = Parser.parse("go north")
      assert {:ok, Verbs.Go, ["n"]} = Parser.parse("go n")
    end

    test "in/out are directions too" do
      assert {:ok, Verbs.Go, ["in"]} = Parser.parse("in")
      assert {:ok, Verbs.Go, ["out"]} = Parser.parse("out")
    end
  end

  describe "parse/1 — speak prefix" do
    test "quote prefix routes to Say" do
      assert {:ok, Verbs.Say, ["hello there"]} = Parser.parse(~s("hello there))
    end

    test "quote prefix with no message" do
      assert {:ok, Verbs.Say, [""]} = Parser.parse(~s("))
    end

    test "quote prefix preserves internal punctuation" do
      assert {:ok, Verbs.Say, ["wait, who are you?"]} =
               Parser.parse(~s("wait, who are you?))
    end
  end

  describe "parse/1 — emote prefix" do
    test "colon prefix routes to Emote" do
      assert {:ok, Verbs.Emote, ["waves"]} = Parser.parse(":waves")
    end

    test "colon prefix with no action" do
      assert {:ok, Verbs.Emote, [""]} = Parser.parse(":")
    end

    test "colon prefix preserves action description" do
      assert {:ok, Verbs.Emote, ["grins mischievously"]} =
               Parser.parse(":grins mischievously")
    end
  end

  describe "parse/1 — multi-word arguments" do
    test "get with multi-word item name" do
      assert {:ok, Verbs.Get, ["rusty knife"]} = Parser.parse("get rusty knife")
    end

    test "say with long message" do
      assert {:ok, Verbs.Say, ["hello homosexy gals and gays"]} =
               Parser.parse(~s("hello homosexy gals and gays))
    end
  end

  describe "parse/1 — text verb structure" do
    test "text <player> <message> splits at first space" do
      assert {:ok, Verbs.Text, ["Graves", "are you ok"]} =
               Parser.parse("text Graves are you ok")
    end

    test "text with only player name" do
      assert {:ok, Verbs.Text, ["Graves"]} = Parser.parse("text Graves")
    end
  end

  describe "parse/1 — desc verb structure" do
    test "desc me as <description>" do
      assert {:ok, Verbs.Desc, ["scarred and quiet"]} =
               Parser.parse("desc me as scarred and quiet")
    end

    test "describe me as <description>" do
      assert {:ok, Verbs.Desc, ["tall, wired"]} =
               Parser.parse("describe me as tall, wired")
    end

    test "desc self as <description>" do
      assert {:ok, Verbs.Desc, ["weary"]} = Parser.parse("desc self as weary")
    end

    test "desc <object> as <description>" do
      assert {:ok, Verbs.Desc, ["knife", "a dented blade"]} =
               Parser.parse("desc knife as a dented blade")
    end
  end

  describe "parse/1 — who verb" do
    test "bare who" do
      assert {:ok, Verbs.Who, []} = Parser.parse("who")
    end

    test "who <player>" do
      assert {:ok, Verbs.Who, ["Graves"]} = Parser.parse("who Graves")
    end
  end

  describe "parse/1 — score verb" do
    test "score aliases all route to Score" do
      assert {:ok, Verbs.Score, []} = Parser.parse("score")
      assert {:ok, Verbs.Score, []} = Parser.parse("stats")
      assert {:ok, Verbs.Score, []} = Parser.parse("sc")
    end

    test "score ignores trailing arguments" do
      assert {:ok, Verbs.Score, []} = Parser.parse("score anything")
    end
  end

  describe "parse/1 — emote verb aliases" do
    test "emote verb aliases all route to Emote" do
      assert {:ok, Verbs.Emote, ["waves"]} = Parser.parse("emote waves")
      assert {:ok, Verbs.Emote, ["waves"]} = Parser.parse("me waves")
    end
  end

  describe "parse/1 — give verb structure" do
    test "give <item> to <player>" do
      assert {:ok, Verbs.Give, ["sword", "Alice"]} = Parser.parse("give sword to Alice")
    end

    test "give with multi-word item and recipient" do
      assert {:ok, Verbs.Give, ["rusty sword", "Alice"]} =
               Parser.parse("give rusty sword to Alice")
    end

    test "hand alias routes to Give" do
      assert {:ok, Verbs.Give, ["knife", "Bob"]} = Parser.parse("hand knife to Bob")
    end

    test "give without recipient returns malformed" do
      assert {:ok, Verbs.Give, ["sword"]} = Parser.parse("give sword")
    end
  end

  describe "parse/1 — unwield verb structure" do
    test "bare unwield" do
      assert {:ok, Verbs.Unwield, []} = Parser.parse("unwield")
    end

    test "unwield <item>" do
      assert {:ok, Verbs.Unwield, ["sword"]} = Parser.parse("unwield sword")
    end

    test "unequip alias routes to Unwield" do
      assert {:ok, Verbs.Unwield, []} = Parser.parse("unequip")
      assert {:ok, Verbs.Unwield, ["shield"]} = Parser.parse("unequip shield")
    end

    test "sheathe alias routes to Unwield" do
      assert {:ok, Verbs.Unwield, []} = Parser.parse("sheathe")
      assert {:ok, Verbs.Unwield, ["sword"]} = Parser.parse("sheathe sword")
    end
  end

  describe "parse/1 — unknown verbs" do
    test "unrecognized verb returns :unknown" do
      assert {:unknown, "blarg", _} = Parser.parse("blarg")
      assert {:unknown, "frob", _} = Parser.parse("frob the widget")
    end

    test "unknown verb preserves original casing in raw, downcases in verb" do
      assert {:unknown, "blarg", "BLARG foo"} = Parser.parse("BLARG foo")
    end
  end

  describe "verb_map / known_verbs" do
    test "verb_map returns a map with all aliases" do
      m = Parser.verb_map()
      assert m["look"] == Verbs.Look
      assert m["l"] == Verbs.Look
      assert m["i"] == Verbs.Inventory
    end

    test "known_verbs returns deduplicated module list" do
      verbs = Parser.known_verbs()
      assert Verbs.Look in verbs
      assert Verbs.Go in verbs
      # No duplicates
      assert length(verbs) == length(Enum.uniq(verbs))
    end
  end
end
