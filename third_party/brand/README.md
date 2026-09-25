# Multiplexer logos

The app draws these logos with `MultiplexerIcon`
(`lib/core/presentation/multiplexer_icon.dart`), which embeds the path data
of the files below unchanged. The files are kept here as the source of truth.

| Logo | Source | Licence |
| --- | --- | --- |
| tmux logomark | https://github.com/tmux/tmux/blob/master/logo/tmux-logomark.svg | ISC, Copyright (c) 2015 Jason Long (`tmux/LICENSE`, the `logo/LICENSE` of the tmux repo) |
| Herdr logo | https://github.com/herdrdev/herdr/blob/master/assets/logo.svg (also served as https://herdr.dev/assets/logo.png) | Apache-2.0, the licence of the Herdr repository (`herdr/LICENSE`) |

Both are used only to identify the tool a session runs in. Apache-2.0
section 6 grants no trademark rights, so the Herdr logo is shown as is and
never as Conductore's own mark. Their notices are registered with Flutter's
licence page by `registerMultiplexerLogoLicenses()`.
