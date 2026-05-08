# ML Pipeline Setup Guide

## Prerequisites

Before running the ML pipeline, you need to set up your Supabase credentials.

## Setup Steps

### 1. Create a `.env` file

Copy the `.env.example` file to `.env`:

```bash
cp ml_pipeline/.env.example ml_pipeline/.env
```

### 2. Configure Supabase Credentials

Edit `ml_pipeline/.env` and add your Supabase credentials:

```
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_KEY=your-anon-key-here
```

**Where to find these values:**
- Go to your Supabase project dashboard
- Click **Settings** → **API**
- Copy the **Project URL** and paste it as `SUPABASE_URL`
- Copy the **anon public** key and paste it as `SUPABASE_KEY`

### 3. (Optional) Use Service Role Key for Better Security

For production pipelines, use the service role key instead:

```
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key-here
```

The pipeline will use this if available, otherwise falls back to the anon key.

### 4. Verify Training Data

Ensure the training data CSV exists at:
```
ml_pipeline/data/processed/master_training_data.csv
```

### 5. Run the Pipeline

```bash
python ml_pipeline/main.py
```

## Recent Improvements

The pipeline now includes:
- **Automatic retry logic** with exponential backoff for network issues
- **Better error messages** to help diagnose configuration problems
- **Proper HTTP client configuration** to eliminate deprecation warnings
- **Detailed logging** to track data fetching progress

## Troubleshooting

### "Connection forcibly closed" error
This usually means:
1. Supabase credentials are invalid or missing
2. Your network has firewall restrictions
3. Supabase server is temporarily unavailable

**Solution:** Check your `.env` file has correct credentials and try again.

### "Missing required environment variable" error
You need to create the `.env` file with your Supabase credentials (see Step 1-2 above).

### "Training data not found" error
Ensure `master_training_data.csv` exists in `ml_pipeline/data/processed/`
