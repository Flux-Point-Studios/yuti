# Supabase Auth & RLS Fixes for BlueLight

## Issue 2: Email Confirmation Redirects to Wrong Domain

**Problem**: Email confirmations redirect to `cardevia.ai` instead of BlueLight app

**Root Cause**: Supabase Auth configuration has wrong redirect URL

**Fix Steps**:

1. **Go to Supabase Dashboard**:
   - Navigate to: https://supabase.com/dashboard/project/zlvcevggynsrmvyiaxru
   - Go to Authentication → Settings → URL Configuration

2. **Update Redirect URLs**:
   ```
   Site URL: https://bluelight-dmom0ulto-decimalists-projects.vercel.app
   
   Additional Redirect URLs:
   - https://bluelight-dmom0ulto-decimalists-projects.vercel.app/auth/callback
   - https://bluelight-dmom0ulto-decimalists-projects.vercel.app/gamechanger-callback
   - bluelight://auth/callback (for native apps)
   ```

3. **Update Email Templates**:
   - Go to Authentication → Email Templates
   - In "Confirm signup" template, change any hardcoded domains from `cardevia.ai` to your actual domain
   - Ensure `{{ .SiteURL }}` is used for dynamic redirects

## Issue 3: Supabase RLS Policy Error (PostgreSQL 42501)

**Problem**: `"new row violates row-level security policy for table 'users'"`

**Root Cause**: Row Level Security policies are too restrictive for user signup

**Fix Steps**:

1. **Go to Supabase SQL Editor**:
   - Navigate to: SQL Editor in your Supabase dashboard

2. **Check Current RLS Policies**:
   ```sql
   SELECT * FROM pg_policies WHERE tablename = 'users';
   ```

3. **Fix/Add Proper RLS Policies**:
   ```sql
   -- Drop existing restrictive policies if any
   DROP POLICY IF EXISTS "Users can only see own data" ON users;
   DROP POLICY IF EXISTS "Users can only insert own data" ON users;
   
   -- Allow users to insert their own records during signup
   CREATE POLICY "Allow authenticated users to insert own data" ON users
   FOR INSERT
   TO authenticated
   WITH CHECK (auth.uid() = id);
   
   -- Allow users to read their own data
   CREATE POLICY "Allow users to read own data" ON users
   FOR SELECT
   TO authenticated
   USING (auth.uid() = id);
   
   -- Allow users to update their own data
   CREATE POLICY "Allow users to update own data" ON users
   FOR UPDATE
   TO authenticated
   USING (auth.uid() = id)
   WITH CHECK (auth.uid() = id);
   
   -- Enable RLS (if not already enabled)
   ALTER TABLE users ENABLE ROW LEVEL SECURITY;
   ```

4. **Fix Subscriptions Table RLS**:
   ```sql
   -- Check if subscriptions table has similar issues
   SELECT * FROM pg_policies WHERE tablename = 'subscriptions';
   
   -- Add proper policies for subscriptions
   CREATE POLICY "Allow authenticated users to insert own subscription" ON subscriptions
   FOR INSERT
   TO authenticated
   WITH CHECK (auth.uid() = user_id);
   
   CREATE POLICY "Allow users to read own subscription" ON subscriptions
   FOR SELECT
   TO authenticated
   USING (auth.uid() = user_id);
   
   CREATE POLICY "Allow users to update own subscription" ON subscriptions
   FOR UPDATE
   TO authenticated
   USING (auth.uid() = user_id)
   WITH CHECK (auth.uid() = user_id);
   
   ALTER TABLE subscriptions ENABLE ROW LEVEL SECURITY;
   ```

5. **Test the Fix**:
   ```sql
   -- Verify policies are working
   SELECT policyname, cmd, roles, qual, with_check 
   FROM pg_policies 
   WHERE tablename IN ('users', 'subscriptions');
   ```

## Alternative Quick Fix for RLS (if above doesn't work)

If you need a quick fix to unblock user signups:

```sql
-- Temporarily disable RLS for users table (DEVELOPMENT ONLY)
ALTER TABLE users DISABLE ROW LEVEL SECURITY;
ALTER TABLE subscriptions DISABLE ROW LEVEL SECURITY;
```

**⚠️ Warning**: This removes security, so only use for immediate testing. Re-enable with proper policies ASAP.

## Verification Steps

1. **Test Email Redirect**:
   - Try signing up with a test email
   - Check that confirmation email links point to correct domain
   - Verify successful redirect after confirmation

2. **Test User Signup**:
   - Create new account through app
   - Should complete without PostgreSQL errors
   - Verify user appears in Supabase users table

3. **Test AI Responses**:
   - After rebuilding with GitHub Actions
   - Send test message to AI in TestFlight
   - Should get proper responses instead of hanging

## Emergency Contacts

If issues persist:
- Supabase Support: https://supabase.com/dashboard/support
- PostgreSQL RLS Documentation: https://supabase.com/docs/guides/auth/row-level-security 