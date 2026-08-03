defmodule Droom.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: Droom.PubSub},
      {DynamicSupervisor, name: Droom.ConnectionSupervisor, strategy: :one_for_one},
      {DynamicSupervisor, name: Droom.DiscoverySupervisor, strategy: :one_for_one},
      {DynamicSupervisor, name: Droom.HEOSSupervisor, strategy: :one_for_one}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Droom.Supervisor)
  end
end
