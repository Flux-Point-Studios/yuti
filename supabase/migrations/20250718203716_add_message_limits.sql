-- Add daily message limit tracking for FREE users
-- FREE users are limited to 20 messages per day across all sessions

-- Add message tracking fields to users table
ALTER TABLE users ADD COLUMN IF NOT EXISTS daily_message_count INTEGER DEFAULT 0;
ALTER TABLE users ADD COLUMN IF NOT EXISTS last_message_reset_date DATE DEFAULT CURRENT_DATE;

-- Create function to check if user can send messages
CREATE OR REPLACE FUNCTION can_user_send_message(user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    user_tier TEXT;
    current_count INTEGER;
    last_reset DATE;
    is_premium BOOLEAN := FALSE;
BEGIN
    -- Get user's subscription tier and current message count
    SELECT s.tier, u.daily_message_count, u.last_message_reset_date
    INTO user_tier, current_count, last_reset
    FROM users u
    LEFT JOIN subscriptions s ON u.id = s.user_id
    WHERE u.id = user_uuid;

    -- If user not found, deny
    IF user_tier IS NULL THEN
        RETURN FALSE;
    END IF;

    -- Check if user has premium subscription
    IF user_tier != 'FREE' THEN
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

    -- Check if FREE user is under the 20 message daily limit
    RETURN current_count < 20;
END;
$$;

-- Create function to increment user's daily message count
CREATE OR REPLACE FUNCTION increment_user_message_count(user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    user_tier TEXT;
    current_count INTEGER;
    last_reset DATE;
BEGIN
    -- Get user's subscription tier and current message count
    SELECT s.tier, u.daily_message_count, u.last_message_reset_date
    INTO user_tier, current_count, last_reset
    FROM users u
    LEFT JOIN subscriptions s ON u.id = s.user_id
    WHERE u.id = user_uuid;

    -- If user not found, return false
    IF user_tier IS NULL THEN
        RETURN FALSE;
    END IF;

    -- Premium users don't need count tracking
    IF user_tier != 'FREE' THEN
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

-- Create function to get user's remaining messages for the day
CREATE OR REPLACE FUNCTION get_user_remaining_messages(user_uuid UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    user_tier TEXT;
    current_count INTEGER;
    last_reset DATE;
    daily_limit INTEGER := 20;
BEGIN
    -- Get user's subscription tier and current message count
    SELECT s.tier, u.daily_message_count, u.last_message_reset_date
    INTO user_tier, current_count, last_reset
    FROM users u
    LEFT JOIN subscriptions s ON u.id = s.user_id
    WHERE u.id = user_uuid;

    -- If user not found, return 0
    IF user_tier IS NULL THEN
        RETURN 0;
    END IF;

    -- Premium users have unlimited messages
    IF user_tier != 'FREE' THEN
        RETURN -1; -- -1 indicates unlimited
    END IF;

    -- Reset count if it's a new day
    IF last_reset != CURRENT_DATE THEN
        RETURN daily_limit;
    END IF;

    -- Return remaining messages for FREE users
    RETURN GREATEST(daily_limit - current_count, 0);
END;
$$;

-- Create function to reset all daily message counts (for daily cron job)
CREATE OR REPLACE FUNCTION reset_daily_message_counts()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    reset_count INTEGER;
BEGIN
    UPDATE users 
    SET daily_message_count = 0, 
        last_message_reset_date = CURRENT_DATE
    WHERE last_message_reset_date < CURRENT_DATE;
    
    GET DIAGNOSTICS reset_count = ROW_COUNT;
    RETURN reset_count;
END;
$$;

-- Add trigger to automatically increment message count when messages are inserted
CREATE OR REPLACE FUNCTION auto_increment_message_count()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Only count user messages (not assistant messages)
    IF NEW.role = 'user' THEN
        -- Get the user_id from the chat
        DECLARE
            chat_user_id UUID;
        BEGIN
            SELECT user_id INTO chat_user_id
            FROM chats
            WHERE id = NEW.chat_id;
            
            -- Increment the user's message count
            PERFORM increment_user_message_count(chat_user_id);
        END;
    END IF;
    
    RETURN NEW;
END;
$$;

-- Create trigger on messages table to auto-increment count
CREATE TRIGGER auto_increment_user_message_count
    AFTER INSERT ON messages
    FOR EACH ROW EXECUTE FUNCTION auto_increment_message_count();

-- Add index for better performance on message count queries
CREATE INDEX IF NOT EXISTS idx_users_message_tracking ON users(last_message_reset_date, daily_message_count);
