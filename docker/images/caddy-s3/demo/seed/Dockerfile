FROM golang:1.26-alpine AS builder

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY main.go ./
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /seed main.go

FROM alpine:3.22
RUN adduser -D -u 10001 seed
COPY --from=builder /seed /usr/local/bin/seed
USER seed
ENTRYPOINT ["/usr/local/bin/seed"]
