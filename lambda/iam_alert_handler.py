import json, os, requests

SUSPICIOUS_EVENTS = ["CreateAccessKey", "AttachUserPolicy", "DeleteUser"]
WEBHOOK_URL = os.environ.get("WEBHOOK_URL")


def lambda_handler(event, context):
    print("EventBridge event received:", json.dumps(event))
    detail = event.get("detail", {})
    event_name = detail.get("eventName")
    user_identity = detail.get("userIdentity", {}).get("userName", "Unknown")

    if event_name in SUSPICIOUS_EVENTS:
        alert = {
            "event": event_name,
            "user": user_identity,
            "timestamp": detail.get("eventTime"),
            "region": event.get("region")
        }
        print(f"Suspicious activity detected: {alert}")

        try:
            message = {
                "content": f"🚨 *Suspicious IAM Activity Detected:*\n```json\n{json.dumps(alert, indent=2)}\n```"
            }
            response = requests.post(WEBHOOK_URL, json=message)
            print(f"Webhook response: {response.status_code}, {response.text}")
        except Exception as webhook_error:
            print(f"Failed to send alert: {webhook_error}")





