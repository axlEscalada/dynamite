#!/bin/sh

# List all DynamoDB tables
# aws --endpoint-url=http://localhost:4566 dynamodb list-tables
tables=$(aws --endpoint-url=http://localhost:4566 dynamodb list-tables --output text --query 'TableNames[*]')

# Loop through each table and delete it
for table in $tables
do
    echo "Deleting table: $table"
    aws --endpoint-url=http://localhost:4566 dynamodb delete-table --table-name "$table"
done

echo "All DynamoDB tables have been deleted."
