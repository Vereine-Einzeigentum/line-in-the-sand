defmodule LineCore.ParserTest do
  use ExUnit.Case, async: true

  alias LineCore.{Parser, Verbs, WorldCommand}

  describe "empty input" do
    test "returns :empty" do
      assert {:empty, _} = Parser.parse("")
      assert {:empty, _} = Parser.parse("   ")
    end
  end

  describe "reserved social prefixes" do
    test "quote prefix routes directly to say" do
      assert {:ok, Verbs.Say, ["hello there"]} = Parser.parse(~s("hello there))
    end

    test "colon prefix routes directly to free emote" do
      assert {:ok, Verbs.Emote, ["leans against the wall."]} =
               Parser.parse(":leans against the wall.")
    end

    test "dot prefix routes directly to sanctioned social namespace" do
      assert {:ok, Verbs.Social, ["hi"]} = Parser.parse(".hi")
      assert {:ok, Verbs.Social, ["wave", "Graves"]} = Parser.parse(".wave Graves")
    end

    test "dot social cannot fall through to an ordinary verb" do
      assert {:ok, Verbs.Social, ["hi"]} = Parser.parse(".hi")
    end
  end

  describe "system commands" do
    test "who stays in the system registry" do
      assert {:ok, Verbs.Who, []} = Parser.parse("who")
      assert {:ok, Verbs.Who, ["Graves"]} = Parser.parse("who Graves")
    end

    test "text aliases stay system-side" do
      for verb <- ~w(text txt tell) do
        assert {:ok, Verbs.Text, ["Graves", "hello"]} = Parser.parse("#{verb} Graves hello")
      end
    end

    test "account/body maintenance syntax stays system-side during transition" do
      assert {:ok, Verbs.Desc, ["scarred and quiet"]} =
               Parser.parse("@desc me as scarred and quiet")

      assert {:ok, Verbs.Bare, ["feet", "%P has tiny feet."]} =
               Parser.parse("@bare feet as %P has tiny feet.")

      assert {:ok, Verbs.Gender, ["she"]} = Parser.parse("@gender me as she")
      assert {:ok, Verbs.Password, ["longpassword"]} =
               Parser.parse("@password me as longpassword")
    end
  end

  describe "world commands" do
    test "look is parsed structurally rather than mapped to a module" do
      assert {:world,
              %WorldCommand{
                verb: "look",
                dobjstr: "self",
                prepstr: nil,
                iobjstr: nil
              }} = Parser.parse("look self")
    end

    test "game aliases remain strings for object verb matching" do
      assert {:world, %WorldCommand{verb: "l", dobjstr: "crate"}} = Parser.parse("l crate")
      assert {:world, %WorldCommand{verb: "take", dobjstr: "knife"}} =
               Parser.parse("take knife")
    end

    test "bare directions become world go commands" do
      assert {:world, %WorldCommand{verb: "go", argstr: "north", dobjstr: nil}} =
               Parser.parse("north")

      assert {:world, %WorldCommand{verb: "go", argstr: "n", dobjstr: nil}} =
               Parser.parse("N")
    end

    test "explicit go keeps direction out of object resolution" do
      assert {:ok, %WorldCommand{verb: "go", argstr: "north", dobjstr: nil}} =
               Parser.parse_world("go north")
    end

    test "wield separates hand modifier from direct-object string" do
      assert {:ok,
              %WorldCommand{
                verb: "wield",
                dobjstr: "rusty knife",
                modifier: "off"
              }} = Parser.parse_world("wield rusty knife off")
    end

    test "sell parses direct object, preposition, and indirect object" do
      assert {:ok,
              %WorldCommand{
                verb: "sell",
                dobjstr: "twisted pipe",
                prepstr: "to",
                iobjstr: "Hamid"
              }} = Parser.parse_world("sell twisted pipe to Hamid")
    end

    test "look at target treats target as the direct object" do
      assert {:ok,
              %WorldCommand{
                verb: "look",
                dobjstr: "fence",
                prepstr: "at"
              }} = Parser.parse_world("look at fence")
    end

    test "unrecognized ordinary words remain world commands for huh/verb search" do
      assert {:world, %WorldCommand{verb: "frob", dobjstr: "widget"}} =
               Parser.parse("frob widget")
    end
  end

  describe "verb_map / known_verbs" do
    test "verb_map contains system commands but no ordinary game verbs" do
      map = Parser.verb_map()

      assert map["who"] == Verbs.Who
      assert map["text"] == Verbs.Text
      assert map["@password"] == Verbs.Password

      refute Map.has_key?(map, "look")
      refute Map.has_key?(map, "go")
      refute Map.has_key?(map, "get")
      refute Map.has_key?(map, "wield")
      refute Map.has_key?(map, "attack")
    end

    test "known_verbs contains direct-prefix handlers and system handlers" do
      verbs = Parser.known_verbs()

      assert Verbs.Who in verbs
      assert Verbs.Say in verbs
      assert Verbs.Emote in verbs
      assert Verbs.Social in verbs
      assert length(verbs) == length(Enum.uniq(verbs))
    end
  end
end
