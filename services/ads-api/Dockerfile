FROM golang:1.25-alpine AS dependencies
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download

FROM dependencies AS test
RUN apk add --no-cache build-base sqlite-dev
COPY . .
RUN CGO_ENABLED=1 go test ./... && go vet ./...

FROM dependencies AS builder
COPY . .
RUN GOOS=linux GOARCH=amd64 go build -o /bin/ads-api ./cmd/server

FROM alpine:3.18
COPY --from=builder /bin/ads-api /bin/ads-api
EXPOSE 8080
ENTRYPOINT ["/bin/ads-api"]
