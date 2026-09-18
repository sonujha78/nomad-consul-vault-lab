import asyncio
import json
from nats.aio.client import Client as NATS

async def main():
    nc = NATS()
    await nc.connect("nats://nats:4222")
    print("Notification subscriber connected to NATS")

    async def message_handler(msg):
        event = json.loads(msg.data.decode())
        print(f"[notification-service] New order received: {event}")
        print(f"[notification-service] Sending notification for order #{event['order_id']} ({event['item']})")

    await nc.subscribe("order-created", cb=message_handler)
    print("Subscribed to 'order-created' subject")

    while True:
        await asyncio.sleep(1)

if __name__ == "__main__":
    asyncio.run(main())
