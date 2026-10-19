defmodule LineMlTest do
  use ExUnit.Case, async: true
  alias LineCore.ItemSpec
  alias LineMl.{Completion, Request}

  defmodule Completer do
    @behaviour LineMl.Backend
    def complete(_), do: {:ok, %{derived: %{"mass" => 12}, solved: %{}}}
  end

  defmodule Contradiction do
    @behaviour LineMl.Backend
    def complete(_), do: {:ok, %{derived: %{}, solved: %{"powered" => true}}}
  end

  defmodule Events do
    @behaviour LineMl.Backend
    def complete(_), do: {:ok, %{derived: %{}, solved: %{}, events: [:admin]}}
  end

  defmodule Executable do
    @behaviour LineMl.Backend
    def complete(_), do: {:ok, %{derived: %{"run" => fn -> :bad end}, solved: %{}}}
  end

  defmodule Slow do
    @behaviour LineMl.Backend
    def complete(_) do
      receive do
        :never -> {:error, :unavailable}
      end
    end
  end

  defmodule Crash do
    @behaviour LineMl.Backend
    def complete(_), do: raise("backend crashed")
  end

  defp request do
    %Request{
      id: "request-1",
      instruction: "Complete the mass without changing assertions.",
      spec:
        ItemSpec.new(["Weapon", "Flute"], %{"name" => "thunder flute", "powered" => false},
          unknown: ["mass"]
        )
    }
  end

  test "a completion preserves asserted facts and carries provenance" do
    input = request()

    assert {:ok, %Completion{spec: spec, provenance: provenance}} =
             LineMl.complete(input, backend: Completer)

    assert spec.asserted == input.spec.asserted
    assert spec.lineage == input.spec.lineage
    assert spec.derived == %{"mass" => 12}
    assert spec.unknown == MapSet.new()
    assert provenance == %{"source" => Atom.to_string(Completer), "reference" => input.id}
  end

  test "missing backends and invalid requests have explicit failure results" do
    assert {:error, :unavailable} = LineMl.complete(request(), backend: nil)
    assert {:error, :invalid_backend} = LineMl.complete(request(), backend: __MODULE__)
    assert {:error, :invalid_request} = LineMl.complete(%{}, backend: Completer)
  end

  test "backend output cannot rewrite assertions or supply executable payloads" do
    assert {:error, {:asserted_conflict, "powered", false, true}} =
             LineMl.complete(request(), backend: Contradiction)

    assert {:error, :invalid_response} = LineMl.complete(request(), backend: Events)
    assert {:error, :invalid_facts} = LineMl.complete(request(), backend: Executable)
  end

  @tag :capture_log
  test "backend crashes and timeouts do not kill the caller" do
    assert {:error, :backend_failed} = LineMl.complete(request(), backend: Crash)
    assert {:error, :timeout} = LineMl.complete(request(), backend: Slow, timeout: 5)
    assert {:error, :invalid_timeout} = LineMl.complete(request(), backend: Slow, timeout: 0)
  end
end
