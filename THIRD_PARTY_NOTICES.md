# Third-Party Notices

HostDeck is licensed under GPL-3.0-only. The following bundled assets retain
their own copyright notices and license terms.

## MacTahoe Icon Theme

- Project: https://github.com/vinceliuice/MacTahoe-icon-theme
- Author and customizer: Vince Liuice
- Upstream source: WhiteSur Icon Theme by Vince Liuice
- License: GNU General Public License version 3 (GPL-3.0)
- Source snapshot commit: `94c7e615a94e352366c3d5298efda16e86bc6da7`

HostDeck imports a selected set of application and file-type SVG icons directly
from the upstream source tracked as a Git submodule at
`host-deck-ui/src/assets/mac-tahoe/`. The submodule is pinned to the commit above
and the selected SVG contents have not been intentionally modified. See its
`AUTHORS`, `COPYING`, and `README.md` files for the applicable notices and GPL
version 3 terms.

## Maple Mono

- Project: https://github.com/subframe7536/maple-font
- Copyright: 2022 The Maple Mono Project Authors
- License: SIL Open Font License 1.1 (OFL-1.1)
- Bundled file: `host-deck-ui/src/assets/MapleMono-Regular.ttf`

The font remains licensed under OFL-1.1 and is not relicensed under the
HostDeck license. See `host-deck-ui/src/assets/MapleMono-OFL.txt` for the full
license text.

## Corresponding Source

The preferred form for modifying HostDeck and the bundled MacTahoe SVG files is
available by cloning the repository and initializing its submodules:

https://github.com/foliageSea/HostDeck

```bash
git clone --recurse-submodules https://github.com/foliageSea/HostDeck.git
```

For a released binary, check out the Git tag matching the displayed application
version and initialize its submodules. GitHub-generated source archives do not
contain submodule contents and are not sufficient on their own.
