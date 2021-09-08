defmodule Feedbuilder.Merchant do
  # @behaviour Feedbuilder.Feed

  alias Feedbuilder.{Encoder, File}
  alias Feedbuilder.Merchant.{Item, Index}

  @max_length 52_428_800
  @max_count 50_000

  @dec "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
  @line_sep "\n"
  @line_sep_length String.length(@line_sep)

  @index_start "<sitemapindex xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xsi:schemaLocation=\"http://www.sitemaps.org/schemas/sitemap/0.9 http://www.sitemaps.org/schemas/sitemap/0.9/siteindex.xsd\" xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">"
  @index_end "</sitemapindex>"

  @index_end_length String.length(@index_end) + @line_sep_length
  @index_max_length_offset @max_length - @index_end_length

  @feed_start "<rss xmlns:g=\"http://base.google.com/ns/1.0\" version=\"2.0\"><channel>"
  @feed_end "</channel></rss>"

  @feed_end_length String.length(@feed_end) + @line_sep_length
  @feed_max_length_offset @max_length - @feed_end_length

  def ping(_base_url) do
    :ok
  end

  # Callback functions to generate a new Feed
  def new_index() do
    body = [@dec, @line_sep, @index_start, @line_sep]
    length = IO.iodata_length(body)
    %File{count: 0, length: length, body: body}
  end

  def create_index_item(loc, opts) do
    lastmod = Keyword.get(opts, :index_lastmod, Date.utc_today())

    %Index{loc: loc, lastmod: lastmod}
  end

  def add_index_item(
        %File{count: count, length: length, body: body},
        %Index{} = reference
      ) do
    element =
      sitemap_element(reference)
      |> XmlBuilder.generate()

    element_length = IO.iodata_length(element)
    new_length = length + element_length + @line_sep_length
    new_count = count + 1

    cond do
      new_length >= @index_max_length_offset ->
        {:error, :over_length}

      new_count > @max_count ->
        {:error, :over_count}

      true ->
        new_body = [body, element, @line_sep]
        %File{count: new_count, length: new_length, body: new_body}
    end
  end

  def finalize_index(%File{count: count, length: length, body: body}) do
    new_body = [body, @index_end, @line_sep]
    new_length = length + @index_end_length
    %File{count: count, length: new_length, body: new_body}
  end

  # Callback functions to generate a new Feed
  def new_feed(opts) do
    feed_config = Keyword.get(opts, :feed_config, [])
    title = Keyword.get(feed_config, :title, "")
    link = Keyword.get(feed_config, :link, "")
    description = Keyword.get(feed_config, :description, "")

    channel_header =
      [
        XmlBuilder.element(:title, title),
        XmlBuilder.element(:link, link),
        XmlBuilder.element(:description, description)
      ]
      |> XmlBuilder.generate()

    body = [@dec, @line_sep, @feed_start, @line_sep, channel_header, @line_sep]

    length = IO.iodata_length(body)
    %File{count: 0, length: length, body: body}
  end

  def add_feed_item(%File{count: count, length: length, body: body}, %Item{} = item, _opts) do
    element =
      item_element(item)
      |> XmlBuilder.generate()

    element_length = IO.iodata_length(element)
    new_length = length + element_length + @line_sep_length
    new_count = count + 1

    cond do
      new_length >= @feed_max_length_offset ->
        {:error, :over_length}

      new_count > @max_count ->
        {:error, :over_count}

      true ->
        new_body = [body, element, @line_sep]
        %File{count: new_count, length: new_length, body: new_body}
    end
  end

  def finalize_feed(%File{count: count, length: length, body: body}, _opts) do
    new_body = [body, @feed_end, @line_sep]
    new_length = length + @feed_end_length
    %File{count: count, length: new_length, body: new_body}
  end

  defp item_element(%Item{} = item) do
    elements =
      [:id, :title, :description, :link]
      |> Enum.reduce([], fn k, acc ->
        case Map.get(item, k) do
          nil ->
            acc

          v ->
            acc ++ [{"g:#{k}", Encoder.encode(v)}]
        end
      end)

    XmlBuilder.element(:item, elements)
  end

  defp sitemap_element(%Index{} = reference) do
    elements =
      [:loc, :lastmod]
      |> Enum.reduce([], fn k, acc ->
        case Map.get(reference, k) do
          nil ->
            acc

          v ->
            acc ++ [{k, Encoder.encode(v)}]
        end
      end)

    XmlBuilder.element(:sitemap, elements)
  end
end
