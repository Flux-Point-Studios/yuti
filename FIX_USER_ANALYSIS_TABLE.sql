-- Fix for user_analysis table issue
-- Run this in Supabase SQL Editor if you encountered the RLS error

-- Drop the view if it exists and create as a proper table
DROP VIEW IF EXISTS public.user_analysis;

-- Create user_analysis as a table (not view)
CREATE TABLE IF NOT EXISTS public.user_analysis (
    id uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
    chat_count integer DEFAULT 0,
    fragments integer DEFAULT 0,
    referral_count integer DEFAULT 0,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now()
);

-- Enable RLS on the table
ALTER TABLE public.user_analysis ENABLE ROW LEVEL SECURITY;

-- Add RLS policies for user_analysis table
DROP POLICY IF EXISTS "Users can view their own analysis" ON public.user_analysis;
CREATE POLICY "Users can view their own analysis" ON public.user_analysis
    FOR SELECT USING (auth.uid() = id);

DROP POLICY IF EXISTS "Users can insert their own analysis" ON public.user_analysis;
CREATE POLICY "Users can insert their own analysis" ON public.user_analysis
    FOR INSERT WITH CHECK (auth.uid() = id);

DROP POLICY IF EXISTS "Users can update their own analysis" ON public.user_analysis;
CREATE POLICY "Users can update their own analysis" ON public.user_analysis
    FOR UPDATE USING (auth.uid() = id);

-- Success message
DO $$
BEGIN
    RAISE NOTICE '✅ user_analysis table fixed successfully!';
END $$; 