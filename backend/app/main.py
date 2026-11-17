import os
from datetime import datetime, timezone

from dotenv import load_dotenv
from fastapi import FastAPI, Header, HTTPException
from supabase import create_client

load_dotenv()
app = FastAPI()


def get_db():
    # Uses the SECRET key: this code only ever runs on the server
    return create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SECRET_KEY"])


@app.get("/health")
def health():
    return {"ok": True}


@app.post("/jobs/tick")
def tick(x_job_token: str = Header()):
    # Only the scheduler knows this token, so strangers can't run jobs
    if x_job_token != os.environ["JOB_TOKEN"]:
        raise HTTPException(status_code=401, detail="Bad token")

    now = datetime.now(timezone.utc).isoformat()
    get_db().table("heartbeat").insert({"ran_at": now}).execute()
    # Later: pick prompts and run reveals here
    return {"ran_at": now}