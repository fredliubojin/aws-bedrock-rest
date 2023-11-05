import os
from fastapi import FastAPI
from starlette.requests import Request
from starlette.responses import PlainTextResponse
from starlette.responses import StreamingResponse
import asyncio
from mangum import Mangum
import boto3, json, logging

app = FastAPI()
handler = Mangum(app)

bedrock = boto3.client(service_name='bedrock-runtime')
modelId = 'anthropic.claude-v2'
accept = 'application/json'
contentType = 'application/json'

logger = logging.getLogger()
logger.setLevel(logging.INFO)
handler = logging.StreamHandler()
formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
handler.setFormatter(formatter)
logger.addHandler(handler)


@app.get("/")
def read_root():
    return {"Hello": "world"}

@app.post("/v1/complete")
async def complete(request: Request):
    if 'x-api-key' not in request.headers:
        logger.error("Missing x-api-key header")
        return {"error": "Missing x-api-key header"}

    body = await request.json()
    logger.info(f"Received data: {body}")
    if not _is_valid_json_body(body, ["prompt", "max_tokens_to_sample", "temperature"]):
        logger.error(f'Invalid JSON body: {json.loads(body)}')
        return _create_response(400, f'Invalid JSON body: {body=}')

    body_obj, stream_enabled = _process_body(body)
    response = _invoke_model(body_obj)

    if stream_enabled:
        response = f'event: completion\ndata:{response}\n\n'

    return PlainTextResponse(response)

def _is_valid_json_body(data, fields):
    return all(field in data for field in fields)

def _process_body(body_obj):
    body_obj.pop("model", None)
    stream_enabled = body_obj.pop("stream", False)
    body_obj['anthropic_version'] = 'bedrock-2023-05-31'

    return json.dumps(body_obj), stream_enabled

def _invoke_model(body):
    response = bedrock.invoke_model(body=body, modelId=modelId, accept=accept, contentType=contentType)
    return response.get('body').read().decode('utf-8')

def _create_response(status_code, body):
    return {
        'statusCode': status_code,
        'body': body
    }

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
