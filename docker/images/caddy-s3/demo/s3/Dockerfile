FROM golang:1.26-alpine AS builder

WORKDIR /src
COPY go.mod main.go ./
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /s3 main.go

FROM alpine:3.23
RUN adduser -D -u 10001 s3
COPY --from=builder /s3 /usr/local/bin/s3
USER s3
ENTRYPOINT ["/usr/local/bin/s3"]
