// swift-tools-version:5.10
import PackageDescription

// Hello world: a host, a client built over it, and tests that call through the
// binary. It is built twice, against two different things.
//
// Here the dependency is the package in the parent directory, which is what the
// nightly Apple job and the release lane compile BEFORE anything is published.
// `StubHost` below `Sources/` is the only Swift type in this repository that
// conforms to the five host protocols (`AgentHost`, `AgentSessionHost`,
// `AgentHistoryHost`, `AgentPocketHost`, `AgentEscalationHost`), so this build
// is where a member added to any of them first meets a conforming type.
//
// When this example is copied into the public repository the two lines that
// name the dependency -- the `.package(...)` below and the `package:` label on
// each product -- are rewritten to resolve the PUBLISHED package by URL. That
// copy is the one check that the manifest, the release tag, the asset URL and
// the checksum agree with each other from outside, and its tests run on an iOS
// simulator so they LINK the binary target and call through it.
let package = Package(
    name: "HelloPaygent",
    platforms: [ .iOS(.v16) ],
    products: [ .library(name: "HelloPaygent", targets: ["HelloPaygent"]) ],
    dependencies: [ .package(url: "https://github.com/paygent-net/paygent-swift.git", .upToNextMinor(from: "0.3.0")) ],
    targets: [
        .target(
            name: "HelloPaygent",
            // Each product names the package that vends it. A bare string
            // would not do: it may name a target of this package, or a
            // product of a dependency whose PACKAGE name it matches, and
            // neither is true of "PaygentSdk" -- the package in the parent
            // directory is called "PaygentMobileCore".
            //
            // `package:` takes the dependency's identity, which for a path
            // dependency is the directory's basename, so it is "ios" here and
            // "paygent-swift" in the published copy. That is the one word
            // build-public-package.sh rewrites besides the dependency line.
            dependencies: [
                .product(name: "PaygentSdk", package: "paygent-swift"),
                .product(name: "PaygentMobileCore", package: "paygent-swift"),
            ]
        ),
        .testTarget(
            name: "HelloPaygentTests",
            dependencies: [
                "HelloPaygent",
                // Named even though `HelloPaygent` already depends on it: a
                // target's dependencies are what it may import, and the tests
                // import PaygentSdk directly.
                .product(name: "PaygentSdk", package: "paygent-swift"),
            ]
        ),
    ]
)
