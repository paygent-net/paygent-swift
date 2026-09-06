// swift-tools-version:5.10
import PackageDescription

// The worked example: the documentation article's code as something a compiler
// reads, so a renamed record or a changed enum case is a build error rather
// than a stale paragraph.
//
// The dependency below, and the `package:` label on each product, are
// rewritten when this example is copied into the public repository -- there it
// resolves the published package by URL, here it is the package in the parent
// directory, which is what the nightly Apple job builds before anything is
// published.
//
// A library target rather than an executable: the xcframework carries iOS
// slices only, and SwiftPM cannot build an iOS executable.
let package = Package(
    name: "PayAnInvoice",
    platforms: [ .iOS(.v16) ],
    products: [ .library(name: "PayAnInvoice", targets: ["PayAnInvoice"]) ],
    dependencies: [ .package(url: "https://github.com/paygent-net/paygent-swift.git", .upToNextMinor(from: "0.2.0")) ],
    targets: [
        .target(
            name: "PayAnInvoice",
            // Each product names the package that vends it. A bare string
            // may name a target of this package, or a product of a dependency
            // whose PACKAGE name it matches; "PaygentSdk" is neither, because
            // the package in the parent directory is called
            // "PaygentMobileCore".
            //
            // `package:` takes the dependency's identity -- for a path
            // dependency, its directory's basename -- so it reads "ios" here
            // and "paygent-swift" in the published copy, which is why
            // build-public-package.sh rewrites it alongside the line above.
            dependencies: [
                .product(name: "PaygentSdk", package: "paygent-swift"),
                .product(name: "PaygentMobileCore", package: "paygent-swift"),
            ]
        ),
    ]
)
