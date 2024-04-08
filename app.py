import os
from fastapi import FastAPI
from fastapi import HTTPException, Depends
from fastapi.security import APIKeyHeader
from fastapi import Security
from starlette.requests import Request
from starlette.responses import PlainTextResponse
from starlette.responses import StreamingResponse
import asyncio
from mangum import Mangum
import boto3, json, logging
from botocore.exceptions import ClientError
import botocore
from uuid import uuid4
from typing import List


app = FastAPI()
handler = Mangum(app)

bedrock = boto3.client(service_name='bedrock-runtime')
accept = 'application/json'
contentType = 'application/json'
ANTHROPIC_TO_BEDROCK_MODEL_MAP = {
    'claude-instant-1.2': 'anthropic.claude-instant-v1',
    'claude-2.0': 'anthropic.claude-v2',
    'claude-2.1': 'anthropic.claude-v2:1',
    #'claude-3-opus-20240229': 'anthropic.claude-3-opus-20240229-v1:0', # opus is not supported on bedrock yet
    'claude-3-sonnet-20240229': 'anthropic.claude-3-sonnet-20240229-v1:0',
    'claude-3-haiku-20240307': 'anthropic.claude-3-haiku-20240307-v1:0',
}

logger = logging.getLogger()
logger.setLevel(logging.INFO)
handler = logging.StreamHandler()
formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
handler.setFormatter(formatter)
logger.addHandler(handler)

# API key management
API_KEY_NAME = "x-api-key"
API_ADMIN_HEADER_NAME = "x-api-admin"
api_key_header = APIKeyHeader(name=API_KEY_NAME, auto_error=False)
api_admin_header = APIKeyHeader(name=API_ADMIN_HEADER_NAME, auto_error=False)

# Retrieve the admin API key from environment variable
ADMIN_API_KEY = os.getenv("ADMIN_API_KEY")

# Name of the secret you want to use in AWS Secrets Manager
SECRET_NAME = "my_api_keys_secret"

# Create a Secrets Manager client
secrets_manager_client = boto3.client(
    service_name='secretsmanager',
    region_name='us-west-2'
)

# Function to retrieve API keys from AWS Secret Manager
def load_api_keys():
    try:
        get_secret_value_response = secrets_manager_client.get_secret_value(
            SecretId=SECRET_NAME
        )
    except ClientError as e:
        if e.response['Error']['Code'] == 'ResourceNotFoundException':
            # Secrets Manager can't decrypt the protected secret text using the provided KMS key.
            # Deal with the exception here, and/or rethrow at your discretion.
            logger.info(f"The requested secret {SECRET_NAME} was not found. Creating new secret with an empty list.")
            secrets_manager_client.create_secret(
                Name=SECRET_NAME,
                SecretString=json.dumps([])  # Initialize the secret with an empty list
            )
            return []
        else:
            raise e
    else:
        # Decrypts secret using the associated KMS CMK
        # Depending on whether the secret is a string or binary, one of these fields will be populated
        if 'SecretString' in get_secret_value_response:
            secret = get_secret_value_response['SecretString']
            return json.loads(secret)  # Assuming the keys are stored as a JSON array
        else:
            decoded_binary_secret = base64.b64decode(get_secret_value_response['SecretBinary'])
            return json.loads(decoded_binary_secret)

def save_api_keys():
    try:
        secrets_manager_client.update_secret(
            SecretId=SECRET_NAME,
            SecretString=json.dumps(api_keys)  # Saving the keys as a JSON array
        )
    except ClientError as e:
        # In a production environment, consider logging the error and handling it appropriately
        raise e

# Load API keys at startup
api_keys = load_api_keys()

# Dependency to check for valid API key
async def get_api_key(api_key_header: str = Security(api_key_header)):
    if api_key_header not in api_keys:
        raise HTTPException(status_code=403, detail="Invalid API key")
    return api_key_header

# Dependency to check for valid admin API key
async def get_admin_api_key(api_admin_header: str = Security(api_admin_header)):
    if api_admin_header != ADMIN_API_KEY:
        raise HTTPException(status_code=403, detail="Invalid admin API key")
    return api_admin_header

@app.get("/keys", response_model=List[str])
async def list_api_keys(admin_api_key: str = Depends(get_admin_api_key)):
    return api_keys

@app.post("/keys")
async def create_api_key(admin_api_key: str = Depends(get_admin_api_key)):
    new_key = f"bedrock-sk-{uuid4()}"
    api_keys.append(new_key)
    save_api_keys()
    return {"api_key": new_key}

@app.delete("/keys/{api_key}")
async def delete_api_key(api_key: str, admin_api_key: str = Depends(get_admin_api_key)):
    if api_key in api_keys:
        api_keys.remove(api_key)
        save_api_keys()
        return {"detail": "API key deleted"}
    else:
        raise HTTPException(status_code=404, detail="API key not found")

@app.get("/")
def read_root():
    return {"Hello": "world"}

@app.post("/v1/complete")
async def complete(request: Request, api_key: str = Depends(get_api_key)):
    body = await request.json()
    if not _is_valid_json_body(body, ["prompt", "max_tokens_to_sample"]):
        logger.error(f'Invalid JSON body: {json.loads(body)}')
        raise HTTPException(status_code=400, detail=f'Invalid JSON body: {body=}')

    model, body_obj, stream_enabled = _process_body(body)

    if stream_enabled:
        # Create a StreamingResponse using the _invoke_model asynchronous generator
        return StreamingResponse(_invoke_model_stream(body_obj, model), media_type="text/event-stream")
    else:
        response = _invoke_model(body_obj, model)
        return PlainTextResponse(response)


@app.post("/v1/messages")
async def complete(request: Request, api_key: str = Depends(get_api_key)):
    body = await request.json()
    if not _is_valid_json_body(body, ["model", "messages", "max_tokens"]):
        logger.error(f'Invalid JSON body: {json.loads(body)}')
        raise HTTPException(status_code=400, detail=f'Invalid JSON body: {body=}')

    model, body_obj, stream_enabled = _process_body(body)

    if stream_enabled:
        # Create a StreamingResponse using the _invoke_model asynchronous generator
        return StreamingResponse(_invoke_model_stream(body_obj, model), media_type="text/event-stream")
    else:
        response = _invoke_model(body_obj, model)
        return PlainTextResponse(response)

def _is_valid_json_body(data, fields):
    return all(field in data for field in fields)

def _process_body(body_obj):
    anthropic_model = body_obj.pop("model", None)
    # Translate to bedrock model
    bedrock_model = ANTHROPIC_TO_BEDROCK_MODEL_MAP.get(anthropic_model, None)
    stream_enabled = body_obj.pop("stream", False)
    body_obj['anthropic_version'] = 'bedrock-2023-05-31'

    return bedrock_model, json.dumps(body_obj), stream_enabled

async def _invoke_model_stream(body: dict, model):
    response = bedrock.invoke_model_with_response_stream(body=body, modelId=model, accept=accept, contentType=contentType)
    for event in response.get('body'):
        chunk = json.loads(event["chunk"]["bytes"])
        event_type = chunk.get("type", "completion")
        yield f'event: {event_type}\ndata:{json.dumps(chunk)}\n\n'

def _invoke_model(body, model):
    response = bedrock.invoke_model(body=body, modelId=model, accept=accept, contentType=contentType)
    return response.get('body').read().decode('utf-8')

async def event_stream():
    count = 0
    while count < 5:
        await asyncio.sleep(1)
        count += 1
        yield f"data: {count}\n\n"
    yield "end!"

@app.get("/events", response_class=StreamingResponse)
async def get_events():
    return StreamingResponse(event_stream(), media_type="text/event-stream")
