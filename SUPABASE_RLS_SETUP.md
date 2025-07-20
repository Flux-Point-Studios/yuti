# Supabase Row Level Security (RLS) Setup

## Issue Description

The mobile app was experiencing signup failures with the error:
```
PostgrestException(message: new row violates row-level security policy for table "users", code: 42501, details: Unauthorized, hint: null)
```

This occurs because Row Level Security (RLS) policies prevent newly authenticated users from inserting records into the `users` and `subscriptions` tables immediately after signup.

## Root Cause

When a user signs up through `auth.signUp()`, Supabase creates an authentication record, but the RLS policies on the `users` table don't allow the newly authenticated user to insert their own profile record. This happens because:

1. The user is authenticated but not yet in the `users` table
2. RLS policies typically check if the user exists in the `users` table
3. This creates a chicken-and-egg problem during signup

## Solution Implemented

The `AuthService.signUp()` method has been updated to handle this issue with a multi-layered approach:

1. **Primary**: Try using a Supabase RPC function `create_user_profile` that bypasses RLS
2. **Fallback**: Attempt direct insert with proper auth context
3. **Graceful degradation**: Create a basic user object if database operations fail

## Required Supabase Database Function

Create this function in your Supabase SQL Editor to properly handle user profile creation:

```sql
-- Function to create user profile that bypasses RLS
CREATE OR REPLACE FUNCTION create_user_profile(user_id uuid, user_email text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER -- This allows the function to bypass RLS
AS $$
BEGIN
  -- Insert user record
  INSERT INTO users (id, email, customer_id, created_at)
  VALUES (user_id, user_email, null, now())
  ON CONFLICT (id) DO NOTHING;
  
  -- Insert free subscription record
  INSERT INTO subscriptions (user_id, tier, status, created_at)
  VALUES (user_id, 'FREE', 'active', now())
  ON CONFLICT (user_id) DO NOTHING;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION create_user_profile(uuid, text) TO authenticated;
```

## Alternative RLS Policy Setup

If you prefer not to use the RPC function, you can modify your RLS policies to allow new users to insert their own records:

```sql
-- Enable RLS on users table
ALTER TABLE users ENABLE ROW LEVEL SECURITY;

-- Policy to allow users to insert their own record during signup
CREATE POLICY "Users can insert their own record" ON users
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = id);

-- Policy to allow users to read their own record
CREATE POLICY "Users can read their own record" ON users
FOR SELECT
TO authenticated
USING (auth.uid() = id);

-- Policy to allow users to update their own record
CREATE POLICY "Users can update their own record" ON users
FOR UPDATE
TO authenticated
USING (auth.uid() = id);

-- Enable RLS on subscriptions table
ALTER TABLE subscriptions ENABLE ROW LEVEL SECURITY;

-- Policy to allow users to insert their own subscription
CREATE POLICY "Users can insert their own subscription" ON subscriptions
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

-- Policy to allow users to read their own subscription
CREATE POLICY "Users can read their own subscription" ON subscriptions
FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

-- Policy to allow users to update their own subscription
CREATE POLICY "Users can update their own subscription" ON subscriptions
FOR UPDATE
TO authenticated
USING (auth.uid() = user_id);
```

## Database Triggers (Recommended)

The most elegant solution is to use database triggers that automatically create user profiles when a user signs up:

```sql
-- Function to handle new user signup
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO users (id, email, created_at)
  VALUES (NEW.id, NEW.email, NEW.created_at);
  
  INSERT INTO subscriptions (user_id, tier, status, created_at)
  VALUES (NEW.id, 'FREE', 'active', NEW.created_at);
  
  RETURN NEW;
END;
$$;

-- Trigger to automatically create user profile on auth signup
CREATE OR REPLACE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();
```

## Testing the Fix

After implementing any of the above solutions, test the signup flow:

1. Clear app data/cache
2. Attempt to sign up with a new email
3. Verify that the user profile is created successfully
4. Check that the user has a FREE subscription

## Monitoring

Add logging to monitor which path the signup process takes:
- RPC function success
- Direct insert fallback
- Graceful degradation

This will help identify if the database setup is working correctly.