-- Admin bypass for daily message limits
-- Allows specific admin email to bypass all daily limit restrictions

-- 1) can_user_send_message: return TRUE for admin email
CREATE OR REPLACE FUNCTION can_user_send_message(user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    user_tier TEXT;
    current_count INTEGER;
    last_reset DATE;
    user_email TEXT;
    is_premium BOOLEAN := FALSE;
BEGIN
    -- Get user's email, subscription tier and current message count
    SELECT u.email, s.tier, u.daily_message_count, u.last_message_reset_date
    INTO user_email, user_tier, current_count, last_reset
    FROM users u
    LEFT JOIN subscriptions s ON u.id = s.user_id
    WHERE u.id = user_uuid;

    -- If user not found, deny
    IF user_email IS NULL THEN
        RETURN FALSE;
    END IF;

    -- Admin email bypass
    IF user_email = 'nathanielminton@fluxpointstudios.com' THEN
        RETURN TRUE;
    END IF;

    -- Check if user has premium subscription
    IF user_tier IS NOT NULL AND user_tier != 'FREE' THEN
        is_premium := TRUE;
    END IF;

    -- Premium users have unlimited messages
    IF is_premium THEN
        RETURN TRUE;
    END IF;

    -- Reset count if it's a new day
    IF last_reset != CURRENT_DATE THEN
        UPDATE users 
        SET daily_message_count = 0, 
            last_message_reset_date = CURRENT_DATE
        WHERE id = user_uuid;
        current_count := 0;
    END IF;

    -- Check if FREE user is under the 20 Agent T response daily limit
    RETURN current_count < 20;
END;
$$;

-- 2) increment_user_message_count: no-op for admin email
CREATE OR REPLACE FUNCTION increment_user_message_count(user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    user_tier TEXT;
    current_count INTEGER;
    last_reset DATE;
    user_email TEXT;
BEGIN
    -- Get user's email, subscription tier and current message count
    SELECT u.email, s.tier, u.daily_message_count, u.last_message_reset_date
    INTO user_email, user_tier, current_count, last_reset
    FROM users u
    LEFT JOIN subscriptions s ON u.id = s.user_id
    WHERE u.id = user_uuid;

    -- If user not found, return false
    IF user_email IS NULL THEN
        RETURN FALSE;
    END IF;

    -- Admin email bypass: do not increment, but treat as success
    IF user_email = 'nathanielminton@fluxpointstudios.com' THEN
        RETURN TRUE;
    END IF;

    -- Premium users don't need count tracking
    IF user_tier IS NOT NULL AND user_tier != 'FREE' THEN
        RETURN TRUE;
    END IF;

    -- Reset count if it's a new day
    IF last_reset != CURRENT_DATE THEN
        UPDATE users 
        SET daily_message_count = 1, 
            last_message_reset_date = CURRENT_DATE
        WHERE id = user_uuid;
        RETURN TRUE;
    END IF;

    -- Increment count for FREE users
    UPDATE users 
    SET daily_message_count = daily_message_count + 1
    WHERE id = user_uuid;

    RETURN TRUE;
END;
$$;

-- 3) get_user_remaining_messages: return -1 (unlimited) for admin email
CREATE OR REPLACE FUNCTION get_user_remaining_messages(user_uuid UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    user_tier TEXT;
    current_count INTEGER;
    last_reset DATE;
    user_email TEXT;
    daily_limit INTEGER := 20;
BEGIN
    -- Get user's email, subscription tier and current message count
    SELECT u.email, s.tier, u.daily_message_count, u.last_message_reset_date
    INTO user_email, user_tier, current_count, last_reset
    FROM users u
    LEFT JOIN subscriptions s ON u.id = s.user_id
    WHERE u.id = user_uuid;

    -- If user not found, return 0
    IF user_email IS NULL THEN
        RETURN 0;
    END IF;

    -- Admin email bypass: unlimited
    IF user_email = 'nathanielminton@fluxpointstudios.com' THEN
        RETURN -1; -- sentinel for unlimited
    END IF;

    -- Premium users have unlimited messages
    IF user_tier IS NOT NULL AND user_tier != 'FREE' THEN
        RETURN -1; -- -1 indicates unlimited
    END IF;

    -- Reset count if it's a new day
    IF last_reset != CURRENT_DATE THEN
        RETURN daily_limit;
    END IF;

    -- Return remaining Agent T responses for FREE users
    RETURN GREATEST(daily_limit - current_count, 0);
END;
$$;