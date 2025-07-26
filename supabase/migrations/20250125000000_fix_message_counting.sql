-- Fix message counting logic to count Assistant responses instead of User messages
-- The daily limit should apply to Agent T responses, not user messages

-- Drop the existing trigger
DROP TRIGGER IF EXISTS auto_increment_user_message_count ON messages;

-- Update the function to count assistant messages instead of user messages
CREATE OR REPLACE FUNCTION auto_increment_message_count()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Only count assistant messages (Agent T responses), not user messages
    -- This is because we want to limit Agent T responses to 20 per day for FREE users
    -- Exclude greeting messages from counting
    IF NEW.role = 'assistant' AND 
       NEW.content NOT LIKE 'Hello! I''m Agent T, your crypto concierge.%' THEN
        -- Get the user_id from the chat
        DECLARE
            chat_user_id UUID;
        BEGIN
            SELECT user_id INTO chat_user_id
            FROM chats
            WHERE id = NEW.chat_id;
            
            -- Increment the user's message count (counting Agent T responses)
            PERFORM increment_user_message_count(chat_user_id);
        END;
    END IF;
    
    RETURN NEW;
END;
$$;

-- Recreate the trigger
CREATE TRIGGER auto_increment_user_message_count
    AFTER INSERT ON messages
    FOR EACH ROW EXECUTE FUNCTION auto_increment_message_count();

-- Reset all daily message counts to account for the counting logic change
-- This ensures everyone starts fresh with the corrected counting
UPDATE users 
SET daily_message_count = 0, 
    last_message_reset_date = CURRENT_DATE;