# Polly Advisor — iOS client

A read-only iOS client for the Polly advisor engine. It polls a self-hosted
advisor over WireGuard and presents live up/down market state: fair value vs
market ask, net edge after the taker fee, feed health, graded hit rate, and
the engine's own signals.

The app **never places orders**. Every trade is executed by the operator on
their own device. The engine stays advisory (`exec.enabled = false`).

Built with [Jeho974/ipa-build-template](https://github.com/Jeho974/ipa-build-template).
Push to `main` to produce an unsigned `.ipa` release; install via SideStore.

## What it talks to

| Endpoint | Purpose |
|---|---|
| `GET /api/state` | Spot/TWAP health, book, live windows with snapshots |
| `GET /api/advice?limit=N` | Recorded signals (bare JSON array) |
| `GET /api/scorecard?days=N` | Graded hit rate by confidence bucket |
| `GET /api/exec` | Execution posture (advisory vs armed) |
| `GET /healthz` | Reachability probe for the settings screen |

Auth is HTTP Basic. The password is stored in the **Keychain**, never in
`UserDefaults`. Transport is plain HTTP over a private WireGuard address, so
`NSAllowsArbitraryLoads` is enabled deliberately — the host is not reachable
from the open internet.

## Screens

- **Markets** — actionable windows first (edge clears the fee), then the full
  board. Each card carries a countdown ring, spot-vs-beat delta in basis
  points, a sparkline against the strike, and a fair-value/market bar where
  the gap between the fill and the marker *is* the edge.
- **Signals** — the engine's recorded advice, filterable by buys and exits.
- **Edge** — graded hit rate, per-confidence-bucket breakdown, and an explicit
  warning when a bucket is statistically dead.
- **Settings** — endpoint, credentials, poll interval, connection test.

## Design

Dark instrument-panel aesthetic. Colour is semantic only: mint = edge/up,
rose = down/overpriced, amber = attention. All numerals are monospaced so
columns align across cards. Hairline strokes and one continuous corner radius
keep the surfaces quiet.

## Build

The IPA is compiled on a macOS runner and left **unsigned**; the device
re-signs it (SideStore / LiveContainer).

```bash
git push origin main          # triggers .github/workflows/build.yml
```

Output: tag `ipa-YYYYMMDD-HHMM-<sha7>` with `<AppName>-<version>-<sha7>.ipa`
and a `sidestore-source.json` addable directly in SideStore → Sources.

Local verification after download:

```bash
unzip -o PollyAdvisor-*.ipa -d verify
file verify/Payload/*.app/PollyAdvisor        # Mach-O 64-bit arm64
```

## Layout

```
Sources/PollyAdvisor/
  PollyAdvisorApp.swift   app entry, UIKit chrome appearance
  Theme.swift             palette, type scale, formatters, base components
  Models.swift            Codable models mirroring the live API
  PollyClient.swift       URLSession client + Keychain storage
  AppModel.swift          settings, polling loop, per-window history
  Components.swift        ring, sparkline, probability bar, chips
  DashboardView.swift     markets board + window detail
  SecondaryViews.swift    signals, edge scorecard, settings
tools/make_icon.py        regenerates the app icon + colour assets
```

Regenerate the icon after changing the palette:

```bash
python3 tools/make_icon.py
```

### Board layout

The Markets tab is ordered by contract length — **5 min**, **10 min**, **15 min** —
and the single best trade is pinned above them, with an executable plan: entry
price, exit target, breakeven, share count at a $50 reference stake, expected
profit, and what to do if it has not filled by T-60s.

Polymarket only lists 5- and 15-minute crypto Up/Down markets; the 10-minute
section is present so the gap is visible rather than silently missing.

Motion is centralised in `AnimationKit.swift` (`Motion.value / .shape / .board`),
numbers use `contentTransition(.numericText())`, and countdowns run on a 1-second
`TimelineView` derived from the real close time, so the board eases between polls
instead of jumping.
