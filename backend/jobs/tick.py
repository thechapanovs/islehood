import os
from datetime import datetime, timezone

from dotenv import load_dotenv
from supabase import create_client

load_dotenv()  # reads backend/.env on Mac. Render uses its own settings instead


def build_heartbeat(now):
    return {"ran_at": now.isoformat()}


def main():
    client = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SECRET_KEY"])
    row = build_heartbeat(datetime.now(timezone.utc))
    client.table("heartbeat").insert(row).execute()
    print(f"tick ok {row['ran_at']}")


if __name__ == "__main__":
    main()