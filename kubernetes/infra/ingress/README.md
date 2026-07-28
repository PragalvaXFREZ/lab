# ingress

How traffic reaches the cluster. The gateways that route inbound requests and the `cloudflared` tunnel that gives the cluster an outbound path without exposing the home network directly.

- [`cloudflared/`](./cloudflared) runs the outbound-only connectors and defines their cluster-side trust boundary.
