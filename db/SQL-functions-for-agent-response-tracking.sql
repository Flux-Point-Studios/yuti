-- BlueLight: Updated Message Limit Functions - Track Agent T Responses
-- Date: July 19, 2025
-- Purpose: Count Agent T responses instead of user messages for daily limits

-- Function to check if user can receive more Agent T responses (track assistant messages, not user messages)
CREATE OR REPLACE FUNCTION public.can_user_send_message(user_uuid uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    user_tier text;
    agent_responses_today integer;
BEGIN
    -- Get user tier from subscriptions table
    SELECT COALESCE(s.tier, 'FREE')
    INTO user_tier
    FROM auth.users u
    LEFT JOIN public.subscriptions s ON u.id = s.user_id
    WHERE u.id = user_uuid;
    
    -- Premium users have unlimited messages
    IF user_tier = 'PREMIUM' OR user_tier = 'premium' THEN
        RETURN true;
    END IF;
    
    -- For FREE users, check daily limit (20 AGENT RESPONSES)
    SELECT COUNT(*)
    INTO agent_responses_today
    FROM public.messages cm
    JOIN public.chats cs ON cm.chat_id = cs.id
    WHERE cs.user_id = user_uuid
    AND cm.role = 'assistant'  -- Count Assistant/Agent T responses, not user messages
    AND DATE(cm.created_at) = CURRENT_DATE;
    
    -- Return true if under limit (can still get more Agent responses)
    RETURN agent_responses_today < 20;
END;
$$;

-- Function to get remaining Agent T responses for today
CREATE OR REPLACE FUNCTION public.get_user_remaining_messages(user_uuid uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    user_tier text;
    agent_responses_today integer;
BEGIN
    -- Get user tier from subscriptions table
    SELECT COALESCE(s.tier, 'FREE')
    INTO user_tier
    FROM auth.users u
    LEFT JOIN public.subscriptions s ON u.id = s.user_id
    WHERE u.id = user_uuid;
    
    -- Premium users have unlimited messages
    IF user_tier = 'PREMIUM' OR user_tier = 'premium' THEN
        RETURN 999999; -- Effectively unlimited
    END IF;
    
    -- For FREE users, calculate remaining Agent T responses from 20 daily limit
    SELECT COUNT(*)
    INTO agent_responses_today
    FROM public.messages cm
    JOIN public.chats cs ON cm.chat_id = cs.id
    WHERE cs.user_id = user_uuid
    AND cm.role = 'assistant'  -- Count Assistant/Agent T responses
    AND DATE(cm.created_at) = CURRENT_DATE;
    
    -- Return remaining Agent T responses (minimum 0)
    RETURN GREATEST(0, 20 - agent_responses_today);
END;
$$;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION public.can_user_send_message(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_user_remaining_messages(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_user_send_message(uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.get_user_remaining_messages(uuid) TO anon;

-- Refresh the schema cache
NOTIFY pgrst, 'reload schema'; 