defmodule Feedbuilder.Feed do
  # @callback write(filename :: String.t(), body :: IO.chardata(), config :: Keyword.t()) ::
  #             :ok | {:error, atom()}
end
