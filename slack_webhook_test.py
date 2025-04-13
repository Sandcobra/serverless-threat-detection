import json, os, requests
from dotenv import load_dotenv

load_dotenv()

webhook_url = os.getenv("SLACK_WEBHOOK")
message = {
    "text": "*Test Alert:* This is a test of the IAM Threat Detection Pipeline."
}
response = requests.post(webhook_url, json=message)
print(response.status_code, response.text)
