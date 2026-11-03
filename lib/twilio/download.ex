defmodule Twilio.Download do
  @moduledoc """
  Download the bytes of one file, such as a media item that an inbound message names
  in `MediaUrl{N}`, as a stream that the caller can stop early.

      {:ok, %Twilio.Download{status: 200, headers: headers, body: body}} =
        Twilio.Download.get(client, media_url, timeout: 30_000)

      bytes = Enum.into(body, <<>>)

  `get/3` sends the client's credentials with the request and follows up to 3
  redirects of status 301, 302, 303, 307, or 308, including a relative `Location`.
  Twilio redirects a media request to a signed URL on another host, so the
  credentials go only to the origin (scheme, host, and port) of the first request.
  It returns when the status and headers of a 2xx answer arrive, before any body
  byte. Any other final answer is a `Twilio.Error` built from its status and headers
  only, because a Twilio error body names the requested path.

  The body is a lazy enumerable of binaries. Only the process that called `get/3` can
  read it, and only once. Halting it, or reading it to the end, ends the request. A
  caller that will not read the body calls `cancel/1`.

  A read error while the body streams raises from the enumeration: the exception
  that Finch reports, or `Finch.TransportError` with reason `:timeout` when the
  timeout passes. Before the headers, the same failures return
  `Twilio.Error.connection_error/1`.

  The download makes no retry, emits no Twilio telemetry event, and logs nothing,
  because its URL names the media item. Finch's own `[:finch, ...]` events carry the
  request, so a handler attached to them sees the URL. `Twilio.Test.stub/1` answers
  each of its requests as it does for `Twilio.Client.request/4`, and the stub's body
  is the one chunk of the stream.
  """

  alias Twilio.Client

  @redirect_statuses [301, 302, 303, 307, 308]
  @max_redirects 3

  @enforce_keys [:status, :headers, :body]
  defstruct [:status, :headers, :body, :ref]

  @typedoc "One answer whose body is not read yet. `ref` is internal."
  @type t :: %__MODULE__{
          status: 100..599,
          headers: [{String.t(), String.t()}],
          body: Enumerable.t(),
          ref: Finch.request_ref() | nil
        }

  @doc """
  Start the download of `url` and return its answer once the headers arrive.

  ## Options

    * `:timeout` - Milliseconds from this call to the end of the body, across all
      redirects (default: the client's `read_timeout`)
  """
  @spec get(Client.t(), String.t(), keyword()) :: {:ok, t()} | {:error, Twilio.Error.t()}
  def get(%Client{} = client, url, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, client.read_timeout)
    deadline = System.monotonic_time(:millisecond) + timeout
    follow(client, url, origin(url), deadline, 0)
  end

  @doc "Stop a download whose body the caller will not read, and drop what has arrived."
  @spec cancel(t()) :: :ok
  def cancel(%__MODULE__{ref: nil}), do: :ok
  def cancel(%__MODULE__{ref: ref}), do: stop(ref)

  defp follow(client, url, first_origin, deadline, redirects) do
    headers = [{"user-agent", Client.user_agent(client)}, {"accept", "*/*"}]

    headers =
      if origin(url) == first_origin, do: [Client.authorization(client) | headers], else: headers

    case start(client, url, headers, deadline) do
      {:ok, %__MODULE__{status: status} = download} when status in 200..299 ->
        {:ok, download}

      {:ok, download} ->
        cancel(download)
        redirect(client, url, first_origin, deadline, redirects, download)

      {:error, _error} = error ->
        error
    end
  end

  defp redirect(client, url, first_origin, deadline, redirects, download) do
    %__MODULE__{status: status, headers: headers} = download
    location = Client.get_header(headers, "location")

    cond do
      status not in @redirect_statuses or is_nil(location) ->
        {:error, Twilio.Error.from_response(status, "", headers)}

      redirects == @max_redirects ->
        {:error,
         %{Twilio.Error.from_response(status, "", headers) | message: "Too many redirects"}}

      true ->
        next = url |> URI.merge(location) |> URI.to_string()
        follow(client, next, first_origin, deadline, redirects + 1)
    end
  end

  defp origin(url) do
    %URI{scheme: scheme, host: host, port: port} = URI.parse(url)
    {scheme, host && String.downcase(host), port}
  end

  defp start(client, url, headers, deadline) do
    case Twilio.Test.fetch_stub(self()) do
      {:ok, fun} ->
        {status, resp_headers, body} = fun.("GET", url, headers, nil)
        {:ok, %__MODULE__{status: status, headers: resp_headers, body: [body]}}

      :error ->
        ref =
          "GET"
          |> Finch.build(url, headers)
          |> Finch.async_request(client.finch,
            pool_timeout: client.open_timeout,
            receive_timeout: remaining(deadline)
          )

        await_headers(ref, deadline, nil)
    end
  end

  defp await_headers(ref, deadline, status) do
    receive do
      {^ref, {:status, status}} ->
        await_headers(ref, deadline, status)

      {^ref, {:headers, headers}} ->
        {:ok, %__MODULE__{status: status, headers: headers, body: body(ref, deadline), ref: ref}}

      {^ref, {:error, exception}} ->
        {:error, Twilio.Error.connection_error(Exception.message(exception))}
    after
      remaining(deadline) ->
        stop(ref)
        {:error, Twilio.Error.connection_error("Timeout before the response headers")}
    end
  end

  defp body(ref, deadline) do
    Stream.resource(fn -> ref end, &next_chunk(&1, deadline), &finish/1)
  end

  defp next_chunk(ref, deadline) do
    receive do
      {^ref, {:data, data}} -> {[data], ref}
      {^ref, {:headers, _trailers}} -> {[], ref}
      {^ref, :done} -> {:halt, :done}
      {^ref, {:error, exception}} -> raise exception
    after
      remaining(deadline) -> raise Finch.TransportError, reason: :timeout
    end
  end

  defp finish(:done), do: :ok
  defp finish(ref), do: stop(ref)

  # A message that Finch sent before the cancel can still arrive, so the mailbox is
  # emptied of the request's messages, as `Req.cancel_async_response/1` does.
  defp stop(ref) do
    Finch.cancel_async_request(ref)
    flush(ref)
  end

  defp flush(ref) do
    receive do
      {^ref, _message} -> flush(ref)
    after
      0 -> :ok
    end
  end

  defp remaining(deadline), do: max(deadline - System.monotonic_time(:millisecond), 0)
end
