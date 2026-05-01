import pandas as pd
import requests
import holidays
from supabase import create_client
import os 

# 1. Database & API Setup
url = "https://yswbklftnuioiwhbjsgv.supabase.co"
key = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inlzd2JrbGZ0bnVpb2l3aGJqc2d2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM4MjY3OTUsImV4cCI6MjA4OTQwMjc5NX0.ezZh3VeoTS7WZH8p_xP_uXiKreSVK62BBqK7UEG9zJg"
weather_api_key ="d653f3cef6031de43e224e93997658fa"

supabase = create_client(url, key)

# 2. Fetch Raw Data[cite: 1]
# Pulls the transaction logs your parents created in the Flutter app
print("Fetching data from Supabase...")
response = supabase.table("sales_log").select("*").execute()
df = pd.DataFrame(response.data)
print(f"✓ Fetched {len(df)} rows from sales_log")

# 3. Add Indian Holiday Context
print("Processing Indian holidays...")
in_holidays = holidays.India()
df['is_holiday'] = df['created_date'].apply(lambda x: x in in_holidays)
print("✓ Holiday context added")

# 4. Fetch Weather Data
def get_weather(date_str):
    # Calls OpenWeather to get temp/conditions for that specific day
    # This turns '2024-05-01' into '34°C, Sunny'
    pass 

# 5. Export to Master File
print("Exporting to CSV...")
df.to_csv('master_training_data.csv', index=False)
print("✓ Data saved to master_training_data.csv")