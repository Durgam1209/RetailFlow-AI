-- This SQL script sets up the daily_insights table in Supabase
-- Run this in Supabase Dashboard → SQL Editor → New Query
-- Then copy and paste this entire script and click "Run"

-- Create the daily_insights table if it doesn't exist
CREATE TABLE IF NOT EXISTS public.daily_insights (
  id BIGSERIAL PRIMARY KEY,
  forecast_summary TEXT NOT NULL,
  suggested_bundles JSONB NOT NULL DEFAULT '[]'::jsonb,
  stock_advice JSONB NOT NULL DEFAULT '[]'::jsonb,
  festival_advice JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL
);

-- Add the festival advice column for existing installations
ALTER TABLE public.daily_insights
  ADD COLUMN IF NOT EXISTS festival_advice JSONB NOT NULL DEFAULT '{}'::jsonb;

-- Enable RLS (Row Level Security)
ALTER TABLE public.daily_insights ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist (safe if they don't)
DROP POLICY IF EXISTS "Anyone can read daily insights" ON public.daily_insights;
DROP POLICY IF EXISTS "Service role can insert insights" ON public.daily_insights;

-- Create read policy for anonymous users (Flutter app)
CREATE POLICY "Anyone can read daily insights"
  ON public.daily_insights
  FOR SELECT
  USING (true);

-- Create insert policy for service role only (Python backend)
CREATE POLICY "Service role can insert insights"
  ON public.daily_insights
  FOR INSERT
  WITH CHECK (true);

-- Create an index on created_at for faster queries
CREATE INDEX IF NOT EXISTS daily_insights_created_at_idx 
  ON public.daily_insights(created_at DESC);

-- Grant permissions
GRANT SELECT ON public.daily_insights TO anon;
GRANT SELECT ON public.daily_insights TO authenticated;
GRANT INSERT, SELECT, UPDATE ON public.daily_insights TO service_role;

-- Success message
SELECT 'daily_insights table setup complete!' as status;
