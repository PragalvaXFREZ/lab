# patches

Reusable Talos configuration patches, applied on top of the base machine configs so common settings are defined once and shared across nodes rather than copied into each machineconfig.

`netbird.extensionserviceconfig.example.yaml` is a secret-free enrollment template. Append it to the complete live configuration for exactly one node, including that node's auxiliary volume documents, dry-run the full document set, then insert a one-off setup key and apply it. Never commit or paste a live setup key.
