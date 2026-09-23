# k8s / remote-cluster planes — legacy

These guides and boot scripts powered Turbo Flow v4's DevPod-on-Kubernetes
execution planes (Rackspace spot clusters, Google Cloud Shell). They are
**community-maintained and unverified since v4** — Turbo Flow now targets
**GitHub Codespaces as its primary, release-verified plane** (open this repo
in a Codespace; `postCreate` runs the full install chain).

Kept because the multi-cloud escape hatch matters if Codespace terms ever
change. If you revive one of these planes, verify it against
`devpods/tf-verify.sh` and remove this notice.
