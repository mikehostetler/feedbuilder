defmodule Bench.FastSitemap do
  use Sitemap

  def simple(range) do
    create host: "https://example.com",
           files_path: Path.join(__DIR__, "fast_sitemap"),
           public_path: "sitemaps" do
      for n <- range do
        add("#{n}", lastmod: DateTime.utc_now())
      end
    end
  end
end

defmodule Bench.Feedbuilder do
  alias Feedbuilder.Sitemap.Item

  def simple(range) do
    config = [
      base_url: "https://example.com/sitemaps",
      generator: Feedbuilder.Sitemap,
      name_prefix: "sitemap",
      store: Feedbuilder.FileStore,
      store_config: [
        path: Path.join(__DIR__, "feedbuilder")
      ]
    ]

    range
    |> Stream.map(fn i ->
      %Item{loc: "#{i}", lastmod: DateTime.utc_now()}
    end)
    |> Feedbuilder.generate(config)
    |> Feedbuilder.persist(config)
    |> Stream.run()
  end
end

:observer.start()

Benchee.run(
  [
    {"fast_sitemap - simple", fn range -> Bench.FastSitemap.simple(range) end},
    {"feedbuilder - simple", fn range -> Bench.Feedbuilder.simple(range) end}
  ],
  time: 10,
  formatters: [
    Benchee.Formatters.HTML,
    Benchee.Formatters.Console
  ],
  inputs: %{
    "small" => 1..1_000,
    "medium" => 1..100_000,
    "large" => 1..1_000_000
  }
)
