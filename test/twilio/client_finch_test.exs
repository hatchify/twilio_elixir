defmodule Twilio.ClientFinchTest do
  @moduledoc """
  Perform one request over the real Finch path.

  Every other client test installs a stub with `Twilio.Test.stub/1`, so it answers
  before Finch builds anything. The request options that `Twilio.Client` passes are
  therefore exercised here alone, and this test is what reports an option key that
  Finch does not accept. This test installs no stub, which is what selects the real
  path.
  """

  use ExUnit.Case, async: false

  alias Twilio.Client

  # One connection and one canned answer. A real socket keeps the test free of a web
  # server dependency and still makes Finch build a request, open a connection, and
  # read a response.
  defp serve_once do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, packet: :raw, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listen)

    task =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listen, 5_000)
        {:ok, _request} = :gen_tcp.recv(socket, 0, 5_000)
        body = ~s({"sid":"SM123","status":"queued"})

        :gen_tcp.send(socket, [
          "HTTP/1.1 200 OK\r\n",
          "content-type: application/json\r\n",
          "content-length: #{byte_size(body)}\r\n\r\n",
          body
        ])

        :gen_tcp.close(socket)
        :gen_tcp.close(listen)
      end)

    {port, task}
  end

  test "builds a request Finch accepts, and reads the answer" do
    name = :"finch_#{System.unique_integer([:positive])}"
    start_supervised!({Finch, name: name})

    {port, task} = serve_once()
    client = Client.new("ACtest123", "test_token", finch: name)

    assert {:ok, %{"sid" => "SM123"}} =
             Client.request(client, :get, "/2010-04-01/Accounts.json",
               base_url: "http://127.0.0.1:#{port}"
             )

    Task.await(task, 5_000)
  end
end
