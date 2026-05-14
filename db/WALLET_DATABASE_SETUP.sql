-- BlueLight: Wallet Authentication Database Support - COMPLETE SETUP
-- Date: January 2025  
-- Purpose: Ensure database schema supports wallet authentication and storage properly
-- 
-- INSTRUCTIONS: Copy and paste this entire script into your Supabase SQL Editor and run it.

-- FIRST: Ensure users table has the required wallet columns
DO $$ 
BEGIN
    -- Check if wallet_address column exists, if not add it
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
        AND table_name = 'users' 
        AND column_name = 'wallet_address'
    ) THEN
        ALTER TABLE public.users ADD COLUMN wallet_address TEXT;
        RAISE NOTICE 'Added wallet_address column';
    ELSE
        RAISE NOTICE 'wallet_address column already exists';
    END IF;
    
    -- Check if stake_address column exists, if not add it  
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
        AND table_name = 'users' 
        AND column_name = 'stake_address'
    ) THEN
        ALTER TABLE public.users ADD COLUMN stake_address TEXT;
        RAISE NOTICE 'Added stake_address column';
    ELSE
        RAISE NOTICE 'stake_address column already exists';
    END IF;
    
    -- Check if premium_access_details column exists, if not add it
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
        AND table_name = 'users' 
        AND column_name = 'premium_access_details'
    ) THEN
        ALTER TABLE public.users ADD COLUMN premium_access_details JSONB;
        RAISE NOTICE 'Added premium_access_details column';
    ELSE
        RAISE NOTICE 'premium_access_details column already exists';
    END IF;
END $$;

-- SECOND: Add unique constraint on wallet_address (now that column exists)
DO $$
BEGIN
    -- Check if constraint already exists
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE table_schema = 'public' 
        AND table_name = 'users' 
        AND constraint_name = 'unique_wallet_address'
    ) THEN
        ALTER TABLE public.users ADD CONSTRAINT unique_wallet_address UNIQUE (wallet_address);
        RAISE NOTICE 'Added unique constraint on wallet_address';
    ELSE
        RAISE NOTICE 'unique_wallet_address constraint already exists';
    END IF;
END $$;

-- THIRD: Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_users_wallet_address 
ON public.users (wallet_address) 
WHERE wallet_address IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_users_stake_address 
ON public.users (stake_address) 
WHERE stake_address IS NOT NULL;

-- FOURTH: Create tables needed for new profile features

-- Referrals table for affiliate program
CREATE TABLE IF NOT EXISTS public.referrals (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    referral_code text NOT NULL UNIQUE,
    referral_link text NOT NULL,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now()
);

-- Referral uses table to track successful referrals
CREATE TABLE IF NOT EXISTS public.referral_uses (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    referrer_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    referred_user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    referral_code text NOT NULL,
    created_at timestamptz DEFAULT now(),
    UNIQUE(referred_user_id) -- Each user can only be referred once
);

-- User analysis table for usage statistics
CREATE TABLE IF NOT EXISTS public.user_analysis (
    id uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
    chat_count integer DEFAULT 0,
    fragments integer DEFAULT 0,
    referral_count integer DEFAULT 0,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now()
);

-- Monthly analysis table for activity charts
CREATE TABLE IF NOT EXISTS public.analysis_month (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    month date NOT NULL, -- First day of the month
    chat_count integer DEFAULT 0,
    fragments integer DEFAULT 0,
    referral_count integer DEFAULT 0,
    created_at timestamptz DEFAULT now(),
    UNIQUE(user_id, month)
);

-- FIFTH: Add RLS policies for new tables
ALTER TABLE public.referrals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.referral_uses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_analysis ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.analysis_month ENABLE ROW LEVEL SECURITY;

-- RLS policies for referrals table
CREATE POLICY "Users can view their own referrals" ON public.referrals
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own referrals" ON public.referrals
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own referrals" ON public.referrals
    FOR UPDATE USING (auth.uid() = user_id);

-- RLS policies for referral_uses table
CREATE POLICY "Users can view referrals they made" ON public.referral_uses
    FOR SELECT USING (auth.uid() = referrer_id);

CREATE POLICY "Anyone can insert referral uses" ON public.referral_uses
    FOR INSERT WITH CHECK (true);

-- RLS policies for user_analysis table
CREATE POLICY "Users can view their own analysis" ON public.user_analysis
    FOR SELECT USING (auth.uid() = id);

CREATE POLICY "Users can insert their own analysis" ON public.user_analysis
    FOR INSERT WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can update their own analysis" ON public.user_analysis
    FOR UPDATE USING (auth.uid() = id);

-- RLS policies for analysis_month table
CREATE POLICY "Users can view their own monthly analysis" ON public.analysis_month
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own monthly analysis" ON public.analysis_month
    FOR INSERT WITH CHECK (auth.uid() = user_id);

-- SIXTH: Create helper functions

-- Function to find user by wallet address (used by wallet auth service)
CREATE OR REPLACE FUNCTION public.find_user_by_wallet_address(target_wallet_address text)
RETURNS TABLE (
    id uuid,
    email text,
    wallet_address text,
    stake_address text,
    tier text,
    created_at timestamptz,
    updated_at timestamptz,
    premium_access_details jsonb
) 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        u.id,
        u.email,
        u.wallet_address,
        u.stake_address,
        COALESCE(s.tier, 'FREE') as tier,
        u.created_at,
        u.updated_at,
        u.premium_access_details
    FROM public.users u
    LEFT JOIN public.subscriptions s ON u.id = s.user_id
    WHERE u.wallet_address = target_wallet_address;
END;
$$;

-- Function to check if wallet address is already linked to another account
CREATE OR REPLACE FUNCTION public.is_wallet_address_taken(
    target_wallet_address text,
    exclude_user_id uuid DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    wallet_count integer;
BEGIN
    SELECT COUNT(*)
    INTO wallet_count
    FROM public.users
    WHERE wallet_address = target_wallet_address
    AND (exclude_user_id IS NULL OR id != exclude_user_id);
    
    RETURN wallet_count > 0;
END;
$$;

-- Function to update user statistics when actions occur
CREATE OR REPLACE FUNCTION public.update_user_stats(
    target_user_id uuid,
    increment_chats integer DEFAULT 0,
    increment_fragments integer DEFAULT 0,
    increment_referrals integer DEFAULT 0
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    INSERT INTO public.user_analysis (id, chat_count, fragments, referral_count)
    VALUES (target_user_id, increment_chats, increment_fragments, increment_referrals)
    ON CONFLICT (id) DO UPDATE SET
        chat_count = user_analysis.chat_count + increment_chats,
        fragments = user_analysis.fragments + increment_fragments,
        referral_count = user_analysis.referral_count + increment_referrals,
        updated_at = now();
END;
$$;

-- SEVENTH: Grant permissions
GRANT EXECUTE ON FUNCTION public.find_user_by_wallet_address(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.find_user_by_wallet_address(text) TO anon;
GRANT EXECUTE ON FUNCTION public.is_wallet_address_taken(text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_wallet_address_taken(text, uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.update_user_stats(uuid, integer, integer, integer) TO authenticated;

-- Create a view for wallet authentication info
CREATE OR REPLACE VIEW public.wallet_auth_info AS
SELECT 
    u.id,
    u.email,
    u.wallet_address,
    u.stake_address,
    COALESCE(s.tier, 'FREE') as tier,
    s.status as subscription_status,
    u.premium_access_details,
    u.created_at,
    u.updated_at
FROM public.users u
LEFT JOIN public.subscriptions s ON u.id = s.user_id
WHERE u.wallet_address IS NOT NULL;

-- Grant access to the view
GRANT SELECT ON public.wallet_auth_info TO authenticated;
GRANT SELECT ON public.wallet_auth_info TO anon;

-- EIGHTH: Create triggers to automatically update user stats

-- Trigger function to update stats when new chat is created
CREATE OR REPLACE FUNCTION public.trigger_update_chat_stats()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM public.update_user_stats(NEW.user_id, 1, 0, 0);
    RETURN NEW;
END;
$$;

-- Trigger function to update stats when new message is created
CREATE OR REPLACE FUNCTION public.trigger_update_message_stats()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM public.update_user_stats(NEW.user_id, 0, 1, 0);
    RETURN NEW;
END;
$$;

-- Trigger function to update stats when referral is used
CREATE OR REPLACE FUNCTION public.trigger_update_referral_stats()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM public.update_user_stats(NEW.referrer_id, 0, 0, 1);
    RETURN NEW;
END;
$$;

-- Create triggers (drop first if they exist)
DROP TRIGGER IF EXISTS trigger_chat_stats ON public.chats;
CREATE TRIGGER trigger_chat_stats
    AFTER INSERT ON public.chats
    FOR EACH ROW
    EXECUTE FUNCTION public.trigger_update_chat_stats();

DROP TRIGGER IF EXISTS trigger_message_stats ON public.messages;
CREATE TRIGGER trigger_message_stats
    AFTER INSERT ON public.messages
    FOR EACH ROW
    EXECUTE FUNCTION public.trigger_update_message_stats();

DROP TRIGGER IF EXISTS trigger_referral_stats ON public.referral_uses;
CREATE TRIGGER trigger_referral_stats
    AFTER INSERT ON public.referral_uses
    FOR EACH ROW
    EXECUTE FUNCTION public.trigger_update_referral_stats();

-- Refresh the schema cache
NOTIFY pgrst, 'reload schema';

-- Success message
DO $$
BEGIN
    RAISE NOTICE '🎉 ===== WALLET DATABASE SETUP COMPLETED SUCCESSFULLY! =====';
    RAISE NOTICE '✅ Added wallet columns to users table';
    RAISE NOTICE '✅ Added unique constraints and indexes';
    RAISE NOTICE '✅ Created referrals and analytics tables';
    RAISE NOTICE '✅ Set up RLS policies for security';
    RAISE NOTICE '✅ Created helper functions for wallet auth';
    RAISE NOTICE '✅ Added triggers for automatic stats tracking';
    RAISE NOTICE '🚀 Your BlueLight app is now ready for wallet storage and profile features!';
END $$; 