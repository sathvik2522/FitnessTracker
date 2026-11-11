# Optional project tools

Ordinary builds use the checked-in Xcode project and need no Ruby dependencies.

`validate_project.rb` checks all three targets, source membership, minimum deployment, configuration references, assets, Charts/HealthKit linkage and shared Test/Run/Profile scheme membership. It does not compile or validate phone behavior.

To install the pinned development tool without a global gem installation:

```sh
cd Tools
bundle config set --local path ../.bundle/vendor
bundle install
bundle exec ruby validate_project.rb
```

Requires an available Ruby/Bundler installation. `.bundle` configuration and installed gems are local and ignored. These commands download development tooling only; the app itself has no third-party runtime dependency.

`generate_project.rb` reconstructs a missing project from current folders using xcodeproj 1.27.0. It deliberately refuses to overwrite an existing project. Use it only in a separate recovery checkout, then validate and build its output. Add normal source files through Xcode instead of regenerating the working project.
