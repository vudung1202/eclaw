defmodule Eclaw.Speech do
  @moduledoc """
  Speech-to-text transcription via OpenAI Whisper API.

  Transcribes audio binary (OGG, MP3, etc.) to text.
  Used by ChannelManager to process voice messages from Telegram.
  """

  require Logger

  @whisper_url "https://api.openai.com/v1/audio/transcriptions"
  @default_model "whisper-1"
  @default_language "vi"

  @doc """
  Transcribe audio binary to text using OpenAI Whisper.

  ## Options

    * `:language` — language code (default: `"vi"` for Vietnamese)
    * `:model` — Whisper model (default: `"whisper-1"`)

  ## Examples

      {:ok, "xin chào"} = Eclaw.Speech.transcribe(ogg_binary)
      {:ok, text} = Eclaw.Speech.transcribe(audio, language: "en")
  """
  @spec transcribe(binary(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def transcribe(audio_binary, opts \\ []) do
    api_key = Application.get_env(:eclaw, :openai_api_key) || System.get_env("OPENAI_API_KEY")

    if is_nil(api_key) or api_key == "" do
      Logger.error("[Speech] Missing OpenAI API key for Whisper transcription")
      {:error, :missing_api_key}
    else
      do_transcribe(audio_binary, api_key, opts)
    end
  end

  defp do_transcribe(audio_binary, api_key, opts) do
    model = Keyword.get(opts, :model, @default_model)
    language = Keyword.get(opts, :language, @default_language)

    # Multipart form upload — Req supports {:file_content, binary, filename, content_type}
    multipart =
      {:multipart,
       [
         {"file", audio_binary, {"form-data", [{:name, "file"}, {:filename, "audio.ogg"}]},
          [{"content-type", "audio/ogg"}]},
         {"model", model},
         {"language", language}
       ]}

    headers = [
      {"authorization", "Bearer #{api_key}"}
    ]

    Logger.debug("[Speech] Sending #{byte_size(audio_binary)} bytes to Whisper API (model=#{model}, lang=#{language})")

    case Req.post(@whisper_url,
           body: multipart,
           headers: headers,
           receive_timeout: 30_000
         ) do
      {:ok, %{status: 200, body: %{"text" => text}}} ->
        Logger.info("[Speech] Transcription successful: #{String.slice(text, 0, 100)}")
        {:ok, text}

      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        # Response may come as JSON string
        case Jason.decode(body) do
          {:ok, %{"text" => text}} ->
            Logger.info("[Speech] Transcription successful: #{String.slice(text, 0, 100)}")
            {:ok, text}

          _ ->
            Logger.error("[Speech] Unexpected response body: #{String.slice(body, 0, 200)}")
            {:error, :unexpected_response}
        end

      {:ok, %{status: status, body: body}} ->
        Logger.error("[Speech] Whisper API error: HTTP #{status} — #{inspect(body)}")
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        Logger.error("[Speech] Whisper request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
