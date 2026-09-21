import os
from dotenv import load_dotenv
from supabase import create_client, Client
from supabase.lib.client_options import SyncClientOptions

load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_KEY")

# The default PostgREST timeout is two minutes. Handlers are sync `def`, so a
# hung call holds an AnyIO worker thread for that whole time - long after the
# app gave up at 15-30 s. There are only 40 such threads.
POSTGREST_TIMEOUT = float(os.getenv("SUPABASE_TIMEOUT", "10"))

supabase: Client = create_client(
    SUPABASE_URL,
    SUPABASE_KEY,
    options=SyncClientOptions(
        postgrest_client_timeout=POSTGREST_TIMEOUT,
        storage_client_timeout=POSTGREST_TIMEOUT,
    ),
)
