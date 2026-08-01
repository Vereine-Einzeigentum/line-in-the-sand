#!/bin/bash
# SessionStart hook: provision Elixir/OTP + Postgres for Claude Code on the web.
# Installs OTP 26 + Elixir 1.16 (precompiled, checksum-verified), fetches mix
# deps, and starts PostgreSQL so `mix test` works out of the box.
set -euo pipefail

# Only needed in remote (web) sessions; local machines manage their own toolchain.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

OTP_VERSION="26.2.5.9"
OTP_SHA256="aa91509f4d474487c28de4918d494e5022771fcb72e46b4e76343e46fa2c09eb"
ELIXIR_VERSION="1.16.3"
ELIXIR_SHA256="339f7f303c676ca94e54fe41dd02117f7b6b4906c9f7019026e98ede6ff4b233"
BEAM_DIR="/opt/beam"

export PATH="$BEAM_DIR/otp/bin:$BEAM_DIR/elixir/bin:$PATH"
export LANG=C.UTF-8 LC_ALL=C.UTF-8

# --- Erlang/OTP (precompiled for ubuntu-24.04 from builds.hex.pm) ---
if [ ! -x "$BEAM_DIR/otp/bin/erl" ]; then
  mkdir -p "$BEAM_DIR"
  curl -sSfL -o "$BEAM_DIR/otp.tar.gz" \
    "https://builds.hex.pm/builds/otp/amd64/ubuntu-24.04/OTP-${OTP_VERSION}.tar.gz"
  echo "$OTP_SHA256  $BEAM_DIR/otp.tar.gz" | sha256sum -c -
  tar xzf "$BEAM_DIR/otp.tar.gz" -C "$BEAM_DIR"
  rm -rf "$BEAM_DIR/otp"
  mv "$BEAM_DIR/OTP-${OTP_VERSION}" "$BEAM_DIR/otp"
  (cd "$BEAM_DIR/otp" && ./Install -minimal "$BEAM_DIR/otp" >/dev/null)
  rm -f "$BEAM_DIR/otp.tar.gz"
fi

# --- Elixir (precompiled against OTP 26 from builds.hex.pm) ---
if [ ! -x "$BEAM_DIR/elixir/bin/elixir" ]; then
  curl -sSfL -o "$BEAM_DIR/elixir.zip" \
    "https://builds.hex.pm/builds/elixir/v${ELIXIR_VERSION}-otp-26.zip"
  echo "$ELIXIR_SHA256  $BEAM_DIR/elixir.zip" | sha256sum -c -
  mkdir -p "$BEAM_DIR/elixir"
  unzip -qo "$BEAM_DIR/elixir.zip" -d "$BEAM_DIR/elixir"
  rm -f "$BEAM_DIR/elixir.zip"
fi

# --- Persist environment for the session ---
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  {
    echo "export PATH=\"$BEAM_DIR/otp/bin:$BEAM_DIR/elixir/bin:\$PATH\""
    echo "export LANG=C.UTF-8"
    echo "export LC_ALL=C.UTF-8"
  } >> "$CLAUDE_ENV_FILE"
fi

# --- PostgreSQL (preinstalled in the container image, but not running) ---
if ! pg_isready -q 2>/dev/null; then
  sudo service postgresql start
  for _ in $(seq 1 15); do
    pg_isready -q && break
    sleep 1
  done
fi
sudo -u postgres psql -qc "ALTER USER postgres WITH PASSWORD 'postgres';"

# --- Project dependencies ---
cd "$CLAUDE_PROJECT_DIR"
mix local.hex --force --if-missing
mix local.rebar --force --if-missing
mix deps.get

# --- Frontend assets (Svelte + Vite) ---
if [ -f apps/line_web/assets/package-lock.json ]; then
  npm install --prefix apps/line_web/assets
fi

# Warm the test build so `mix test` is fast on first use. The `test` alias
# also creates and migrates the test database.
MIX_ENV=test mix compile

echo "session-start: Elixir $(elixir --short-version 2>/dev/null || true) / OTP ${OTP_VERSION} ready, Postgres up, deps compiled"
