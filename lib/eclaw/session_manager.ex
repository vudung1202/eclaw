defmodule Eclaw.SessionManager do
  @moduledoc """
  Manages per-user Agent sessions.

  Each user (from Telegram, Discord, ...) has a separate Agent process,
  created automatically on first message.

  - Fast lookup via Registry {:agent, session_id}
  - Auto cleanup on Agent idle timeout
  - DynamicSupervisor ensures crash isolation
  """

  require Logger

  @doc """
  Get or create an Agent process for a session_id.

  session_id format: "telegram:123456" or "discord:789"
  """
  @spec get_or_create(String.t()) :: {:ok, pid()} | {:error, term()}
  def get_or_create(session_id) do
    case lookup(session_id) do
      {:ok, pid} ->
        {:ok, pid}

      :not_found ->
        start_session(session_id)
    end
  end

  @doc "Find running Agent process for a session_id."
  @spec lookup(String.t()) :: {:ok, pid()} | :not_found
  def lookup(session_id) do
    case Registry.lookup(Eclaw.Registry, {:agent, session_id}) do
      [{pid, _}] -> {:ok, pid}
      [] -> :not_found
    end
  end

  @doc "Stop an Agent session."
  @spec stop(String.t()) :: :ok
  def stop(session_id) do
    case lookup(session_id) do
      {:ok, pid} ->
        DynamicSupervisor.terminate_child(Eclaw.SessionSupervisor, pid)
        Logger.info("[SessionManager] Stopped session: #{session_id}")
        :ok

      :not_found ->
        :ok
    end
  end

  @doc "List all active sessions."
  @spec list_sessions() :: [%{session_id: String.t(), pid: pid()}]
  def list_sessions do
    Eclaw.Registry
    |> Registry.select([{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
    |> Enum.filter(fn {{:agent, _id}, _pid} -> true; _ -> false end)
    |> Enum.map(fn {{:agent, id}, pid} -> %{session_id: id, pid: pid} end)
  end

  @doc "Count active sessions."
  @spec count() :: non_neg_integer()
  def count do
    length(list_sessions())
  end

  @doc """
  Get or start an Agent process, returning the pid directly.

  Unlike `get_or_create/1` which returns `{:ok, pid}`, this returns
  just the pid — convenient for callers that need it immediately.
  """
  @spec get_or_start!(String.t()) :: pid()
  def get_or_start!(session_id) do
    case get_or_create(session_id) do
      {:ok, pid} -> pid
      {:error, reason} -> raise "Failed to start session #{session_id}: #{inspect(reason)}"
    end
  end

  # ── Private ──────────────────────────────────────────────────────

  defp start_session(session_id) do
    spec = {Eclaw.Agent, [session_id: session_id]}

    case DynamicSupervisor.start_child(Eclaw.SessionSupervisor, spec) do
      {:ok, pid} ->
        Logger.info("[SessionManager] Started session: #{session_id}")
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        {:ok, pid}

      {:error, reason} ->
        Logger.error("[SessionManager] Failed to start session #{session_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
