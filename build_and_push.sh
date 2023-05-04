#!/bin/bash

# Ensure AWS_ACCOUNT_ID and AWS_REGION are set
if [ -z "$AWS_ACCOUNT_ID" ] || [ -z "$AWS_REGION" ]; then
  echo "Please set the environment variables AWS_ACCOUNT_ID and AWS_REGION before running this script."
  exit 1
fi

# Set the required variables from the environment
account_id=${AWS_ACCOUNT_ID}
region=${AWS_REGION}
service_name=my-fastapi-app

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

# Retrieve the ARN of your App Runner service
service_arn=$(aws apprunner list-services --region $region --query "ServiceSummaryList[?ServiceName=='$service_name'].ServiceArn | [0]" --output text)

echo $service_arn

# Trigger a manual deployment of the updated image in AWS App Runner
aws apprunner start-deployment --service-arn $service_arn --region $region