# Third-Party Licenses

Spectra uses the following third-party components.

---

## Ghostty (libghostty)

Spectra embeds libghostty as its terminal emulation core, and bundles
Ghostty's terminfo database, shell integration scripts, and color themes.

- **Project**: [Ghostty](https://ghostty.org)
- **Repository**: https://github.com/ghostty-org/ghostty
- **License**: MIT
- **Copyright**: (c) 2024 Mitchell Hashimoto, Ghostty contributors

### Bundled components

| Component | Path in Spectra | Description |
|-----------|----------------|-------------|
| libghostty | `lib/libghostty.a` | Terminal emulation static library |
| terminfo | `Sources/Spectra/Resources/terminfo/` | xterm-ghostty terminal capability database |
| Shell integration | `Sources/Spectra/Resources/ghostty/shell-integration/` | Shell integration scripts (bash, zsh, fish, elvish, nushell) |
| Themes | `Sources/Spectra/Resources/ghostty/themes/` | Color theme definitions |

### MIT License

```
MIT License

Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
