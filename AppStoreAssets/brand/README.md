# IPTV brand artwork

These masters are the source of truth for the app icon and tvOS artwork:

- `iptv-app-icon-master.png`: square iOS/macOS app-icon master.
- `iptv-tvos-master.png`: landscape tvOS app-icon and Top Shelf master.

Regenerate the asset-catalog images from the repository root:

```sh
rtk bash scripts/appstore/generate-brand-assets.sh
```

## Legal-safe visual boundary

The identity is limited to a generic television outline, a playback symbol, and
three abstract channel/signal bars. Do not add footballs, balls, trophies, cups,
stadiums, sports fields, flags, medals, teams, leagues, FIFA, World Cup, Apple,
or other third-party brand imagery.

## Generation prompts

The masters were created with the built-in image generation mode on 2026-07-14.

Square icon prompt:

> Use case: logo-brand. Asset type: Apple app icon master for an IPTV and live
> television player. Create a completely original icon that communicates general
> IPTV, streaming channels, and video playback. The central symbol is an abstract
> television screen made from one clean geometric rounded rectangular outline,
> with a simple play triangle integrated with three subtle channel or signal bars.
> Use a premium minimal flat vector-style brand mark, bold geometric silhouette,
> polished and modern, visually distinctive, and readable at 16 pixels. Center
> the mark on an edge-to-edge square app-icon canvas with generous internal
> padding. Use a deep midnight navy background with electric cyan and soft violet
> accents plus one restrained coral highlight. No text, letters, transparency,
> device mockup, baked outer app-icon mask, watermark, Apple product symbols, or
> third-party branding. No football, soccer, ball of any kind, trophy, cup,
> stadium, sports field, floodlights, confetti, flags, medals, teams, leagues,
> FIFA, World Cup resemblance, or gold trophy palette.

tvOS landscape prompt:

> Using the IPTV app icon as the exact visual identity, create a matching
> landscape tvOS brand artwork. Preserve the same abstract television outline,
> play triangle, three channel/signal bars, deep midnight navy background,
> cyan-to-violet gradient, and small coral accent. Recompose it for a wide
> cinematic landscape canvas with the symbol centered and comfortably inside a
> generous center-safe area so it can be cropped to both 5:3 tvOS app icon and
> very wide Top Shelf formats. Use premium minimal vector-style artwork, clean
> geometric forms, subtle depth and glow, and strong contrast at television
> viewing distance. No text, letters, device mockup, watermark, football, soccer,
> ball, trophy, cup, stadium, sports field, floodlights, confetti, flags, medals,
> teams, leagues, FIFA, World Cup resemblance, Apple symbols, or third-party
> symbols.
