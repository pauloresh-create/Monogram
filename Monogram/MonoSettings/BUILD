load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# MARK: Monogram
swift_library(
    name = "MonoSettings",
    module_name = "MonoSettings",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//Swiftgram/SGAppGroupIdentifier:SGAppGroupIdentifier",
    ],
    visibility = [
        "//visibility:public",
    ],
)
