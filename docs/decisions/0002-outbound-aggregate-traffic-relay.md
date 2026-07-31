# 0002 - Outbound aggregate traffic relay

- Status: accepted
- Date: 2026-07-31

## Context

The hourly public snapshot carries six hours of aggregate Hubble flow and drop rates. It is durable and safe when Devata or its uplink is unavailable, but it cannot drive a near-live chart. Hubble Relay and Prometheus are LAN-only, and exposing either would reveal a larger interface than the public chart needs.

## Decision

Run a single GitOps-managed producer in Devata. It queries only the two aggregate Prometheus rates and pushes a closed three-field payload outbound every five seconds. It has no Service or inbound route.

Use a Cloudflare Worker with one SQLite-backed Durable Object as the public relay. The relay authenticates writes, validates the closed payload, rejects replays and excessive writes, retains six hours, and fans accepted samples out through hibernating WebSockets. The browser remains a read-only consumer. The hourly snapshot remains the fallback and historical proof surface.

## Consequences

- Nothing accepts unsolicited inbound traffic on the home network.
- The public contract cannot grow by accidentally forwarding Prometheus labels or Hubble flow fields.
- Five-second publishing adds one small always-on workload and about 17,280 relay writes per day.
- The relay depends on Cloudflare Workers, Durable Objects, DNS, and one producer credential.
- A relay outage makes the stream stale; it does not erase or fabricate the hourly snapshot.
- The portfolio integration is a separate change after the producer and relay are verified live.
