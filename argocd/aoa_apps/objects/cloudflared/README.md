# cloudflared

## installed binary locally

`brew install cloudflared`

login, prompting browser, and authorized the creation of certs in a zone.

```text
> cloudflared tunnel login
You have successfully logged in.
If you wish to copy your credentials to a server, they have been saved to:
/<path>/<user>/.cloudflared/cert.pem
```

> Success, Cloudflared has installed a certificate allowing your origin to create a Tunnel on this zone.

## create the tunnel

```text
> cloudflared tunnel create k8shome
Tunnel credentials written to /<path>/<user>/.cloudflared/<blah>.json. cloudflared chose this file based on where your origin certificate was found. Keep this file secret. To revoke these credentials, delete the tunnel.
Created tunnel k8shome with id <blah>
```
