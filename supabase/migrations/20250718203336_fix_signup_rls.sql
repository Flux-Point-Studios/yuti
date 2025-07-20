-- Fix RLS policy issue preventing user signup
-- The INSERT policy for users table is too restrictive and blocks the signup trigger

-- Drop the problematic INSERT policies that block the signup trigger
DROP POLICY IF EXISTS "Users can insert own profile" ON users;
DROP POLICY IF EXISTS "Users can insert own subscription" ON subscriptions;

-- Users and their initial subscriptions should only be created via the auth signup trigger
-- Direct INSERTs by users are not needed for these tables

-- Also ensure the trigger function can bypass RLS if needed
CREATE OR REPLACE FUNCTION handle_new_user_signup()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER -- This allows the function to bypass RLS
SET search_path = public
AS $$
BEGIN
    -- Insert into users table (will bypass RLS due to SECURITY DEFINER)
    INSERT INTO users (id, email, created_at)
    VALUES (NEW.id, NEW.email, NEW.created_at);
    
    -- Insert into subscriptions table with FREE tier
    INSERT INTO subscriptions (user_id, tier, status, created_at)
    VALUES (NEW.id, 'FREE', 'active', NEW.created_at);
    
    RETURN NEW;
END;
$$;
