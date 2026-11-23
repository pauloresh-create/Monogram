load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# MARK: Monogram
swift_library(
    name = "MonoSettingsUI",
    module_name = "MonoSettingsUI",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//Monogram/MonoSettings:MonoSettings",
        "//Swiftgram/SGSimpleSettings:SGSimpleSettings",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/Display:Display",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/ItemListUI:ItemListUI",
        "//submodules/AccountContext:AccountContext",
        "//submodules/PresentationDataUtils:PresentationDataUtils",
    ],
    visibility = [
        "//visibility:public",
    ],
)
