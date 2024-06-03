TOOL_NAME = "swc"
TOOLCHAIN_TYPE = "@tools_swc//swc:toolchain_type"
TOOLCHAIN_LOCATION = "@tools_swc//swc:defs.bzl"

VERSIONS = {
    "darwin-arm64": struct(
        versions = {
            "v1.5.7": "https://github.com/swc-project/swc/releases/download/v1.5.7/swc-darwin-arm64"
        },
        compatible_with = [
            "@platforms//os:macos",
            "@platforms//cpu:aarch64",
        ],
    ),
    "darwin-x64": struct(
        versions = {
            "v1.5.7": "https://github.com/swc-project/swc/releases/download/v1.5.7/swc-darwin-x64"
        },
        compatible_with = [
            "@platforms//os:macos",
            "@platforms//cpu:x86_64",
        ],
    ),
    "linux-arm64": struct(
        versions = {
            "v1.5.7": "https://github.com/swc-project/swc/releases/download/v1.5.7/swc-linux-arm64-gnu"
        },
        compatible_with = [
            "@platforms//os:linux",
            "@platforms//cpu:aarch64",
        ],
    ),
    "linux-x64": struct(
        versions = {
            "v1.5.7": "https://github.com/swc-project/swc/releases/download/v1.5.7/swc-linux-x64-gnu"
        },
        compatible_with = [
            "@platforms//os:linux",
            "@platforms//cpu:x86_64",
        ],
    ),
    "win32-arm64": struct(
        versions = {
            "v1.5.7": "https://github.com/swc-project/swc/releases/download/v1.5.7/swc-win32-arm64-msvc.exe"
        },
        compatible_with = [
            "@platforms//os:windows",
            "@platforms//cpu:aarch64",
        ],
    ),
    "win32-ia32": struct(
        versions = {
            "v1.5.7": "https://github.com/swc-project/swc/releases/download/v1.5.7/swc-win32-ia32-msvc.exe"
        },
        compatible_with = [
            "@platforms//os:windows",
            "@platforms//cpu:i386",
        ],
    ),
    "win32-x64": struct(
        versions = {
            "v1.5.7": "https://github.com/swc-project/swc/releases/download/v1.5.7/swc-win32-x64-msvc.exe"
        },
        compatible_with = [
            "@platforms//os:windows",
            "@platforms//cpu:x86_64",
        ],
    ),
}

# Toolchain

Info = provider(
    fields = {
        "binary": "Path to the toolchain binary.",
        "runfiles": "Runfiles required by the tool.",
    },
)

def _toolchain(ctx):
    runfiles = ctx.attr.tool.files.to_list()
    return [
        DefaultInfo(
            files = depset(runfiles),
            runfiles = ctx.runfiles(files = runfiles),
        ),
        platform_common.ToolchainInfo(
            info = Info(
                binary = "external/" + runfiles[0].short_path.removeprefix("../"),
                runfiles = runfiles,
            ),
        ),
    ]

toolchain = rule(
    implementation = _toolchain,
    attrs = {
        "tool": attr.label(
            mandatory = False,
            allow_single_file = True,
        ),
    },
)

# Single toolchain repository rule

toolchain_snippet = """
toolchain(
    name = "{platform}_toolchain",
    exec_compatible_with = {compatible_with},
    toolchain = "@{name}_{platform}//:toolchain",
    toolchain_type = "{toolchain_type}",
)
"""

def _toolchains_repo(repository_ctx):
    build_content = ""
    for [platform, meta] in VERSIONS.items():
        build_content += toolchain_snippet.format(
            platform = platform,
            name = repository_ctx.attr.repo_name,
            compatible_with = meta.compatible_with,
            toolchain_type = TOOLCHAIN_TYPE,
        )

    repository_ctx.file("BUILD.bazel", build_content)

toolchains_repo = repository_rule(
    _toolchains_repo,
    attrs = {
        "repo_name": attr.string(),
    }
)

# All toolchains repository rule

build_snippet = """
load("{}", "toolchain")
toolchain(
    name = "toolchain",
    tool = "{}",
)
"""

def _repositories(repository_ctx):
    platform = VERSIONS[repository_ctx.attr.platform]
    version = repository_ctx.attr.version
    if version not in platform.versions.keys():
        fail("{} version {} not supported. available versions: {}".format(TOOL_NAME, version, platform.versions.keys()))

    url_parts = platform.versions[version].split("#")
    url = url_parts[0]
    filename = url.split("/").pop()
    repository_ctx.file("BUILD.bazel", build_snippet.format(TOOLCHAIN_LOCATION, filename))
    repository_ctx.download(
        output = filename,
        url = url,
        integrity = url_parts[1] if len(url_parts) > 1 else "",
        executable = True,
    )


repositories = repository_rule(
    _repositories,
    attrs = {
        "version": attr.string(),
        "platform": attr.string(mandatory = True, values = VERSIONS.keys()),
    },
)

def register_toolchains(name, version = None, register = True, **kwargs):
    for platform in VERSIONS.keys():
        repositories(
            name = name + "_" + platform,
            platform = platform,
            version = version,
            **kwargs
        )
        if register:
            native.register_toolchains("@%s_toolchains//:%s_toolchain" % (name, platform))
    toolchains_repo(
        name = name + "_toolchains",
        repo_name = name,
    )


# Bzlmod extension

def _extension(module_ctx):
    for mod in module_ctx.modules:
        for toolchain in mod.tags.toolchain:
            register_toolchains(
                name = toolchain.name,
                version = toolchain.version,
                register = False,
            )

swc = module_extension(
    implementation = _extension,
    tag_classes = {"toolchain": tag_class(attrs = {
        "name": attr.string(),
        "version": attr.string(),
    })},
)
