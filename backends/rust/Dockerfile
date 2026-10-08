# rust:alpine targets musl, which links statically by default: the binary runs on distroless/static.
FROM rust:1.98-alpine AS build
WORKDIR /src
COPY Cargo.toml Cargo.lock ./
COPY src src
RUN cargo build --release --locked

FROM gcr.io/distroless/static:nonroot
COPY --from=build /src/target/release/knock /knock
EXPOSE 8080
ARG VERSION=dev
ENV VERSION=$VERSION
ENTRYPOINT ["/knock"]
