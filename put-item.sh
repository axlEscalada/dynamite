aws dynamodb put-item --table-name Users --item "{\"Username\":{\"S\":\"milos\"}, \"id\":{\"S\":\"2\"}}" --endpoint-url=http://localhost:4566
aws dynamodb put-item \
    --endpoint-url http://localhost:4566 \
    --table-name Users \
    --item '{
        "id": {"S": "1234567890"},
        "name": {"S": "John Doe Milo Axl Bichy river"},
        "age": {"N": "30"},
        "email": {"S": "john.doe@example.com"},
        "is_active": {"BOOL": true},
        "last_login": {"S": "2023-08-20T14:30:00Z"}
    }'
aws dynamodb put-item \ 
    --endpoint-url http://localhost:4566 \
    --table-name Users \ 
    --item '{
        "id": {"S": "1234567890"},
        "name": {"S": "John Doe"},
        "age": {"N": "30"},
        "email": {"S": "john.doe@example.com"},
        "is_active": {"BOOL": true},
        "last_login": {"S": "2023-08-20T14:30:00Z"},
        "address": {"S": "Av Nazca y Juan b justo 123486666666"},
        "phone_number": {"S": "+1-555-123-4567"},
        "registration_date": {"S": "2023-01-15"},
        "preferences": {"M": {"theme": {"S": "dark"}, "notifications": {"BOOL": true}}},
        "account_balance": {"N": "100.50"}
    }'
