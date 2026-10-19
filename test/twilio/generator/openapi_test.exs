defmodule Twilio.Generator.OpenAPITest do
  use ExUnit.Case, async: true

  alias Twilio.Generator.OpenAPI

  @tag :tmp_dir
  test "an operation whose answer has fields its resource lacks gets its own resource",
       %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "twilio_test_v1.json")
    File.write!(path, JSON.encode!(widget_spec()))

    %{resources: resources} = OpenAPI.parse_file(path)
    assert resources |> Enum.map(& &1.name) |> Enum.sort() == ["NewWidget", "Widget"]

    widget = Enum.find(resources, &(&1.name == "Widget"))
    ops = Map.new(widget.operations, &{&1.operation_id, &1})
    assert ops["CreateNewWidget"].response_module == Twilio.Resources.Test.V1.NewWidget
    refute Map.has_key?(ops["UpdateWidget"], :response_module)
    refute Map.has_key?(ops["FetchWidget"], :response_module)

    new_widget = Enum.find(resources, &(&1.name == "NewWidget"))
    assert new_widget.response_only
    assert new_widget.schema_name == "test.v1.new_widget"
    assert new_widget.properties |> Enum.map(& &1.name) |> Enum.sort() == ~w(name secret sid)
  end

  # Widgets mirror Keys: the list and the instance answer with `widget`,
  # `CreateNewWidget` answers with `new_widget`, which adds `secret`, and
  # `UpdateWidget` answers with `widget_summary`, whose fields `widget` holds.
  defp widget_spec do
    %{
      "servers" => [%{"url" => "https://test.twilio.com"}],
      "paths" => %{
        "/v1/Widgets" => %{
          "x-twilio" => %{"pathType" => "list"},
          "get" => operation("ListWidget", "200", page("widgets", "test.v1.widget")),
          "post" => operation("CreateNewWidget", "201", ref("test.v1.new_widget"))
        },
        "/v1/Widgets/{Sid}" => %{
          "x-twilio" => %{"pathType" => "instance"},
          "get" => operation("FetchWidget", "200", ref("test.v1.widget")),
          "post" => operation("UpdateWidget", "200", ref("test.v1.widget_summary"))
        }
      },
      "components" => %{
        "schemas" => %{
          "test.v1.widget" => object(~w(sid name)),
          "test.v1.new_widget" => object(~w(sid name secret)),
          "test.v1.widget_summary" => object(~w(sid))
        }
      }
    }
  end

  defp operation(id, code, schema) do
    %{
      "operationId" => id,
      "responses" => %{code => %{"content" => %{"application/json" => %{"schema" => schema}}}}
    }
  end

  defp page(key, schema) do
    %{"type" => "object", "properties" => %{key => %{"type" => "array", "items" => ref(schema)}}}
  end

  defp ref(schema), do: %{"$ref" => "#/components/schemas/#{schema}"}

  defp object(fields) do
    %{"type" => "object", "properties" => Map.new(fields, &{&1, %{"type" => "string"}})}
  end
end
