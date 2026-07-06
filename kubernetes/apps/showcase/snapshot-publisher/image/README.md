# image

The publisher's toolbox image: kubectl (pinned to the cluster's minor), jq, git, openssh-client, and check-jsonschema on Alpine.

Built and pushed to `ghcr.io/pragalvaxfrez/snapshot-publisher` by `.github/workflows/publisher-image.yaml` whenever this directory changes on main. The version tag is set in that workflow and must move together with the image pin in `../cronjob.yaml`.

The package must be public on ghcr so the nodes can pull it anonymously. A first push lands private by default; flipping it to public is a one-time setting on the package page.

Argo's directory source does not recurse into subdirectories, which is why these build files can sit here without ever being applied as manifests.
