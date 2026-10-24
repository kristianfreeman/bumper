# playbumper.com

Bumper's website: one static page, plus Privacy, Support, What's new and
poster credits. No build step and nothing loaded from anyone else (fonts,
posters and the script are all here).

```
website/
  index.html            the page
  privacy/ support/     the App Store's privacy and support links
  changelog/            generated from CHANGELOG.md — don't edit by hand
  credits/              where each poster comes from
  assets/site.css       the Late Show look: near-black, amber, Geist
  assets/posters/       82 public-domain horror posters (credits.json)
  assets/fonts/         Geist (SIL Open Font License, OFL.txt)
  _headers              Cloudflare Pages: caching and security headers
```

## Working on it

Preview locally (any static server):

```bash
python3 -m http.server 4321 --directory website
```

After editing CHANGELOG.md, rebuild What's new:

```bash
scripts/site-changelog.py
```

## Deploying

The site is a Cloudflare Pages project named `playbumper`.

```bash
scripts/site-deploy.sh preview
```

```bash
scripts/site-deploy.sh
```

First time: the script asks wrangler to sign in to Cloudflare, and creates
the project if it doesn't exist. Then attach the domain in the Cloudflare
dashboard: Workers & Pages → playbumper → Custom domains → playbumper.com
(and www.playbumper.com, redirected to it).

`support@playbumper.com` is on the Privacy and Support pages: set it up with
Cloudflare Email Routing (Email → Email Routing → forward to your inbox).

## Posters

All public domain, from Wikimedia Commons; `assets/posters/credits.json`
lists each one's Commons page, and `/credits/` shows them. Famous titles that
Commons lists as public domain but whose studios still guard them (Psycho,
The Birds, Jaws, Godzilla) were left out on purpose.
