# Noffin

A minimal Android app for tracking mess tiffin absences on a billing-cycle calendar and calculating bills automatically.

## Supabase Setup

1. **Create a Supabase Project**:
   - Go to [supabase.com](https://supabase.com) and create a new project.
2. **Run the Database Schema**:
   - In your Supabase dashboard, open the **SQL Editor**.
   - Copy and paste the contents of `supabase/schema.sql` and run it.
3. **Enable Email Authentication**:
   - In **Authentication** → **Sign In / Providers**, enable the **Email** provider for sign-in and account creation.
4. **Retrieve API Keys**:
   - Navigate to **Project Settings** → **API**.
   - Copy your **Project URL** and **Publishable key**. Do not use a secret/service-role key in the app.

## Configuration

Set your Supabase credentials using either a `.env` file or `--dart-define`.

### Option A: `.env` file
Create or edit `.env` in the project root:
```env
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_PUBLISHABLE_KEY=your-publishable-key
```
Replace both example values with credentials from your Supabase project. The app shows a setup screen rather than connecting if these placeholders are unchanged.

### Option B: `--dart-define`
Run directly with arguments:
```bash
flutter run --dart-define=SUPABASE_URL=https://your-project.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=your-publishable-key
```

## Running the App

Run on an Android device or emulator:
```bash
flutter run
```

Run tests:
```bash
flutter test
```

Analyze code:
```bash
flutter analyze
```
