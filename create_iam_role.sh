#!/bin/bash

# Ensure AWS_ACCOUNT_ID and AWS_REGION are set
if [ -z "$AWS_ACCOUNT_ID" ] || [ -z "$AWS_REGION" ]; then
  echo "Please set the environment variables AWS_ACCOUNT_ID and AWS_REGION before running this script."
  exit 1
fi

# Create apprunner-trust-policy.json
cat > apprunner-trust-policy.json << EOL
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "build.apprunner.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOL

# Create the IAM role
aws iam create-role --role-name AppRunnerServiceRoleForECRAccess --assume-role-policy-document file://apprunner-trust-policy.json

# Attach the required policies
aws iam attach-role-policy --role-name AppRunnerServiceRoleForECRAccess --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
aws iam attach-role-policy --role-name AppRunnerServiceRoleForECRAccess --policy-arn arn:aws:iam::aws:policy/service-role/AWSAppRunnerServicePolicyForECRAccess

# Get the ARN of the created role
ROLE_ARN=$(aws iam get-role --role-name AppRunnerServiceRoleForECRAccess --query 'Role.Arn' --output text)

# Update the apprunner-service.json file with the ARN of the created role
cat > apprunner-service.json << EOL
{
  "SourceConfiguration": {
    "AuthenticationConfiguration": {
      "AccessRoleArn": "${ROLE_ARN}"
    },
    "ImageRepository": {
      "ImageIdentifier": "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/my-fastapi-app:latest",
      "ImageRepositoryType": "ECR"
    }
  },
  "InstanceConfiguration": {
    "Cpu": "1 vCPU",
    "Memory": "2 GB"
  },
  "ServiceName": "my-fastapi-app"
}
EOL

# Clean up
rm apprunner-trust-policy.json

echo "The IAM role has been created and the apprunner-service.json file has been updated."