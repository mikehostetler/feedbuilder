defmodule Feedbuilder.File do
  @enforce_keys [:count, :length, :body]
  defstruct [:count, :length, :body]
end
