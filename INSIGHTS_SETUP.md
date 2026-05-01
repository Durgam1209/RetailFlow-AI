# RetailFlow AI Insights - Setup & Troubleshooting Guide

## ✅ If Insights Are Not Updating

Follow these steps to ensure the system is working properly:

### Step 1: Create the `daily_insights` Table (if it doesn't exist)

1. Go to [Supabase Dashboard](https://app.supabase.com)
2. Select your project
3. Click **SQL Editor** → **New Query**
4. Copy and paste the entire content from: `sql/setup_daily_insights_table.sql`
5. Click **Run**

This creates the table with proper RLS policies so:
- Flutter app (anon key) can **READ** insights
- Python backend (service role key) can **INSERT** insights

---

### Step 2: Run the Python ML Pipeline

```powershell
cd C:\projects\RetailFlowAI
python ml_pipeline/main.py
```

You should see:
```
>>>..Starting RetailFLow AI Intelligence pipeline....
....Running Market Basket Analysis....
....Generating Demand Forecasts....
✓ Insights successfully pushed to cloud!
   Forecast: 7-day growth trend looks positive.
   Bundles: X recommendations
   Stock advice: 7 days forecasted
Pipeline Complete. Insights are ready!!
```

---

### Step 3: Verify Data in Supabase

1. Go to Supabase Dashboard
2. Click **Database** → **Tables**
3. Select `daily_insights`
4. You should see at least 1 row with:
   - `forecast_summary` (text)
   - `suggested_bundles` (JSON array)
   - `stock_advice` (JSON array)
   - `festival_advice` (JSON object)
   - `created_at` (timestamp)

---

### Step 4: Run the Flutter App

```powershell
cd C:\projects\RetailFlowAI\murali_fruits_ml
flutter run --dart-define=SUPABASE_URL=https://yswbklftnuioiwhbjsgv.supabase.co --dart-define=SUPABASE_ANON_KEY=<your_anon_key>
```

Open the **AI Insights** tab to see the recommendations.

---

## 🔧 Common Issues & Fixes

### **Issue: "No AI insights available yet"**

**Cause:** The table exists but is empty, or the query isn't finding data.

**Fix:**
1. Run `python ml_pipeline/main.py` to generate fresh insights
2. Check Supabase Dashboard that rows were inserted
3. Verify `created_at` column is recent (within last few minutes)

---

### **Issue: Flutter App Crashes When Opening Insights Tab**

**Cause:** Supabase not initialized or anon key is wrong.

**Fix:**
1. Check that the `--dart-define` flags are correct in your flutter run command
2. Verify you're using the **ANON KEY** (not service role key) for Flutter
3. Check console for error messages: Look for RLS policy denials

---

### **Issue: "Error loading insights: 42501 row-level security policy"**

**Cause:** RLS policy doesn't allow anon key to read.

**Fix:**
1. Run the SQL setup script from `sql/setup_daily_insights_table.sql`
2. Make sure the SELECT policy for `anon` role exists:
   ```sql
   CREATE POLICY "Anyone can read daily insights"
     ON public.daily_insights
     FOR SELECT
     USING (true);
   ```

---

### **Issue: Python Script Says "RLS policy for insert"**

**Cause:** Service role key is missing or incorrectly configured.

**Fix:**
1. Get your **Service Role Secret** from Supabase Settings → API
2. Add it to `ml_pipeline/.env`:
   ```
   SUPABASE_SERVICE_ROLE_KEY=your_service_role_key
   ```
3. Run: `python ml_pipeline/main.py`

---

## 📊 Data Flow Diagram

```
┌──────────────────────────────────────────────────────────────┐
│                    RetailFlow AI Pipeline                     │
└──────────────────────────────────────────────────────────────┘

1. Raw Sales Data
   ↓
2. Python ML Pipeline (main.py)
   - Basket Analysis → suggested_bundles
   - Demand Forecasting → stock_advice
   ↓
3. Format & Push to Supabase (using Service Role Key)
   ↓
4. Supabase Database (daily_insights table)
   ↓
5. Flutter App Fetches (using Anon Key) → Displays in UI
```

---

## ✨ Expected Output Format

When the pipeline runs successfully, this JSON is inserted:

```json
{
  "forecast_summary": "7-day growth trend looks positive.",
  "suggested_bundles": [
    {
      "pair_1": "Lemon",
      "pair_2": "Ginger",
      "confidence": 0.75,
      "lift": 1.2,
      "advice": "Customers who buy Lemon often look for Ginger. Consider placing them together."
    }
  ],
  "stock_advice": [
    {
      "date": "2026-05-01",
      "predicted_demand": 45.3,
      "upper_bound": 52.1,
      "lower_bound": 38.5
    }
  ],
  "festival_advice": {
    "is_active": true,
    "priority": "High",
    "festival_name": "Buddha Purnima",
    "title": "Tomorrow is Buddha Purnima",
    "action": "Stock up on Banana, Apple Washington, Pomegranate today.",
    "merchandising": "Place these fruits at the front of the shop for faster pickup."
  }
}
```

---

## 🚀 Quick Start Checklist

- [ ] SQL table created (`setup_daily_insights_table.sql`)
- [ ] Service role key added to `ml_pipeline/.env`
- [ ] Python pipeline runs successfully
- [ ] Rows visible in Supabase `daily_insights` table
- [ ] Flutter app displays insights without errors

If you still have issues, check the console output for error messages and let me know! 🔍
