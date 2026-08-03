defmodule Droom.MixProject do
  use Mix.Project

  # Some tooling (e.g. the `.expert` indexer) compiles the project without the
  # standard OTP lib dirs on the code path, so `:xmerl_sax_parser` would be
  # reported as undefined. Ensure the app's ebin is resolvable at compile time.
  unless Code.ensure_loaded?(:xmerl_sax_parser) do
    case Path.wildcard(Path.join([List.to_string(:code.lib_dir()), "xmerl-*", "ebin"])) do
      [ebin | _] -> :code.add_patha(String.to_charlist(ebin))
      _ -> :ok
    end
  end

  def project do
    [
      app: :droom,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      description:
        "Control UPnP/DLNA media renderers via SSDP discovery and SOAP (AVTransport/RenderingControl)",
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :inets, :ssl, :xmerl],
      mod: {Droom.Application, []}
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:phoenix_pubsub, "~> 2.1"}
    ]
  end
end
