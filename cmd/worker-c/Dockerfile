FROM --platform=linux/arm64 golang:1.22-alpine AS builder

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -o worker-c ./cmd/worker-c/main.go

FROM --platform=linux/arm64 alpine:latest
RUN apk --no-cache add ca-certificates
WORKDIR /root/

COPY --from=builder /app/worker-c .

EXPOSE 8080

CMD ["./worker-c"]
