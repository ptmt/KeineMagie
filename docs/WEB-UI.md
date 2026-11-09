# Minimal web UI

The web surface is a translator only: header/logo/account, language selectors and swap, input/output, translate/cancel/copy/clear, then personal history. The former hero strings, planned-feature navigation, enrichment cards, empty-result slogan and footer tagline are removed from markup, not merely hidden. The API response schema is unchanged; enrichment arrays remain validated but are not rendered. Native iOS is unchanged.

Authentication prerequisites/errors appear inline beside the translate action. Guests see an `Anmelden` dialog with an accessible close control, Apple sign-in and optional secondary iPhone pairing. ChatGPT is semantically hidden and its account text/code cleared until a confirmed authenticated user exists. The authenticated account retains the personal provider bootstrap, retry and logout flow. Closing the dialog or losing/changing identity invalidates pending provider UI results and clears one-time codes.

## Apple artwork provenance

`web/apple-sign-in-de.png` is the unmodified PNG returned by Apple's official [button-image generator](https://developer.apple.com/documentation/signinwithapple/incorporating-sign-in-with-apple-into-other-platforms):

```
https://appleid.cdn-apple.com/appleid/button?height=48&width=320&color=black&border=false&type=sign-in&border_radius=8&scale=3&locale=de_DE
```

Apple renders the logo and German label together; there is no hand-drawn logo, Unicode Apple glyph, manually localized visual label, remote script or CSP exception. The 960×144 image renders at 320×48 CSS pixels on desktop, with a minimum 44px touch target and surrounding clearspace on small screens. In dark mode it sits on a light surface for contrast. The same-origin native HTML button keeps the existing CSRF-bound POST and validated Apple navigation flow.

Official guidance: [Sign in with Apple HIG](https://developer.apple.com/design/human-interface-guidelines/sign-in-with-apple), [Apple button resource API](https://developer.apple.com/documentation/signinwithapple/incorporating-sign-in-with-apple-into-other-platforms).

## Verification

- `node --test web/tests/*.test.mjs`
- `cd server && go test -race ./... && go vet ./... && go build .`
- `web/tests/browser_smoke.py`: execute via browser helpers against a loopback static server at port 8766. Its explicitly synthetic responses exercise translation/history, busy/cancel, copy/clear/swap, errors, expiry, account visibility, provider bootstrap cleanup and logout readback, plus viewport widths 320/390/768/1440.
- Screenshots use synthetic availability configuration only, not successful Apple/ChatGPT consent. Live consent/provider requests are not claimed verified. No secrets or backend authentication policies changed.
