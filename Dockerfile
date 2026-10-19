ARG ELIXIR_IMAGE=elixir:1.18.4-otp-27-slim

FROM ${ELIXIR_IMAGE} AS build

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends build-essential git npm && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app
ENV MIX_ENV=prod

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
COPY config ./config
COPY apps ./apps

RUN mix deps.get --only prod
RUN mix deps.compile
RUN mix compile

WORKDIR /app/apps/line_web/assets
RUN npm ci
RUN npm run build

WORKDIR /app/apps/line_web
RUN mix phx.digest

WORKDIR /app
RUN mix release lits

FROM ${ELIXIR_IMAGE} AS runtime

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends openssl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app
ENV MIX_ENV=prod

COPY --from=build /app/_build/prod/rel/lits ./

CMD ["bin/lits", "start"]
