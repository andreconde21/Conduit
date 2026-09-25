import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Adds the bundled fonts and the Omarchy themes to the app's licence page.
void registerThemeLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      const ['JetBrains Mono Nerd Font'],
      await rootBundle.loadString(
        'assets/fonts/LICENSE-JetBrainsMonoNerdFont.txt',
      ),
    );
    yield LicenseEntryWithLineBreaks(
      const ['JetBrains Mono Nerd Font (Nerd Fonts icon sets)'],
      await rootBundle.loadString(
        'assets/fonts/README-JetBrainsMonoNerdFont.md',
      ),
    );
    yield LicenseEntryWithLineBreaks(const [
      'Atkynson Mono Nerd Font',
    ], await rootBundle.loadString('assets/fonts/LICENSE-AtkynsonMono.txt'));
    yield const LicenseEntryWithLineBreaks([
      'Omarchy themes',
    ], omarchyLicenseText);
  });
}

/// Omarchy's licence (https://github.com/basecamp/omarchy/blob/master/LICENSE).
/// The app's themes are Omarchy's colors.toml palettes.
const String omarchyLicenseText = '''
The colour themes are taken from Omarchy (https://github.com/basecamp/omarchy).

Copyright (c) David Heinemeier Hansson

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.''';
