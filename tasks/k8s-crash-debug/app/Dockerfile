# Stage 1: Build the Go binary
FROM golang:1.19-alpine AS builder

WORKDIR /app

# Copy the Go module files and download dependencies
COPY go.mod go.sum ./
RUN go mod download

# Copy the source code
COPY . .

# Build the binary
# The -o flag specifies the output file name
RUN CGO_ENABLED=0 GOOS=linux go build -o /go-app

# Stage 2: Create the final, minimal image
FROM alpine:latest

# It's good practice to run as a non-root user
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser

WORKDIR /home/appuser

# Copy the built binary from the builder stage
COPY --from=builder /go-app .

# Expose the port the app runs on
EXPOSE 8080

# This command will run the application
# The user will need to fix the code so this runs without crashing
ENTRYPOINT ["./go-app"]
