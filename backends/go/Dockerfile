FROM golang:1.27-alpine AS build
WORKDIR /src
COPY go.mod main.go ./
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /knock .

FROM scratch
COPY --from=build /knock /knock
USER 65532:65532
EXPOSE 8080
ARG VERSION=dev
ENV VERSION=$VERSION
ENTRYPOINT ["/knock"]
