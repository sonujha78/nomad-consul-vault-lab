import asyncio
import json
import random
import time
from nats.aio.client import Client as NATS

async def main():
    nc = NATS()
    await nc.connect("nats://nats:4222")
    print("Publisher connected to NATS")

    order_id = 1
    while True:
        event = {
            "order_id": order_id,
            "item": random.choice(["laptop", "phone", "headphones", "keyboard"]),
            "timestamp": time.time()
        }
        await nc.publish("order-created", json.dumps(event).encode())
        print(f"Published: {event}")
        order_id += 1
        await asyncio.sleep(5)

if __name__ == "__main__":
    asyncio.run(main())
