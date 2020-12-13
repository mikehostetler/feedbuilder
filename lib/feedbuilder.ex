defmodule Feedbuilder do
  @moduledoc """
  Feedbuilder is an Elixir library for generating XML Feeds using Streams.
  It currently supports three feed formats:

  * [XML Sitemaps](https://www.sitemaps.org)
  * [Google Merchant](https://support.google.com/merchants/answer/160567?hl=en&ref_topic=3163841)

  Inspiration and design was taken from [Sitemapper](https://github.com/tomtaylor/sitemapper).  Many thanks
  to that project and their contribution.

  Feedbuilder is designed for generating large feeds quickly and efficiently,
  with the ability to persist those feeds to Amazon S3.

  It is also designed to be easily extended to support additional formats, should
  the need arise.
  """

  alias Feedbuilder.File

  @spec generate(stream :: Enumerable.t(), opts :: keyword) :: Stream.t()
  def generate(enum, opts) do
    generator = Keyword.fetch!(opts, :generator)
    name = Keyword.get(opts, :name)
    name_prefix = Keyword.get(opts, :name_prefix, "")
    gzip_enabled = Keyword.get(opts, :gzip, true)
    index_enabled = Keyword.get(opts, :index, true)

    enum
    |> Stream.concat([:end])
    |> Stream.transform(nil, &accumulate_feed_item(&1, &2, generator, opts))
    |> Stream.transform(1, &reduce_file_to_name_and_body(&1, &2, name, name_prefix, gzip_enabled))
    |> Stream.concat([:end])
    # |> Stream.map(&maybe_generate_index(&1, index_enabled))
    |> Stream.transform(nil, &accumulate_feed_index(&1, &2, generator, opts))
    |> Stream.map(&maybe_gzip_body(&1, gzip_enabled))
  end

  @doc """
  Receives a `Stream` of `{filename, body}` tuples, and persists
  those to the `Feedbuilder.Store`.

  Will raise if persistence fails.

  Accepts the following `Keyword` options in `opts`:

  * `store` - The module of the desired `Feedbuilder.Store`,
    such as `Feedbuilder.S3Store`. (required)

  * `store_config` -  A `Keyword` list with options for the
    `Feedbuilder.Store`. (optional, but usually required)
  """
  @spec persist(Enumerable.t(), keyword) :: Stream.t()
  def persist(enum, opts) do
    store = Keyword.fetch!(opts, :store)
    store_config = Keyword.get(opts, :store_config, [])

    enum
    |> Stream.each(fn {filename, body} ->
      :ok = store.write(filename, body, store_config)
    end)
  end

  @doc """
  Receives a `Stream` of `{filename, body}` tuples, takes the last
  one (the index file), and pings Google and Bing with its URL.
  """
  @spec ping(Enumerable.t(), keyword) :: Stream.t()
  def ping(enum, opts) do
    generator = Keyword.fetch!(opts, :generator)
    base_url = Keyword.fetch!(opts, :base_url)

    enum
    |> Stream.take(-1)
    |> Stream.map(fn {filename, _body} ->
      index_url =
        URI.parse(base_url)
        |> join_uri_and_filename(filename)
        |> URI.to_string()

      generator.ping(index_url)
    end)
  end

  defp accumulate_feed_item(:end, nil, _generator, _opts) do
    {[], nil}
  end

  defp accumulate_feed_item(:end, progress, generator, opts) do
    done = generator.finalize_feed(progress, opts)
    {[done], nil}
  end

  defp accumulate_feed_item(item, nil, generator, opts) do
    accumulate_feed_item(item, generator.new_feed(opts), generator, opts)
  end

  defp accumulate_feed_item(item, progress, generator, opts) do
    case generator.add_feed_item(progress, item, opts) do
      {:error, reason} when reason in [:over_length, :over_count] ->
        done = generator.finalize_feed(progress, opts)
        next = generator.new_feed(opts) |> generator.add_feed_item(item, opts)
        {[done], next}

      new_progress ->
        {[], new_progress}
    end
  end

  defp accumulate_feed_index(:end, nil, _generator, _opts) do
    {[], nil}
  end

  defp accumulate_feed_index(:end, index_file, generator, opts) do
    name = Keyword.get(opts, :name)
    name_prefix = Keyword.get(opts, :name_prefix, "")
    gzip_enabled = Keyword.get(opts, :gzip, true)

    done_file = generator.finalize_index(index_file)
    {filename, body} = index_file_to_data_and_name(done_file, name, name_prefix, gzip_enabled)
    {[{filename, body}], nil}
  end

  defp accumulate_feed_index({filename, body}, nil, generator, opts) do
    accumulate_feed_index({filename, body}, generator.new_index(), generator, opts)
  end

  defp accumulate_feed_index({filename, body}, index_file, generator, opts) do
    base_url = Keyword.fetch!(opts, :base_url)

    loc =
      URI.parse(base_url)
      |> join_uri_and_filename(filename)
      |> URI.to_string()

    reference = generator.create_index_item(loc, opts)

    case generator.add_index_item(index_file, reference) do
      {:error, reason} when reason in [:over_length, :over_count] ->
        raise "Generated too many feed index entries"

      new_file ->
        {[{filename, body}], new_file}
    end
  end

  defp reduce_file_to_name_and_body(%File{body: body}, counter, name, name_prefix, gzip_enabled) do
    {[{filename(name, name_prefix, gzip_enabled, counter), body}], counter + 1}
  end

  defp maybe_gzip_body({filename, body}, true) do
    {filename, :zlib.gzip(body)}
  end

  defp maybe_gzip_body({filename, body}, false) do
    {filename, body}
  end

  defp join_uri_and_filename(%URI{path: nil} = uri, filename) do
    URI.merge(uri, filename)
  end

  defp join_uri_and_filename(%URI{path: path} = uri, filename) do
    path = Path.join(path, filename)
    URI.merge(uri, path)
  end

  defp index_file_to_data_and_name(%File{body: body}, name, name_prefix, gzip_enabled) do
    {filename(name, name_prefix, gzip_enabled), body}
  end

  defp filename(name, name_prefix, gzip, count \\ nil) do
    prefix = [name_prefix, name] |> Enum.reject(&is_nil/1) |> Enum.join("-")

    suffix =
      case count do
        nil ->
          ""

        c ->
          str = Integer.to_string(c)
          "-" <> String.pad_leading(str, 5, "0")
      end

    extension =
      case gzip do
        true -> ".xml.gz"
        false -> ".xml"
      end

    prefix <> suffix <> extension
  end
end
