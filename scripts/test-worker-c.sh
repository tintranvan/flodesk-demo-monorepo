#!/bin/bash

API_URL="https://raznxe6xd7.execute-api.us-east-1.amazonaws.com/latest/api-svc-a"

echo "Sending 100 messages to worker-c..."

for i in {1..30}; do
  # Send to both endpoints that route to worker-c
  curl -s -X POST "$API_URL/process" \
    -H "Content-Type: application/json" \
    -d "{\"query\":\"test-$i\",\"data\":{\"id\":$i}}" > /dev/null
  
  curl -s -X POST "$API_URL/complete" \
    -H "Content-Type: application/json" \
    -d "{\"query\":\"complete-$i\",\"result\":\"success\",\"id\":$i}" > /dev/null
  
  echo "Sent messages $i to worker-c"
done

echo "Done! 200 messages sent to worker-c"
