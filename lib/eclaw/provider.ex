defmodule Eclaw.Provider do
  @moduledoc """
  Behaviour for LLM providers.

  Allows Eclaw to use multiple LLM backends
  (Anthropic, OpenAI, Google Gemini, local models, etc.)
  """

  @doc "Provider name (e.g. :anthropic, :openai, :gemini)."
  @callback name() :: atom()

  @doc "Send messages and receive response (non-streaming)."
  @callback chat(messages :: [map()], system :: String.t(), tools :: [map()], opts :: keyword()) ::
              {:ok, map()} | {:error, term()}

  @doc "Send messages with streaming callback."
  @callback stream(
              messages :: [map()],
              system :: String.t(),
              tools :: [map()],
              on_chunk :: function(),
              opts :: keyword()
            ) :: {:ok, map()} | {:error, term()}
end
