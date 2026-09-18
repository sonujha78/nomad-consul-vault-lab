# NATS: Plain Pub-Sub vs JetStream

## What was demonstrated
- **Plain NATS pub-sub**: `order-created` publisher + `notification` subscriber,
  fire-and-forget, no persistence, no queue — pure in-memory delivery to
  currently-connected subscribers only.
- **JetStream** (`ORDERS` stream): same subject (`order-created`) also captured
  into a persistent, file-backed stream. Verified messages accumulate on disk
  (Storage: File) and survive independently of whether a subscriber is
  connected at publish time.

## The trade-off (interview-relevant: "when would you NOT use Kafka")
Plain NATS pub-sub is the right choice when:
- Consumers only care about "now" (live dashboards, ephemeral notifications)
- Message loss during a consumer outage is acceptable
- You want the lowest possible latency and zero storage/ops overhead
- No need for replay, consumer groups, or exactly-once semantics

JetStream (or Kafka) is the right choice when:
- Messages must survive a consumer being offline (replay from any point)
- You need durable delivery guarantees, acknowledgments, or exactly-once
- Multiple consumer groups need independent read positions
- Audit/compliance requires a persisted log of every event

**Kafka is often overkill** for internal service-to-service notifications,
cache invalidation, or ephemeral status updates — the operational cost
(ZooKeeper/KRaft, partition management, broker tuning) isn't justified when
plain pub-sub or a lightweight JetStream stream solves the actual problem.
NATS lets a team start with zero persistence and opt into durability
per-subject, rather than committing to Kafka's operational model up front
for every message type.
