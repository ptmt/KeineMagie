# Current tinyserve infrastructure deployment

Backend hostname: https://keinemagie.tinyserve.org

Verified publicly through Cloudflare with normal TLS validation (explicit DNS resolution to a Cloudflare address because the local resolver still cached NXDOMAIN): GET /health returns 200 and real server JSON; POST /v1/translations returns 503. No OpenAI key or shared auth token is deployed. Apple login and connected ChatGPT are not implemented. Cache-Control is no-store and Cloudflare reports DYNAMIC; no cache purge required.

## Local image limitations
Image: keinemagie:local, built from server sources. Docker lacks buildx; build used a scratch copy of Dockerfile with `FROM --platform=$BUILDPLATFORM` replaced by native `FROM`. Repository Dockerfile unchanged.

`tinyserve service add --name keinemagie --image keinemagie:local --port 8787 --hostname keinemagie.tinyserve.org --auto-volumes --cloudflare` registered the service. DNS CNAME was created through Cloudflare API and read back.

`tinyserve deploy --service keinemagie` fails because it unconditionally pulls the local image from a registry. The generated configuration was left in a staging directory; current configuration was not promoted. To start the real server and route its hostname, used:

```
docker-compose -p tinyserve -f '/Users/tinyserve/Library/Application Support/tinyserve/generated/.staging-20261108-144857/docker-compose.yml' up -d --pull never --no-deps keinemagie cloudflared
```

Both containers are running, and tinyserve service list reports keinemagie running. This is a development deployment workaround, not a fully supported tinyserve deploy lifecycle. A later tinyserve deploy may replace the tunnel configuration. Resolve by supporting local images in tinyserve or publishing to an authorized registry, then deploy normally. No registry image was published.

Auto-volumes did not add persistence mounts for this image. Before storing real user/account/history data, explicitly configure persistent storage, encryption and backups. No users or provider credentials exist in this deployment.
