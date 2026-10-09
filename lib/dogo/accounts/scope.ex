defmodule Dogo.Accounts.Scope do
  @moduledoc """
  Defines the scope of the caller to be used throughout the app.

  The `Dogo.Accounts.Scope` allows public interfaces to receive
  information about the caller, such as if the call is initiated from an
  end-user, and if so, which user. Additionally, such a scope can carry fields
  such as "super user" or other privileges for use in authorization checks,
  or to ensure specific code paths can only be accessed for a given scope.

  It is useful for logging as well as for scoping pubsub subscriptions and
  broadcasts when a caller subscribes to an interface or performs a particular
  action.

  Feel free to extend the fields on this struct to fit the needs of
  growing application requirements.
  """

  alias Dogo.Accounts.Admin

  defstruct admin: nil

  @doc """
  Creates a scope for the given admin.

  Returns nil if no admin is given.
  """
  def for_admin(%Admin{} = admin) do
    %__MODULE__{admin: admin}
  end

  def for_admin(nil), do: nil
end
