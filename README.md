# Tangent development environments

Both developers work on the same Swift source files. Generate a local Xcode
project for your toolchain; package versions and caches stay separate.
Run these commands from the repository root after pulling changes.

```sh
python3 scripts/environment.py auto --resolve
```

Open the project path printed by the command, select the **Tangent** scheme,
and build. Xcode downloads the packages; there is no separate MLX installation.
The first build compiles MLX's native code and can take several minutes.

| Profile | Toolchain | mlx-swift-lm | mlx-swift | swift-transformers | swift-huggingface |
| --- | --- | --- | --- | --- | --- |
| `xcode16` | Xcode 16.2 / Swift 6.0.3 | 2.29.2 | 0.29.1 | 1.1.0 | Uses Transformers' `Hub` instead |
| `modern` | Swift 6.1 or newer, subject to pinned dependencies | 3.31.3 | 0.31.6 | 1.3.0 | 0.9.0 |

`auto` chooses `xcode16` for Swift 6.0 and `modern` for Swift 6.1 or newer.
The newer MLX and Hugging Face packages declare Swift 6.1 as their minimum
in their [MLX manifest](https://github.com/ml-explore/mlx-swift-lm/blob/3.31.3/Package.swift)
and [Hugging Face manifest](https://github.com/huggingface/swift-huggingface/blob/0.9.0/Package.swift).
Changing the app's Swift language mode does not change its compiler version.

To select a profile explicitly:

```sh
python3 scripts/environment.py xcode16 --resolve
python3 scripts/environment.py modern --resolve
```

With multiple Xcode installations, select one for the command without changing
the machine's global settings:

```sh
DEVELOPER_DIR=/Applications/Xcode-new.app/Contents/Developer \
  python3 scripts/environment.py modern --resolve
```

Use the corresponding Xcode app to open the generated project. The script
rejects `modern` when the selected compiler is older than Swift 6.1.
This is an Apple Silicon Mac/iOS project; it does not build with Windows Xcode.
The iOS deployment target remains 18.2.

For a physical device, provide your own Apple development team:

```sh
python3 scripts/environment.py auto --team ABCDE12345 --resolve
```

You can also set `TANGENT_DEVELOPMENT_TEAM` in your shell. Team overrides affect
only the generated project. Select an appropriate signing identity and a
unique bundle ID in that project if your provisioning setup requires them.

The generated projects are `Tangent/Tangent-xcode16.xcodeproj` and
`Tangent/Tangent-modern.xcodeproj`. Both are ignored by Git. Regenerate after
pulling, and make shared target/build-setting changes in
`Tangent/Tangent.xcodeproj`, since regeneration overwrites local project settings.
Your friend can still open that original project directly with their existing setup.

The modern profile copies the original checked-in `Package.resolved`.
The older profile copies `BuildProfiles/xcode16.resolved`, including transitive
dependencies. `--resolve` requires those pinned versions; do not casually use
Xcode's “Update to Latest Package Versions”. Intentional dependency updates
need a build check and an updated profile lockfile.

On-device generation remains enabled in both profiles. The older profile uses
the older Hub download and MLX loading APIs, with percentage progress because
that Hub API reports file-weighted progress rather than byte counts. Its model
cache is separate: switching profiles requires downloading weights again in
Settings. Diary data and model selection keep the same storage. Completed
legacy downloads load from their local directories during generation.

To check the project generator:

```sh
python3 -m unittest discover -s scripts -p 'test_*.py'
```

To compile for iOS without device signing:

```sh
xcodebuild -project Tangent/Tangent-xcode16.xcodeproj -scheme Tangent \
  -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath .build/DerivedData-xcode16 \
  -clonedSourcePackagesDirPath .build/packages-xcode16 \
  -onlyUsePackageVersionsFromResolvedFile CODE_SIGNING_ALLOWED=NO build
```

Validated locally with Xcode 16.2 / Swift 6.0.3: pinned package resolution,
unsigned iOS Debug build, the existing `TangentTests` suite on an iOS 18.3
simulator, and five generator tests. The modern project and lockfile are
preserved exactly, but its build needs checking on your friend's newer Xcode.
Real model downloading/generation and device signing still need an iPhone check.
