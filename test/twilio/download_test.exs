defmodule Twilio.DownloadTest do
  @moduledoc """
  Download one media item over the real Finch path.

  A local socket server plays both Twilio and the host of the signed URL that Twilio
  redirects to. The address `127.0.0.1` and the name `localhost` reach the same
  listener as two different hosts, so a test sees each request's `Host` and
  `Authorization` headers.
  """

  use ExUnit.Case, async: true

  alias Twilio.Client
  alias Twilio.Download

  # A JPEG image. Each test serves it with the headers that the test names.
  @fixture File.read!(Path.expand("../fixtures/media.jpg", __DIR__))

  @media_path "/2010-04-01/Accounts/ACsub/Messages/MM123/Media/ME123"

  setup do
    {:ok, client: Client.new("SKkey", "secret", account_sid: "ACsub")}
  end

  test "returns the status, the headers, and a stream of exactly the fixture's bytes",
       %{client: client} do
    port = serve([answer(200, [{"content-type", "image/jpeg"}], @fixture)])

    assert {:ok, %Download{status: 200, headers: headers, body: body}} =
             Download.get(client, media_url(port))

    assert header(headers, "content-type") == "image/jpeg"
    assert header(headers, "content-length") == Integer.to_string(byte_size(@fixture))
    assert Enum.into(body, <<>>) == @fixture

    assert_receive {:request, request}
    assert request.headers["authorization"] == "Basic " <> Base.encode64("SKkey:secret")
  end

  test "follows a 307 and a relative 302 to another host without sending it credentials",
       %{client: client} do
    port =
      serve(fn port ->
        [
          answer(307, [{"location", "http://localhost:#{port}/redirected"}]),
          answer(302, [{"location", "/signed?Expires=1"}]),
          answer(200, [{"content-type", "image/jpeg"}], @fixture)
        ]
      end)

    assert {:ok, %Download{status: 200, body: body}} = Download.get(client, media_url(port))
    assert Enum.into(body, <<>>) == @fixture

    assert_receive {:request, first}
    assert first.path == @media_path
    assert first.headers["host"] == "127.0.0.1:#{port}"
    assert first.headers["authorization"] =~ "Basic "

    assert_receive {:request, second}
    assert second.path == "/redirected"
    assert second.headers["host"] == "localhost:#{port}"
    refute Map.has_key?(second.headers, "authorization")

    assert_receive {:request, third}
    assert third.path == "/signed?Expires=1"
    assert third.headers["host"] == "localhost:#{port}"
    refute Map.has_key?(third.headers, "authorization")
  end

  test "returns an error and no bytes on a 4th redirect", %{client: client} do
    port = serve(for hop <- 1..4, do: answer(302, [{"location", "/hop/#{hop}"}]))

    assert {:error, %Twilio.Error{http_status: 302} = error} =
             Download.get(client, media_url(port))

    refute Twilio.Error.retryable?(error)

    for _hop <- 1..4, do: assert_receive({:request, _request})
    assert_receive :served, 1_000
    refute_received {:request, _request}
    refute_received {_ref, {:data, _data}}
  end

  test "returns a 404 as an error with its status and no bytes", %{client: client} do
    message = ~s({"code":20404,"message":"The requested resource #{@media_path} was not found"})
    port = serve([answer(404, [{"content-type", "application/json"}], message)])

    assert {:error, %Twilio.Error{http_status: 404, type: :not_found_error} = error} =
             Download.get(client, media_url(port))

    refute inspect(error) =~ "ME123"
    refute_received {_ref, {:data, _data}}
  end

  test "a caller that stops after the headers receives no body bytes", %{client: client} do
    test = self()

    port =
      serve([
        fn socket ->
          :ok = :gen_tcp.send(socket, head(200, [{"content-type", "image/jpeg"}], @fixture))
          send(test, {:read_after_headers, :gen_tcp.recv(socket, 0, 5_000)})
        end
      ])

    assert {:ok, %Download{status: 200} = download} = Download.get(client, media_url(port))
    assert :ok = Download.cancel(download)

    assert_receive {:read_after_headers, {:error, :closed}}
    refute_received {_ref, {:data, _data}}
  end

  test "halting the body stream closes the connection", %{client: client} do
    test = self()
    {first, _rest} = String.split_at(@fixture, 100)

    port =
      serve([
        fn socket ->
          :ok = :gen_tcp.send(socket, [head(200, [], @fixture), first])
          send(test, {:read_after_chunk, :gen_tcp.recv(socket, 0, 5_000)})
        end
      ])

    assert {:ok, %Download{body: body}} = Download.get(client, media_url(port))
    assert [chunk] = Enum.take(body, 1)
    assert String.starts_with?(first, chunk)

    assert_receive {:read_after_chunk, {:error, :closed}}
  end

  test "returns a connection error when the headers do not arrive before the timeout",
       %{client: client} do
    test = self()
    port = serve([fn socket -> send(test, {:stalled, :gen_tcp.recv(socket, 0, 5_000)}) end])

    assert {:error, %Twilio.Error{type: :connection_error}} =
             Download.get(client, media_url(port), timeout: 200)

    assert_receive {:stalled, {:error, :closed}}
  end

  test "raises from the body stream when the body does not arrive before the timeout",
       %{client: client} do
    test = self()

    port =
      serve([
        fn socket ->
          :ok = :gen_tcp.send(socket, head(200, [], @fixture))
          send(test, {:stalled, :gen_tcp.recv(socket, 0, 5_000)})
        end
      ])

    assert {:ok, %Download{body: body}} = Download.get(client, media_url(port), timeout: 200)
    assert_raise Finch.TransportError, fn -> Enum.to_list(body) end

    assert_receive {:stalled, {:error, :closed}}
  end

  test "applies one timeout across the redirects", %{client: client} do
    test = self()

    port =
      serve([
        fn socket ->
          Process.sleep(300)
          :ok = :gen_tcp.send(socket, answer(302, [{"location", "/stall"}]))
        end,
        fn socket -> send(test, {:stalled, :gen_tcp.recv(socket, 0, 5_000)}) end
      ])

    started = System.monotonic_time(:millisecond)

    assert {:error, %Twilio.Error{type: :connection_error}} =
             Download.get(client, media_url(port), timeout: 400)

    # The shared deadline ends at about 400 ms; a fresh timeout per hop at about 700 ms.
    assert System.monotonic_time(:millisecond) - started < 600
    assert_receive {:stalled, {:error, :closed}}
  end

  test "applies one timeout to the whole body, not to each read", %{client: client} do
    test = self()
    chunks = for _chunk <- 1..20, do: :binary.copy("x", 10)

    port =
      serve([
        fn socket ->
          :ok = :gen_tcp.send(socket, head(200, [], IO.iodata_to_binary(chunks)))

          sent =
            Enum.reduce_while(chunks, 0, fn chunk, sent ->
              Process.sleep(50)

              case :gen_tcp.send(socket, chunk) do
                :ok -> {:cont, sent + 1}
                {:error, _reason} -> {:halt, sent}
              end
            end)

          send(test, {:trickled, sent})
        end
      ])

    assert {:ok, %Download{body: body}} = Download.get(client, media_url(port), timeout: 200)
    assert_raise Finch.TransportError, fn -> Enum.to_list(body) end

    assert_receive {:trickled, sent}, 2_000
    assert sent < length(chunks)
  end

  test "sends each hop through the Twilio.Test stub", %{client: client} do
    test = self()

    Twilio.Test.stub(fn "GET", url, headers, nil ->
      send(test, {:stubbed, url, header(headers, "authorization")})

      case URI.parse(url).host do
        "api.twilio.com" -> {307, [{"location", "https://media.example.com/signed"}], ""}
        "media.example.com" -> {200, [{"content-type", "image/jpeg"}], @fixture}
      end
    end)

    assert {:ok, %Download{status: 200, body: body}} =
             Download.get(client, "https://api.twilio.com" <> @media_path)

    assert Enum.into(body, <<>>) == @fixture
    assert_received {:stubbed, "https://api.twilio.com" <> @media_path, "Basic " <> _auth}
    assert_received {:stubbed, "https://media.example.com/signed", nil}
  end

  defp media_url(port), do: "http://127.0.0.1:#{port}" <> @media_path

  defp header(headers, name) do
    Enum.find_value(headers, fn {key, value} -> if String.downcase(key) == name, do: value end)
  end

  defp answer(status, headers, body \\ ""), do: [head(status, headers, body), body]

  defp head(status, headers, body) do
    [
      "HTTP/1.1 #{status} Status\r\n",
      Enum.map(headers, fn {key, value} -> "#{key}: #{value}\r\n" end),
      "connection: close\r\n",
      "content-length: #{byte_size(body)}\r\n\r\n"
    ]
  end

  # Accepts one connection for each answer, in order, and sends the test each request
  # as `{:request, %{path: path, headers: headers}}`. An answer is iodata, or a function
  # that receives the socket. A function of the port gives answers that name the port.
  # After the last answer the server waits briefly for one more connection and sends
  # `{:request, _}` for it too, so a test can show that the client sent no further
  # request; it then sends `:served`.
  defp serve(answers) when is_list(answers), do: serve(fn _port -> answers end)

  defp serve(answers_for_port) do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, packet: :raw, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listen)
    test = self()

    {:ok, _pid} =
      Task.start_link(fn ->
        for answer <- answers_for_port.(port) do
          {:ok, socket} = :gen_tcp.accept(listen, 5_000)
          send(test, {:request, read_head(socket, "")})
          respond(socket, answer)
          :gen_tcp.close(socket)
        end

        case :gen_tcp.accept(listen, 100) do
          {:ok, socket} -> send(test, {:request, read_head(socket, "")})
          {:error, :timeout} -> :ok
        end

        :gen_tcp.close(listen)
        send(test, :served)
      end)

    port
  end

  defp respond(socket, answer) when is_function(answer, 1), do: answer.(socket)
  defp respond(socket, answer), do: :ok = :gen_tcp.send(socket, answer)

  defp read_head(socket, received) do
    case String.split(received, "\r\n\r\n", parts: 2) do
      [head, _rest] ->
        [request_line | lines] = String.split(head, "\r\n")
        [_method, path, _version] = String.split(request_line, " ")

        headers =
          Map.new(lines, fn line ->
            [key, value] = String.split(line, ": ", parts: 2)
            {String.downcase(key), value}
          end)

        %{path: path, headers: headers}

      [_partial] ->
        {:ok, data} = :gen_tcp.recv(socket, 0, 5_000)
        read_head(socket, received <> data)
    end
  end
end
