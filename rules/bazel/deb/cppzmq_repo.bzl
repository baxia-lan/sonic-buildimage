"""Repository rule for cppzmq headers.

Downloads zmq.hpp and zmq_addon.hpp at fetch time (not build time).
This replaces the `curl` calls that were inside genrule build actions,
which violated hermeticity.

Usage in MODULE.bazel:
    cppzmq = use_repo_rule("//rules/bazel/deb:cppzmq_repo.bzl", "cppzmq_headers")
    cppzmq(name = "cppzmq")
"""

def _cppzmq_headers_impl(rctx):
    rctx.download(
        url = rctx.attr.zmq_hpp_url,
        output = "zmq.hpp",
        sha256 = rctx.attr.zmq_hpp_sha256,
    )
    rctx.download(
        url = rctx.attr.zmq_addon_hpp_url,
        output = "zmq_addon.hpp",
        sha256 = rctx.attr.zmq_addon_hpp_sha256,
    )
    rctx.file("BUILD.bazel", """\
package(default_visibility = ["//visibility:public"])

filegroup(
    name = "headers",
    srcs = ["zmq.hpp", "zmq_addon.hpp"],
)
""")

cppzmq_headers = repository_rule(
    implementation = _cppzmq_headers_impl,
    attrs = {
        "zmq_hpp_url": attr.string(
            default = "https://raw.githubusercontent.com/zeromq/cppzmq/v4.10.0/zmq.hpp",
        ),
        "zmq_hpp_sha256": attr.string(
            default = "1f8b641161dcf12641ae4951c2c49552de425be88d66c988ec5e85046f1320f6",
        ),
        "zmq_addon_hpp_url": attr.string(
            default = "https://raw.githubusercontent.com/zeromq/cppzmq/v4.10.0/zmq_addon.hpp",
        ),
        "zmq_addon_hpp_sha256": attr.string(
            default = "1dc1d551d7eca43ce31031b2104c0acb204e97fe0921e75741be5a8448ce8814",
        ),
    },
    doc = "Downloads cppzmq header-only library at fetch time with sha256 pinning.",
)
