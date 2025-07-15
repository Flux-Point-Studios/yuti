# Supabase Integration for Cardevia Mobile

This document explains how the mobile app integrates with the same Supabase backend as the web application.

## Overview

The mobile app now uses **real Supabase authentication** instead of mock services, providing:
- ✅ **Unified user accounts** across web and mobile
- ✅ **Synchronized chat history** between platforms  
- ✅ **Real subscription management** with tier enforcement
- ✅ **Consistent backend APIs** and database schema
- ✅ **Production-ready authentication** with password reset

## Configuration

The app connects to your existing Supabase project:

- **URL**: `https://zlvcevggynsrmvyiaxru.supabase.co`
- **Anon Key**: Configured in `lib/services/supabase_service.dart`
- **Admin Emails**: Same admin emails as web app for special access

## Database Schema

The mobile app uses the same tables as the web app:

### `users` table
- `id` (UUID) - User identifier
- `email` - User email address  
- `customer_id` - Stripe customer ID
- `created_at` - Account creation timestamp

### `subscriptions` table
- `user_id` (UUID) - Foreign key to users
- `tier` - Subscription tier (FREE, BASIC, PREMIUM, VIP)
- `status` - Subscription status (active, inactive, trialing)
- `subscription_id` - Stripe subscription ID
- `ended_at` - Subscription end date

### `chats` table
- `id` (UUID) - Chat session identifier
- `user_id` (UUID) - Foreign key to users
- `title` - Chat session title
- `path` - URL path for web app
- `created_at` - Chat creation timestamp

### `messages` table
- `id` (UUID) - Message identifier
- `chat_id` (UUID) - Foreign key to chats
- `content` - Message content
- `role` - Message role (user/assistant)
- `created_at` - Message timestamp

## Key Features

### Authentication
```dart
// Real Supabase authentication
final result = await AuthService().signIn(
  email: email, 
  password: password
);

// Password reset
await AuthService().resetPassword(email: email);
```

### Chat Synchronization
- Chat sessions automatically sync with server
- Messages saved to both local storage and Supabase
- Cross-platform chat history access

### Subscription Management
```dart
// Check subscription access
final hasAccess = await AuthService().checkSubscriptionAccess();

// Get user tier
final tier = AuthService().getUserTier(); // FREE, BASIC, PREMIUM, VIP

// Update subscription
await AuthService().updateUserTier('PREMIUM');
```

### Admin Access
Admin emails (same as web app) automatically get:
- VIP tier access
- Unlimited features
- Bypass subscription checks

## Local Development

1. **Install dependencies**:
   ```bash
   flutter pub get
   ```

2. **Run the app**:
   ```bash
   flutter run
   ```

3. **Test authentication**:
   - Sign up creates real Supabase user
   - Login uses actual credentials
   - Chat history syncs with web app

## Production Deployment

The app is ready for production with:
- ✅ Real user authentication
- ✅ Secure credential storage
- ✅ Backend data synchronization
- ✅ Subscription tier enforcement
- ✅ Cross-platform compatibility

## Comparison: Before vs After

| Feature | Mock Service | Supabase Integration |
|---------|-------------|-------------------|
| **Authentication** | Local simulation | Real Supabase auth |
| **User Data** | Hardcoded tiers | Database-backed |
| **Chat History** | Local only | Synced across platforms |
| **Subscriptions** | Fake updates | Real Stripe integration |
| **Password Reset** | Simulated | Actual email sent |
| **Cross-Platform** | None | Full synchronization |

The mobile app now provides a true companion experience to the web application with shared user accounts, synchronized data, and consistent functionality. 