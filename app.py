import os
from fastapi import FastAPI
from starlette.responses import StreamingResponse
import asyncio
from mangum import Mangum

app = FastAPI()
handler = Mangum(app)


@app.get("/")
def read_root():
    return {"Hello": "World!"}


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
