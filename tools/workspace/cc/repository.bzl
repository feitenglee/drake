# -*- mode: python -*-
# vi: set ft=python :

"""
Identifies the C/C++ compiler by examining the presence or values of various
predefined C preprocessor macros. Identifies any compiler capable of compiling
C++ code that is supported by CMake 3.12.0.

Note that there are constraint_values @bazel_tools//tools/cpp:clang and
@bazel_tools//tools/cpp:gcc that could potentially distinguish between the
Clang and GCC compilers as an alternative to this approach, but as of Bazel
0.14.1, they appear not to be compatible with the autogenerated toolchain.

Example:
        load("@drake//tools/workspace/cc:repository.bzl", "cc_repository")
        cc_repository(name = "cc")

    foo.bzl:
        load("@cc//:compiler.bzl", "COMPILER_ID")

        if "COMPILER_ID" == "AppleClang":
            # Do something...

        if "COMPILER_ID" == "Clang":
            # Do something...

        if "COMPILER_ID" == "GNU":
            # Do something...

Argument:
    name: A unique name for this rule.
"""

load("@bazel_tools//tools/cpp:unix_cc_configure.bzl", "find_cc")

def _impl(repository_ctx):
    file_content = """# -*- python -*-

# DO NOT EDIT: generated by cc_repository()

# This file exists to make our directory into a Bazel package, so that our
# neighboring *.bzl file can be loaded elsewhere.
"""

    repository_ctx.file(
        "BUILD.bazel",
        content = file_content,
        executable = False,
    )

    # https://github.com/bazelbuild/bazel/blob/0.14.1/tools/cpp/cc_configure.bzl
    if repository_ctx.os.environ.get("BAZEL_DO_NOT_DETECT_CPP_TOOLCHAIN", "0") == "1":  # noqa
        fail("Could NOT identify C/C++ compiler because CROSSTOOL is empty.")

    if repository_ctx.os.name == "mac os x" and repository_ctx.os.environ.get("BAZEL_USE_CPP_ONLY_TOOLCHAIN", "0") != "1":  # noqa
        # https://github.com/bazelbuild/bazel/blob/0.14.1/tools/cpp/osx_cc_configure.bzl
        cc = repository_ctx.path(Label("@local_config_cc//:cc_wrapper.sh"))

    else:
        # https://github.com/bazelbuild/bazel/blob/0.14.1/tools/cpp/unix_cc_configure.bzl
        cc = find_cc(repository_ctx, overriden_tools = {})

    executable = repository_ctx.path("identify_compiler")
    result = repository_ctx.execute([
        cc,
        repository_ctx.path(
            Label("@drake//tools/workspace/cc:identify_compiler.cc"),
        ),
        "-o",
        executable,
    ])
    if result.return_code != 0:
        fail(
            "Could NOT identify C/C++ compiler because compilation failed.",
            result.stderr,
        )

    result = repository_ctx.execute([executable])
    if result.return_code != 0:
        fail("Could NOT identify C/C++ compiler.", result.stderr)

    output = result.stdout.strip().split(" ")
    if len(output) != 3:
        fail("Could NOT identify C/C++ compiler.")

    compiler_id = output[0]

    if repository_ctx.os.name == "mac os x":
        supported_compilers = ["AppleClang"]
    else:
        supported_compilers = ["Clang", "GNU"]

    # We do not fail outright here since even though we do not officially
    # support them, Drake may happily compile with new enough versions of
    # compilers that are compatible with GNU flags such as -std=c++14.

    if compiler_id not in supported_compilers:
        print("WARNING: {} is NOT a supported C/C++ compiler.".format(
            compiler_id,
        ))
        print("WARNING: Compilation of the drake WORKSPACE may fail.")

    compiler_version_major = int(output[1])
    compiler_version_minor = int(output[2])

    # The minimum compiler versions should match those listed in both the root
    # CMakeLists.txt and doc/developers.rst. We know from experience that
    # compilation of Drake will certainly fail with versions lower than these,
    # even if they happen to support the necessary compiler flags.

    if compiler_id == "AppleClang":
        if compiler_version_major < 9:
            fail("AppleClang compiler version {}.{} is less than 9.0.".format(
                compiler_version_major,
                compiler_version_minor,
            ))

    elif compiler_id == "Clang":
        if compiler_version_major < 4:
            fail("Clang compiler version {}.{} is less than 4.0.".format(
                compiler_version_major,
                compiler_version_minor,
            ))

    elif compiler_id == "GNU":
        if compiler_version_major < 5 or (compiler_version_major == 5 and
                                          compiler_version_minor < 4):
            fail("GNU compiler version {}.{} is less than 5.4.".format(
                compiler_version_major,
                compiler_version_minor,
            ))

    file_content = """# -*- python -*-

# DO NOT EDIT: generated by cc_repository()

COMPILER_ID = "{}"

""".format(compiler_id)

    repository_ctx.file(
        "compiler.bzl",
        content = file_content,
        executable = False,
    )

cc_repository = repository_rule(
    environ = [
        "BAZEL_DO_NOT_DETECT_CPP_TOOLCHAIN",
        "BAZEL_USE_CPP_ONLY_TOOLCHAIN",
        "CC",
    ],
    implementation = _impl,
)
