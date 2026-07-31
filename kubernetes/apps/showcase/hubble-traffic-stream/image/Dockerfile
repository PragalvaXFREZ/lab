FROM golang:1.26.5-alpine AS build

WORKDIR /src
COPY go.mod main.go ./
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/hubble-traffic-streamer .

FROM gcr.io/distroless/static-debian12:nonroot

LABEL org.opencontainers.image.source="https://github.com/PragalvaXFREZ/lab"
LABEL org.opencontainers.image.description="Outbound-only aggregate Hubble traffic producer for devata"

COPY --from=build /out/hubble-traffic-streamer /hubble-traffic-streamer
ENTRYPOINT ["/hubble-traffic-streamer"]
