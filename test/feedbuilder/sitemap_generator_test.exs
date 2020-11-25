defmodule Feedbuilder.Sitemap.GeneratorTest do
  use ExUnit.Case
  doctest Feedbuilder.Sitemap

  alias Feedbuilder.File
  alias Feedbuilder.Sitemap
  alias Feedbuilder.Sitemap.Item

  test "add_url and finalize with a simple URL" do
    item = %Item{loc: "http://example.com"}

    %File{count: count, length: length, body: body} =
      Sitemap.new_feed()
      |> Sitemap.add_feed_item(item)
      |> Sitemap.finalize_feed()

    assert count == 1
    assert length == 330

    assert IO.chardata_to_string(body) ==
             "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<urlset xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xsi:schemaLocation=\"http://www.sitemaps.org/schemas/sitemap/0.9 http://www.sitemaps.org/schemas/sitemap/0.9/sitemap.xsd\" xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n<url>\n  <loc>http://example.com</loc>\n</url>\n</urlset>\n"

    assert length == IO.iodata_length(body)
  end

  test "add_url with more than 50,000 URLs" do
    result =
      0..50_000
      |> Enum.map(fn i ->
        %Item{loc: "http://example.com/#{i}"}
      end)
      |> Enum.reduce(Sitemap.new_feed(), fn url, acc ->
        Sitemap.add_feed_item(acc, url)
      end)

    assert result == {:error, :over_count}
  end

  test "add_url with more than 50MB" do
    {error, %File{count: count, length: length, body: body}} =
      0..50_000
      |> Enum.map(fn i ->
        block = String.duplicate("a", 1024)
        %Item{loc: "http://example.com/#{block}/#{i}"}
      end)
      |> Enum.reduce_while(Sitemap.new_feed(), fn url, acc ->
        case Sitemap.add_feed_item(acc, url) do
          {:error, _} = err ->
            acc = Sitemap.finalize_feed(acc)
            {:halt, {err, acc}}

          other ->
            {:cont, other}
        end
      end)

    assert error == {:error, :over_length}
    assert count == 48735
    assert length == 52_428_035
    assert length == IO.iodata_length(body)
  end
end
