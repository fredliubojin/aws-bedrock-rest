#!/bin/bash

# Ensure AWS_ACCOUNT_ID and AWS_REGION are set
if [ -z "$AWS_ACCOUNT_ID" ] || [ -z "$AWS_REGION" ] || [ -z "$ADMIN_API_KEY" ]; then
  echo "Please set the environment variables AWS_ACCOUNT_ID, AWS_REGION and ADMIN_API_KEY before running this script."
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

# Create apprunner-exe-trust-policy.json
cat > apprunner-exe-trust-policy.json << EOL
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "tasks.apprunner.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOL

# Create apprunner-beckrock-policy.json to allow InvokeModel action on bedrock model resource

cat > apprunner-beckrock-policy.json << EOL
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "bedrock:InvokeModel",
      "Resource": "arn:aws:bedrock:${AWS_REGION}::foundation-model/anthropic.claude-v2"
    },
    {
      "Effect": "Allow",
      "Action": "bedrock:InvokeModelWithResponseStream",
      "Resource": "arn:aws:bedrock:${AWS_REGION}::foundation-model/anthropic.claude-v2"
    }
  ]
}
EOL

# create apprunner-bedrock-secret-manager.json to allow read and write permission to secret manager to all secrets

# Create the IAM apprunner-beckrock-policy
aws iam create-policy --policy-name AppRunnerServiceRoleExecutionPolicy --policy-document file://apprunner-beckrock-policy.json

# Create the IAM role
aws iam create-role --role-name AppRunnerServiceRoleForECRAccess --assume-role-policy-document file://apprunner-trust-policy.json
aws iam create-role --role-name AppRunnerServiceRoleForExecution --assume-role-policy-document file://apprunner-exe-trust-policy.json

# Attach the required policies
aws iam attach-role-policy --role-name AppRunnerServiceRoleForECRAccess --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
aws iam attach-role-policy --role-name AppRunnerServiceRoleForECRAccess --policy-arn arn:aws:iam::aws:policy/service-role/AWSAppRunnerServicePolicyForECRAccess
aws iam attach-role-policy --role-name AppRunnerServiceRoleForExecution --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AppRunnerServiceRoleExecutionPolicy
aws iam attach-role-policy --role-name AppRunnerServiceRoleForExecution --policy-arn arn:aws:iam::aws:policy/SecretsManagerReadWrite

# Get the ARN of the created role
ROLE_ARN=$(aws iam get-role --role-name AppRunnerServiceRoleForECRAccess --query 'Role.Arn' --output text)
INSTANCE_ROLE_ARN=$(aws iam get-role --role-name AppRunnerServiceRoleForExecution --query 'Role.Arn' --output text)

# Update the apprunner-service.json file with the ARN of the created role
cat > apprunner-service.json << EOL
{
  "SourceConfiguration": {
    "AuthenticationConfiguration": {
      "AccessRoleArn": "${ROLE_ARN}"
    },
    "ImageRepository": {
      "ImageIdentifier": "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/bedrock-rest:latest",
      "ImageRepositoryType": "ECR",
      "ImageConfiguration": {
        "Port": "8080",
        "RuntimeEnvironmentVariables": {
            "ADMIN_API_KEY": "${ADMIN_API_KEY}"
        }
      }
    }
  },
  "InstanceConfiguration": {
    "Cpu": "1 vCPU",
    "Memory": "2 GB",
    "InstanceRoleArn": "${INSTANCE_ROLE_ARN}"
  },
  "ServiceName": "bedrock-rest"
}
EOL

# Clean up
rm apprunner-trust-policy.json
rm apprunner-beckrock-policy.json
rm apprunner-exe-trust-policy.json

echo "The IAM role has been created and the apprunner-service.json file has been updated."