# syntax=docker/dockerfile:1

# cargo-chef splits the build into a "cook deps" layer keyed only on
# Cargo.toml/Cargo.lock and a final layer keyed on the real source. This
# means a source-only change (the common case on every push to `main`)
# reuses the dependency-compile layer from cache instead of rebuilding the
# whole tree (sqlx, libsql, turso, ...) from scratch every time.
FROM rust:1.95.0-alpine3.22 AS chef
RUN apk add --no-cache musl-dev
RUN cargo install cargo-chef --locked
WORKDIR /usr/src/app

FROM chef AS planner
COPY . .
RUN cargo chef prepare --recipe-path recipe.json

FROM chef AS builder
# Which [profile.*] in Cargo.toml to build with. Defaults to the
# size/LTO-optimized `release` profile used for official tagged releases
# (docker.yaml/rust.yaml, crates.io). main-publish.yaml overrides this to
# the faster `ci-release` profile for per-commit `main` builds, where
# CI turnaround matters more than shaving binary size/runtime perf.
ARG CARGO_PROFILE=release
COPY --from=planner /usr/src/app/recipe.json recipe.json
RUN cargo chef cook --profile ${CARGO_PROFILE} --recipe-path recipe.json
COPY . .
RUN cargo build --profile ${CARGO_PROFILE} \
    && cp target/${CARGO_PROFILE}/geni /usr/src/app/geni

FROM alpine:3.19.1
COPY --from=builder /usr/src/app/geni /usr/src/app/geni

ENV DATABASE_MIGRATIONS_FOLDER="/migrations"

LABEL org.opencontainers.image.description="Geni: Standalone database migration tool which works for Postgres, MariaDB, MySQL, Sqlite and LibSQL(Turso)."

WORKDIR /usr/src/app

ENTRYPOINT ["./geni"]
