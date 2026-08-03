for file <- Path.wildcard("test/support/*.exs") do
  Code.require_file(file)
end

ExUnit.start(exclude: [:live])
