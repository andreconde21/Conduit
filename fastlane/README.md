# fastlane

Store lanes for Conductore, called by `.github/workflows/release.yml` and
`.github/workflows/promote.yml`. Run `bundle exec fastlane lanes` for the
list, and see `docs/release-pipeline.md` for the setup.

Why fastlane rather than only marketplace actions: uploading is easy either
way, but promotion is not. `supply` promotes a version code between Play
tracks and changes staged rollouts; `pilot` hands a TestFlight build to an
external group; `deliver` submits a build for App Store review. One pinned
tool (Gemfile.lock) covers upload and promotion on both stores, and the
lanes run the same way on a laptop.

Flutter still does the building: the workflows run `flutter build
appbundle` / `flutter build ios --config-only`, and the `ios beta` lane
only archives, signs and uploads the prepared Xcode workspace.

`metadata/android` is upstream Conduit's F-Droid listing, kept as is.
`metadata/ios` and `screenshots/ios` are placeholders: listings are managed
in the consoles and no lane uploads metadata.
