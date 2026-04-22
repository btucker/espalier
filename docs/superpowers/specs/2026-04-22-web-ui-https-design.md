# Web UI — HTTPS Migration — Design

## Problem

Graftty's web server (SPECS §§WEB-1..6) ships plaintext HTTP. SPECS `WEB-6.1` explicitly punts TLS on the grounds that Tailscale already encrypts the wire. That is correct at the transport level, but a user copying `http://[fd7a:115c::5]:8799/` still sees their browser mark the page "Not Secure", and every `http://` URL Graftty emits is a paper cut against the project's security posture.

This design moves the web UI to HTTPS-only, using Tailscale-issued Let's Encrypt certificates for the machine's MagicDNS name. The primary goal is cosmetic/hygienic — no `http://` URLs anywhere, no "Not Secure" badges — not unlocking secure-context browser APIs (clipboard, service workers, PWA install). That clarity of motivation lets us choose the simplest cert-provisioning path and refuse any fallback that would still ship an `http://` URL.

## Non-goals

- **Not a secure-context API unlock.** If a follow-up wants `navigator.clipboard.writeText` to work (e.g., for OSC 52 clipboard sync), that's a separate feature.
- **Not a Tailscale-independence story.** The server still only binds to Tailscale peers and still gates access via `whois`. This change replaces one Tailscale dependency (encryption of the tunnel) with a second (cert issuance); neither works without Tailscale.
- **Not an external ACME client.** Graftty does not talk to Let's Encrypt, does not hold a Let's Encrypt account, does not perform HTTP-01 or DNS-01 challenges. `tailscaled` owns all of that.
- **Not self-signed with a local root CA.** That approach requires per-device root installation, is especially painful on iOS, and was rejected during brainstorming.
- **Not an HTTP→HTTPS redirect listener.** There is no HTTP bind at all, so old `http://` bookmarks will fail to connect. Users update to the new hostname URL.

## Trust anchor & hostname

All cert material comes from **Tailscale LocalAPI**, which Graftty already talks to for `whois` and address enumeration:

- `GET /localapi/v0/status` → returns `Self.DNSName` (FQDN, with trailing dot), e.g. `macbook.tail-abc12.ts.net.`. Strip the trailing dot; this is the name the cert will be valid for and the hostname embedded in every copyable URL.
- `GET /localapi/v0/cert/<fqdn>?type=pair` → returns a PEM cert chain + PEM private key for `<fqdn>`, fetching from Let's Encrypt (via DNS-01 against `ts.net`, which Tailscale controls) and caching inside `tailscaled` itself.

Graftty never writes the cert or key to disk. The only copy Graftty holds is the in-memory `NIOSSLContext` it builds from the returned bytes.

## Binding

Per SPECS `WEB-1.1`, the server today binds to each Tailscale IPv4/IPv6 address reported by LocalAPI and also to `127.0.0.1`. After this change:

- **Keep** binding to each Tailscale IPv4/IPv6 address. MagicDNS resolves the FQDN to those IPs, so a browser typing `https://macbook.tail-abc12.ts.net:8799/` lands on one of our bound sockets. The TLS handshake validates by SNI (the name the browser sends), not by destination IP, so certing the hostname is sufficient even though the socket address is an IP.
- **Drop** the `127.0.0.1` bind. Rationale: keeping it would force one of two bad options —
  1. Serve the same `hostname.ts.net` cert on `127.0.0.1` → every local-loopback browser connection produces a permanent cert-name-mismatch warning, defeating the whole project.
  2. Run a parallel HTTP listener on `127.0.0.1` → re-introduces the `http://` URL surface this project is trying to eliminate.
- Local connections continue to work: MagicDNS resolves the FQDN locally, so `https://macbook.tail-abc12.ts.net:8799/` on the same machine connects to the Tailscale IP, which is bound by the same process.

Consequence: SPECS `WEB-2.5` (loopback bypass of `whois`) becomes dead weight and is removed. Local-machine connections now arrive as a normal Tailscale peer, `whois` resolves them as the same user that runs the Mac, and the existing `WEB-2.2` same-user check lets them through.

## TLS layer

Wrap the NIO `ServerBootstrap`'s child pipeline with `NIOSSL`'s `NIOSSLServerHandler`, initialized from a `NIOSSLContext` built from the PEM pair returned by LocalAPI. The existing HTTP/1.1 + WebSocket-upgrade pipeline sits behind the TLS handler untouched — TLS is a purely additive layer on the bottom of the pipeline.

A single `NIOSSLContext` instance is shared across all channels. The per-channel `ChannelInitializer` reads the current context from an atomic-pointer wrapper (see cert rotation below) and installs a fresh `NIOSSLServerHandler(context:)` on each new channel.

## Cert lifecycle

### No Graftty-side disk cache

`tailscaled` already caches the cert in its own state directory and returns it in microseconds over LocalAPI. A Graftty-side cache would duplicate that state, demand 0600 file permissions and rotation logic, and save nothing measurable. Skip it. On every bind (server start, port change, cert rotation), we refetch from LocalAPI.

### Renewal timer, not expiry math

While the server is listening, a 24-hour timer re-fetches from LocalAPI. If the returned PEM bytes differ from what we're currently serving, build a fresh `NIOSSLContext` from the new bytes and atomically swap the reference the `ChannelInitializer` reads.

Graftty does not track "days until expiry" itself. Tailscale decides when to renew (the industry convention is ~30 days before expiry for 90-day certs); we just periodically ask for whatever's current.

### Hot-swap, no listener restart

When the cert rotates, existing WebSocket connections are **not** torn down. They already completed their TLS handshake with the previous context; the context they used is reference-counted by NIO for the life of the connection, and our swap only affects *new* connections. This matters because an active PTY-streaming WebSocket interrupted mid-cert-rotation would look like a spurious bug.

This also avoids a listener restart, which would rebind the socket and risk a `TIME_WAIT` race with incoming reconnections.

## Error taxonomy

Three new `WebServerStatus` cases, each with a clear human-readable explanation and a deep link to the specific Tailscale admin page the user needs:

| Status | Trigger | Settings-pane copy | Admin-console link |
|---|---|---|---|
| `.magicDNSDisabled` | LocalAPI `/status` returns empty `Self.DNSName` | "MagicDNS must be enabled on your tailnet for Graftty to serve HTTPS." | `https://login.tailscale.com/admin/dns` |
| `.httpsCertsNotEnabled` | LocalAPI cert call returns Tailscale's "HTTPS disabled for this tailnet" error | "HTTPS certificates must be enabled on your tailnet for Graftty to serve HTTPS." | `https://login.tailscale.com/admin/dns` (the HTTPS Certificates section) |
| `.certFetchFailed(String)` | Any other cert-fetch failure (network, Let's Encrypt rate limit, LocalAPI IPC error) | "Could not fetch certificate: `<underlying message>`. Graftty will retry automatically." | _(none)_ |

Existing `.tailscaleUnavailable` (`WEB-1.3`), `.portUnavailable` (`WEB-1.11`), and `.listening(...)` remain. `.listening` now composes an HTTPS URL with the hostname (see below).

Detecting `.httpsCertsNotEnabled` distinctly from `.certFetchFailed` is load-bearing for UX: the difference between a mystery error and "click here to flip a toggle in your admin console" is the difference between the feature shipping and the feature bouncing on field reports. The exact error shape Tailscale returns should be confirmed by manual `curl` against LocalAPI on a tailnet-with-it-off before coding.

## Settings pane UX

The Settings pane grows a sharper distinction between "what do users share" and "what is the server actually doing":

| Row | Content | Purpose |
|---|---|---|
| **Base URL** | `https://macbook.tail-abc12.ts.net:8799/` as a SwiftUI `Link` + copy button (`WEB-1.12` behavior preserved) | The URL the user shares / copies. Hostname-based, cert-valid. |
| **Listening on** | `[fd7a:115c::5]:8799, 100.64.0.5:8799` | Diagnostic: which bind addresses are actually up. IP literals, bracketed IPv6 per `WEB-1.10`. No `127.0.0.1`. |

Without this split, a future reader looking at `WEB-1.10` would see the IP-list as *the* URL spec and risk recomposing copy-links from IPs. Making the split explicit in SPECS preserves the invariant "copy URLs are hostname-based; diagnostic display is IP-based" against future edits.

### Error-state rendering

Each of the three new error statuses renders:

- A short human-readable explanation (see table above)
- A `Link` to the relevant Tailscale admin page (for the two setup-problem statuses; `.certFetchFailed` has no admin action, just retry)
- No Base URL row, no Listening-on row (the server is not bound)

### Startup

If Web Access is persisted-on from a previous session, the full flow runs asynchronously on app launch (does not block the UI): Tailscale availability check → MagicDNS name discovery → cert fetch → bind. The Settings pane shows a `.starting` / indeterminate state until one of the terminal statuses above lands.

## URL composition

`WebURLComposer` today exposes two entry points:

- `baseURL(host:port:)` → `http://<bracketed-host>:<port>/`
- `url(session:host:port:)` → `http://<bracketed-host>:<port>/session/<percent-encoded-name>`

After this change, both take a **hostname** rather than an IP-literal and produce `https://<fqdn>:<port>/…`. The IPv6-bracketing code path is not exercised for these composers (FQDNs never need bracketing) but the bracketing helper stays in `WebURLComposer` for the diagnostic "Listening on …" formatter (`WEB-1.10`), which still prints IPs.

Every caller that copies or opens a URL — Settings "Base URL" row, sidebar "Copy web URL" action — goes through `WebURLComposer`, so the scheme/hostname switch is one-edit-reaches-everywhere.

Percent-encoding of session names (`WEB-1.9`) is unchanged.

## SPECS.md edits

Same commit as code, per `CLAUDE.md`.

### Revisions

- **WEB-1.1** — remove `127.0.0.1` from the bind list. Bind is now "each Tailscale IPv4/IPv6 address reported by LocalAPI". Scheme is HTTPS.
- **WEB-1.8** — scope narrows. IPv6 bracketing applies only to the diagnostic bind-list (`WEB-1.10`), not to copyable URLs, because copyable URLs no longer contain IP literals.
- **WEB-1.10** — drop `127.0.0.1` from the example. Behavior otherwise unchanged.
- **WEB-1.12** — "Base URL" explicitly means the hostname-based HTTPS URL. Add a note that a separate "Listening on" diagnostic row exists and must not be conflated with the Base URL.
- **WEB-2.5** — **delete.** No loopback bind → no loopback-bypass carve-out needed. Note the supersession reason inline so a future archaeologist understands the deletion wasn't accidental: local connections now arrive as a Tailscale peer and pass `WEB-2.2`.
- **WEB-6.1** — **invert.** Old: "Phase 2 shall not implement TLS at the application level; the application shall rely on Tailscale transport encryption." New: "The web server shall bind HTTPS only, using a cert+key pair fetched from Tailscale LocalAPI for the machine's MagicDNS name. It shall not bind any HTTP listener." The "Phase 2 out-of-scope" framing for this specific clause goes away; TLS is now in scope.

### New requirements

- **WEB-8.1** — MagicDNS name discovery: the application shall read `Self.DNSName` from Tailscale LocalAPI `/status`, strip the trailing dot, and use the resulting FQDN as the TLS SNI name and as the hostname in every composed Base URL / session URL. If `Self.DNSName` is absent or empty, the application shall enter `.magicDNSDisabled` status and not bind.
- **WEB-8.2** — cert fetch: the application shall fetch the TLS cert+key pair for the discovered FQDN from Tailscale LocalAPI `/localapi/v0/cert/<fqdn>?type=pair`. If the response classifies as "HTTPS disabled for this tailnet", the application shall enter `.httpsCertsNotEnabled` status and not bind. Any other fetch failure shall enter `.certFetchFailed(<message>)` status and schedule a retry.
- **WEB-8.3** — cert renewal: while the server is listening, the application shall re-fetch the cert every 24 hours. If the returned PEM bytes differ from the currently-serving material, it shall construct a new `NIOSSLContext` and atomically swap the reference read by the per-channel `ChannelInitializer`. It shall not close the listening socket and shall not disturb in-flight connections.
- **WEB-8.4** — error-status rendering: for `.magicDNSDisabled` and `.httpsCertsNotEnabled`, the Settings pane shall render a human-readable explanation plus a SwiftUI `Link` to the relevant Tailscale admin page (`https://login.tailscale.com/admin/dns`). For `.certFetchFailed`, it shall render the underlying message plus a note that Graftty will retry automatically.

## Testing strategy

- **Unit tests** for the status classifier: given sample LocalAPI error responses (feature-off error, transient network error, malformed response), confirm the classifier returns `.httpsCertsNotEnabled` vs `.certFetchFailed` as designed. The classifier should be resilient to Tailscale rewording the error message, so lean on HTTP status codes + structured fields if available and use string-match only as a fallback (same pattern as `WebServer.isAddressInUse(_:)` per `WEB-1.11`).
- **Unit tests** for `WebURLComposer`: hostname-based URLs render without brackets even when the FQDN contains characters that look IPv6-ish; session names containing reserved URL characters still percent-encode correctly (`WEB-1.9` regression guard).
- **Integration test** for cert rotation: stand up a `WebServer` with an initial context, simulate the 24h timer firing with different PEM bytes, confirm a new `NIOSSLContext` is installed and old-context connections are not disturbed. This likely uses an in-process LocalAPI mock returning controlled bytes.
- **Manual smoke test** — documented in PR: enable Web Access on a tailnet with HTTPS certs on, confirm Safari and Chrome both show a valid-cert lock icon for the copied URL; repeat on a tailnet with HTTPS certs off, confirm the Settings pane shows the `.httpsCertsNotEnabled` row with a working admin-console link.

## Out of scope for this work

- Secure-context API consumption (clipboard, service workers, PWA install manifest). These become *available* once HTTPS lands but are separate features.
- A "Require HTTPS" user toggle. The design is HTTPS-only by construction; there is no mode where Graftty serves HTTP.
- Migration messaging to users with old `http://` bookmarks. The old URLs simply fail to connect; this is considered acceptable given Web Access is off by default and the feature population is small.
