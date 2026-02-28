FROM golang:1.25-alpine AS builder
WORKDIR /app
COPY . .
RUN go mod download && GOOS=linux GOARCH=amd64 go build -o /bin/ads-api ./cmd/server

FROM alpine:3.18
COPY --from=builder /bin/ads-api /bin/ads-api
EXPOSE 8080
ENTRYPOINT ["/bin/ads-api"]