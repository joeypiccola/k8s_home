# dyndns

A CronJob runs every hour in the `dyndns` namespace using a PowerShell Alpine container. It executes `Update-DNS.ps1`, which:

1. **Checks the current external IP** via `icanhazip.com`
2. **Compares it to the last known IP** stored in a state file on a 100Mi Longhorn PVC (`/data/lastip`)
3. **If the IP changed** — hits the FreeDNS update URL (which uses automatic IP detection) to update the DNS record, then sends a Pushover notification with the old and new IPs
4. **If unchanged** — exits cleanly

Secrets (FreeDNS URL, Pushover token/user) are pulled from 1Password via an ExternalSecret. The PowerShell script itself and the non-secret config (API URIs) live in a ConfigMap that is also mounted as the `/scripts` volume.

## example log

```text
INFO: PSVersion = 7.4.2
INFO: state file detected
INFO: 1.2.3.4 was last detected IP
INFO: 1.2.3.4 was detected as current IP
INFO: last checked IP of 1.2.3.4 was matches current IP of 1.2.3.4 was. nothing to do, exiting
stream closed: EOF for dyndns/dyndns-update-29630460-st84h (powershell)
```
