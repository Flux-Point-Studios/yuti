-- BlueLight: Wallet Authentication Database Support
-- Date: July 19, 2025
-- Purpose: Ensure database schema supports wallet authentication properly

-- Add unique constraint on wallet_address to prevent multiple accounts with same wallet
-- This will prevent the same wallet from being linked to multiple accounts
ALTER TABLE public.users 
ADD CONSTRAINT unique_wallet_address 
UNIQUE (wallet_address);

-- Add index on wallet_address for fast lookups during authentication
CREATE INDEX IF NOT EXISTS idx_users_wallet_address 
ON public.users (wallet_address) 
WHERE wallet_address IS NOT NULL;

-- Add index on stake_address for premium verification queries
CREATE INDEX IF NOT EXISTS idx_users_stake_address 
ON public.users (stake_address) 
WHERE stake_address IS NOT NULL;

-- Ensure users table has the required wallet columns (should already exist)
-- But let's make sure they exist with proper types
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
    END IF;
    
    -- Check if stake_address column exists, if not add it  
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
        AND table_name = 'users' 
        AND column_name = 'stake_address'
    ) THEN
        ALTER TABLE public.users ADD COLUMN stake_address TEXT;
    END IF;
    
    -- Check if premium_access_details column exists, if not add it
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
        AND table_name = 'users' 
        AND column_name = 'premium_access_details'
    ) THEN
        ALTER TABLE public.users ADD COLUMN premium_access_details JSONB;
    END IF;
END $$;

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

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION public.find_user_by_wallet_address(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.find_user_by_wallet_address(text) TO anon;

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

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION public.is_wallet_address_taken(text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_wallet_address_taken(text, uuid) TO anon;

-- Update RLS policies to allow wallet-based authentication
-- Allow users to read their own data by wallet address
CREATE POLICY "Users can read own data by wallet address" ON public.users
    FOR SELECT USING (
        auth.uid() = id OR 
        wallet_address IN (
            SELECT wallet_address FROM public.users WHERE id = auth.uid()
        )
    );

-- Allow updating wallet information
CREATE POLICY "Users can update own wallet info" ON public.users
    FOR UPDATE USING (auth.uid() = id)
    WITH CHECK (auth.uid() = id);

-- Create a view for wallet authentication info (if needed)
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

-- Refresh the schema cache
NOTIFY pgrst, 'reload schema';

-- Add helpful comments
COMMENT ON CONSTRAINT unique_wallet_address ON public.users IS 
    'Ensures each wallet address can only be linked to one user account';

COMMENT ON FUNCTION public.find_user_by_wallet_address(text) IS 
    'Find user account by wallet address for authentication';

COMMENT ON FUNCTION public.is_wallet_address_taken(text, uuid) IS 
    'Check if wallet address is already linked to another account';

COMMENT ON VIEW public.wallet_auth_info IS 
    'View containing wallet authentication information for users';

-- Success message
DO $$
BEGIN
    RAISE NOTICE 'Wallet authentication database schema updated successfully!';
    RAISE NOTICE 'Added unique constraints, indexes, and helper functions for wallet auth.';
END $$; 