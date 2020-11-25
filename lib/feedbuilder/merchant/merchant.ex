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

  @feed_start "<urlset xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xsi:schemaLocation=\"http://www.sitemaps.org/schemas/sitemap/0.9 http://www.sitemaps.org/schemas/sitemap/0.9/sitemap.xsd\" xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">"
  @feed_end "</urlset>"

  @feed_end_length String.length(@feed_end) + @line_sep_length
  @feed_max_length_offset @max_length - @feed_end_length

  @ping_urls [
    "http://google.com/ping?sitemap=%s",
    "http://www.bing.com/webmaster/ping.aspx?sitemap=%s"
  ]

  def ping(base_url) do
    @ping_urls
    |> Enum.map(fn url ->
      ping_url = String.replace(url, "%s", base_url)
      :httpc.request('#{ping_url}')
    end)
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
  def new_feed() do
    body = [@dec, @line_sep, @feed_start, @line_sep]
    length = IO.iodata_length(body)
    %File{count: 0, length: length, body: body}
  end

  def add_feed_item(%File{count: count, length: length, body: body}, %Item{} = url) do
    element =
      url_element(url)
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

  def finalize_feed(%File{count: count, length: length, body: body}) do
    new_body = [body, @feed_end, @line_sep]
    new_length = length + @feed_end_length
    %File{count: count, length: new_length, body: new_body}
  end

  defp url_element(%Item{} = url) do
    elements =
      [:loc, :lastmod, :changefreq, :priority]
      |> Enum.reduce([], fn k, acc ->
        case Map.get(url, k) do
          nil ->
            acc

          v ->
            acc ++ [{k, Encoder.encode(v)}]
        end
      end)

    XmlBuilder.element(:url, elements)
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
