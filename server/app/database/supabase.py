# This block creates a shared Supabase client using environment configuration.
import os
from dotenv import load_dotenv
from supabase import create_client, Client

# This block loads .env settings when available; settings may also come from the process environment.
load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_KEY")

# Shared client imported by routes to query Supabase.
supabase: Client = create_client(
    SUPABASE_URL,
    SUPABASE_KEY
)