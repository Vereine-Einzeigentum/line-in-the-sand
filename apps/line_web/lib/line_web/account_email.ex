defmodule LineWeb.AccountEmail do
  import Swoosh.Email

  @from {"LINE IN THE SAND", "noreply@example.com"}

  def temp_password(to_address, player_name, temp_pass) do
    new()
    |> to(to_address)
    |> from(@from)
    |> subject("LINE IN THE SAND — your temporary password")
    |> text_body("""
    #{player_name},

    Your account has been requested.

    Temporary password: #{temp_pass}

    Log in and you will be prompted to set a permanent password
    during character creation.

    — LINE IN THE SAND
    """)
  end
end
