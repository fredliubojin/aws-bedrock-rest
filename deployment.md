## 1. Create an Amazon ECR repository

To store your container images, create an Amazon ECR repository:

```bash
aws ecr create-repository --repository-name bedrock-rest
```

Note down the `repositoryUri` from the output.

## 2. Build and push the Docker image

Build and push the Docker image to the ECR repository:

```bash
# Replace <account_id> with your AWS account ID and <region> with your desired AWS region
ECR_REPOSITORY=<account_id>.dkr.ecr.<region>.amazonaws.com/bedrock-rest

# Login to ECR
aws ecr get-login-password --region <region> | docker login --username AWS --password-stdin $ECR_REPOSITORY

# Build the Docker image
docker build -t bedrock-rest .

# Tag the image with the ECR repository URI
docker tag bedrock-rest:latest $ECR_REPOSITORY:latest

# Push the image to ECR
docker push $ECR_REPOSITORY:latest
```

## 3. Create a JSON configuration file

Create a JSON file named `apprunner-service.json` with the following content:

```json
{
  "SourceConfiguration": {
    "AuthenticationConfiguration": {
      "AccessRoleArn": "arn:aws:iam::<account_id>:role/service-role/AppRunnerServiceRoleForECRAccess"
    },
    "ImageRepository": {
      "ImageIdentifier": "<account_id>.dkr.ecr.<region>.amazonaws.com/bedrock-rest:latest",
      "ImageRepositoryType": "ECR"
    }
  },
  "InstanceConfiguration": {
    "Cpu": "1024",
    "Memory": "2"
  },
  "ServiceName": "bedrock-rest"
}
```

Replace `<account_id>` and `<region>` placeholders with your AWS account ID and desired region, respectively.

## 4. Create IAM roles and policies (only needed for the first time)

Run the bash script to create IAM roles and policies:

```bash
./create-iam-roles.sh
```

## 5. Create an AWS App Runner service

Using the AWS CLI, create an AWS App Runner service:

```bash
aws apprunner create-service --cli-input-json file://apprunner-service.json --region <region>
```

Replace `<region>` with your desired AWS region.

AWS App Runner will build and deploy your FastAPI application.

## 6. Get the service URL

Once the deployment is complete, you can get the service URL by running:

```bash
aws apprunner list-services --region <region>
aws apprunner describe-service --service-arn <ServiceArn> --region <region>
```

Replace `<region>` with your desired AWS region and `<ServiceArn>` with the ARN of the created service from the output of the `list-services` command.

## 7. For continued development, after you made changes to the project to rebuild and deploy

```bash
./build_and_push.sh
```