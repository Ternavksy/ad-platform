FROM golang:1.25-alpine

WORKDIR /app

# Copy go mod files
COPY go.mod go.sum ./

# Download dependencies
RUN go mod download

# Copy source code
COPY . .

# Build the application
RUN go build -o worker .

# Expose port if needed (not required for worker)
# EXPOSE 8080

# Run the worker
CMD ["./worker"]