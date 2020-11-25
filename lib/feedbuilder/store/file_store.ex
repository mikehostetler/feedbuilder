defmodule Feedbuilder.FileStore do
  @behaviour Feedbuilder.Store

  def write(filename, data, config) do
    store_path = Keyword.fetch!(config, :path)
    file_path = Path.join(store_path, filename)
    File.write!(file_path, data, [:write])
  end
end
