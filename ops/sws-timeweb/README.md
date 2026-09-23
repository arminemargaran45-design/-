# Styling Wrap Studio — Timeweb deployment

This package moves SWS off `chatgpt.site` without changing the website content.

## Target
- Timeweb VPS: server 9066329
- Static site path: `/var/www/styling-wrap-studio/current`
- Source branch: `sws-site`
- Domains: `stylingwrapstudio.ru`, `www.stylingwrapstudio.ru`
- Existing ORVENIXA and MedAlliance services must remain untouched.

## Safe deployment on the server

```bash
cd /tmp
git clone --branch sws-site --single-branch https://github.com/arminemargaran45-design/-.git sws-deploy
cd sws-deploy
chmod +x ops/sws-timeweb/deploy.sh
sudo ./ops/sws-timeweb/deploy.sh
```

## Caddy

Back up the current configuration first:

```bash
sudo cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.backup-$(date +%Y%m%d-%H%M%S)
```

Merge `ops/sws-timeweb/Caddyfile.sws` into the existing `/etc/caddy/Caddyfile` without deleting any existing blocks.

Validate before reload:

```bash
sudo caddy validate --config /etc/caddy/Caddyfile
sudo systemctl reload caddy
```

## DNS cutover

After the SWS block is active on the VPS, update REG.RU so the root domain and `www` point to the Timeweb server instead of `chatgpt.site`. Remove only the old ChatGPT-site records for these hostnames; do not touch unrelated mail/TXT records.
