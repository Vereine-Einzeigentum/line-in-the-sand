defmodule LineMl do
  @moduledoc """
  Typed inference boundary. No backend is silently substituted: absent providers
  return `{:error, :unavailable}`. Successful output preserves assertions and
  records its provenance; it does not authorize or execute game actions.
  Backend modules are trusted server configuration, never names from a request.
  """
  alias LineCore.ItemSpec
  alias LineMl.{Completion, Request}

  def complete(request, opts \\ []) do
    with :ok <- Request.validate(request) do
      backend = Keyword.get(opts, :backend, Application.get_env(:line_ml, :backend))
      timeout = Keyword.get(opts, :timeout, 5_000)

      cond do
        is_nil(backend) ->
          {:error, :unavailable}

        not is_integer(timeout) or timeout not in 1..30_000 ->
          {:error, :invalid_timeout}

        not is_atom(backend) or not Code.ensure_loaded?(backend) or
            not function_exported?(backend, :complete, 1) ->
          {:error, :invalid_backend}

        true ->
          invoke(backend, request, timeout)
      end
    end
  end

  defp invoke(backend, request, timeout) do
    task = Task.Supervisor.async_nolink(LineMl.Tasks, fn -> backend.complete(request) end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, result}} -> validate_result(request, result, backend)
      {:ok, {:error, :unavailable}} -> {:error, :unavailable}
      {:exit, _} -> {:error, :backend_failed}
      nil -> {:error, :timeout}
      {:ok, {:error, _}} -> {:error, :backend_failed}
      _ -> {:error, :invalid_response}
    end
  end

  defp validate_result(request, %{derived: derived, solved: solved} = result, backend)
       when map_size(result) == 2 and is_map(derived) and is_map(solved) do
    if :erlang.external_size(result) > 65_536 do
      {:error, :response_too_large}
    else
      with {:ok, spec} <- additions(request.spec, derived, &ItemSpec.put_derived/3),
           {:ok, spec} <- additions(spec, solved, &ItemSpec.put_solved/3),
           :ok <- ItemSpec.validate(spec) do
        {:ok,
         %Completion{
           spec: spec,
           provenance: %{
             "source" => Atom.to_string(backend),
             "reference" => request.id
           }
         }}
      end
    end
  end

  defp validate_result(_, _, _), do: {:error, :invalid_response}

  defp additions(spec, facts, put) do
    facts
    |> Enum.sort()
    |> Enum.reduce_while({:ok, spec}, fn {key, value}, {:ok, acc} ->
      case put.(acc, key, value) do
        {:ok, next} -> {:cont, {:ok, next}}
        error -> {:halt, error}
      end
    end)
  end
end
