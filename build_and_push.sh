#!/bin/bash

# Check if we should update the service
UPDATE_SERVICE="$1"

# Ensure AWS_ACCOUNT_ID and AWS_REGION are set
if [ -z "$AWS_ACCOUNT_ID" ] || [ -z "$AWS_REGION" ] || [ -z "$ADMIN_API_KEY" ]; then
  echo "Please set the environment variables AWS_ACCOUNT_ID, AWS_REGION and ADMIN_API_KEY before running this script."
  exit 1
fi

# Set the required variables from the environment
account_id=${AWS_ACCOUNT_ID}
region=${AWS_REGION}
service_name=bedrock-rest
admin_api_key=${ADMIN_API_KEY}

# Set ECR repository
ECR_REPOSITORY=$account_id.dkr.ecr.$region.amazonaws.com/$service_name

# Login to ECR
aws ecr get-login-password --region $region | docker login --username AWS --password-stdin $ECR_REPOSITORY

# Build the Docker image
docker build -t $service_name .

# Tag the image with the ECR repository URI
docker tag $service_name:latest $ECR_REPOSITORY:latest

# Push the image to ECR
docker push $ECR_REPOSITORY:latest

if [ "$UPDATE_SERVICE" == "update" ]; then
  # Get the ARN of the created role
  ROLE_ARN=$(aws iam get-role --role-name AppRunnerServiceRoleForECRAccess --query 'Role.Arn' --output text)
  INSTANCE_ROLE_ARN=$(aws iam get-role --role-name AppRunnerServiceRoleForExecution --query 'Role.Arn' --output text)

  # Create an update-service.json file with the new image URI
  cat > update-service.json << EOF
{
  "ServiceArn": "$(aws apprunner list-services --region $region --query "ServiceSummaryList[?ServiceName=='$service_name'].ServiceArn | [0]" --output text)",
  "SourceConfiguration": {
    "AuthenticationConfiguration": {
      "AccessRoleArn": "${ROLE_ARN}"
    },
    "ImageRepository": {
      "ImageIdentifier": "$ECR_REPOSITORY:latest",
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
  }
}
EOF

  # Update the App Runner service using the update-service.json file
  aws apprunner update-service --cli-input-json file://update-service.json --region $region

  # Clean up the update-service.json file
  rm update-service.json
else
  # Retrieve the ARN of your App Runner service
  service_arn=$(aws apprunner list-services --region $region --query "ServiceSummaryList[?ServiceName=='$service_name'].ServiceArn | [0]" --output text)

  echo $service_arn

  # Trigger a manual deployment of the updated image in AWS App Runner
  aws apprunner start-deployment --service-arn $service_arn --region $region
fi

# #!/bin/bash

# # Ensure AWS_ACCOUNT_ID and AWS_REGION are set
# if [ -z "$AWS_ACCOUNT_ID" ] || [ -z "$AWS_REGION" ]; then
#   echo "Please set the environment variables AWS_ACCOUNT_ID and AWS_REGION before running this script."
#   exit 1
# fi

# # Set the required variables from the environment
# account_id=${AWS_ACCOUNT_ID}
# region=${AWS_REGION}
# service_name=bedrock-rest

# # Set ECR repository
# ECR_REPOSITORY=$account_id.dkr.ecr.$region.amazonaws.com/$service_name

# # Login to ECR
# aws ecr get-login-password --region $region | docker login --username AWS --password-stdin $ECR_REPOSITORY

# # Build the Docker image
# docker build -t $service_name .

# # Tag the image with the ECR repository URI
# docker tag $service_name:latest $ECR_REPOSITORY:latest

# # Push the image to ECR
# docker push $ECR_REPOSITORY:latest

# # Retrieve the ARN of your App Runner service
# service_arn=$(aws apprunner list-services --region $region --query "ServiceSummaryList[?ServiceName=='$service_name'].ServiceArn | [0]" --output text)

# echo $service_arn

# # Trigger a manual deployment of the updated image in AWS App Runner
# aws apprunner start-deployment --service-arn $service_arn --region $region