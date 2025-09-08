#!/bin/bash

API_URL="https://raznxe6xd7.execute-api.us-east-1.amazonaws.com/latest/api-svc-a"

echo "Sending 100 messages to worker-d..."

for i in {1..50}; do
  curl -s -X POST "$API_URL/process" \
    -H "Content-Type: application/json" \
    -d "{\"query\":\"test-$i\",\"data\":{\"id\":$i}}" > /dev/null
  echo "Sent message $i to worker-d"
done

echo "Done! 100 messages sent to worker-d"
