import os
import re
from SCons.Action import Action
from SCons.Builder import Builder
from SCons.Errors import StopError
from SCons.Node.FS import File


def _icons_emitter(target, source, env):
    icons_src = env.GlobRecursive("*.png", env["ICON_SRC_DIR"])
    icons_src += env.GlobRecursive("**/frame_rate", env["ICON_SRC_DIR"])

    target = [
        target[0].File(env.subst("${ICON_FILE_NAME}.c")),
        target[0].File(env.subst("${ICON_FILE_NAME}.h")),
    ]
    return target, icons_src


def _proto_emitter(target, source, env):
    target = []
    for src in source:
        basename = os.path.splitext(src.name)[0]
        target.append(env.File(f"compiled/{basename}.pb.c"))
        target.append(env.File(f"compiled/{basename}.pb.h"))
    return target, source


def _dolphin_emitter(target, source, env):
    res_root_dir = source[0].Dir(env["DOLPHIN_RES_TYPE"])
    source = list()
    source.extend(env.GlobRecursive("*.*", res_root_dir.srcnode()))

    target_base_dir = target[0]
    env.Replace(_DOLPHIN_OUT_DIR=target[0])
    env.Replace(_DOLPHIN_SRC_DIR=res_root_dir)

    if env["DOLPHIN_RES_TYPE"] == "external":
        target = [target_base_dir.File("manifest.txt")]
        ## A detailed list of files to be generated
        # Not used ATM, becasuse it inflates the internal dependency graph too much
        # Preserve original paths, do .png -> .bm conversion
        # target.extend(
        #     map(
        #         lambda node: target_base_dir.File(
        #             res_root_dir.rel_path(node).replace(".png", ".bm")
        #         ),
        #         filter(lambda node: isinstance(node, File), source),
        #     )
        # )
    else:
        asset_basename = f"assets_dolphin_{env['DOLPHIN_RES_TYPE']}"
        target = [
            target_base_dir.File(asset_basename + ".c"),
            target_base_dir.File(asset_basename + ".h"),
        ]

    ## Debug output
    # print(
    #     f"Dolphin res type: {env['DOLPHIN_RES_TYPE']},\ntarget files:",
    #     list(f.path for f in target),
    #     f"\nsource files:",
    #     list(f.path for f in source),
    # )
    return target, source


def _packs_emitter(target, source, env):
    source_dir = source[0]
    target_dir = target[0]
    env.Replace(_PACKS_OUT_DIR=target_dir)
    env.Replace(_PACKS_SRC_DIR=source_dir)
    target = set()

    # Animations
    target.update(
        source_dir.rel_path(node)
        for node in env.GlobRecursive("*/Anims/manifest.txt", source_dir.srcnode())
    )
    target.update(
        source_dir.rel_path(node)
        for node in env.GlobRecursive("*/Anims/**/*.bm", source_dir.srcnode())
    )
    target.update(
        source_dir.rel_path(node).removesuffix(".png") + ".bm"
        for node in env.GlobRecursive("*/Anims/**/*.png", source_dir.srcnode())
    )
    # Animated icons
    target.update(
        source_dir.rel_path(node)
        for node in env.GlobRecursive("*/Icons/*/*/meta", source_dir.srcnode())
    )
    target.update(
        source_dir.rel_path(node).removesuffix("frame_rate") + "meta"
        for node in env.GlobRecursive("*/Icons/*/*/frame_rate", source_dir.srcnode())
    )
    target.update(
        source_dir.rel_path(node)
        for node in env.GlobRecursive("*/Icons/*/*/*.bm", source_dir.srcnode())
    )
    target.update(
        source_dir.rel_path(node).removesuffix(".png") + ".bm"
        for node in env.GlobRecursive("*/Icons/*/*/*.png", source_dir.srcnode())
    )
    # Static icons
    target.update(
        source_dir.rel_path(node)
        for node in env.GlobRecursive("*/Icons/*/*.bmx", source_dir.srcnode())
    )
    target.update(
        source_dir.rel_path(node).removesuffix(".png") + ".bmx"
        for node in env.GlobRecursive("*/Icons/*/*.png", source_dir.srcnode())
    )
    # Fonts
    target.update(
        source_dir.rel_path(node)
        for node in env.GlobRecursive("*/Fonts/*.u8f", source_dir.srcnode())
    )
    target.update(
        source_dir.rel_path(node).removesuffix(".c") + ".u8f"
        for node in env.GlobRecursive("*/Fonts/*.c", source_dir.srcnode())
    )

    target = [target_dir.File(path) for path in target]
    return target, source


def _proto_ver_generator(target, source, env):
    target_file = target[0]
    # The checked-out schema may contain an untagged release. Nearest Git tags
    # can then advertise an older protocol even when new fields are compiled.
    # Changelog is already a tracked builder input; do not fetch mutable tags.
    with open(str(source[0]), encoding="utf-8") as changelog:
        header = next(
            (line.strip() for line in changelog if line.startswith("## ")), ""
        )
    version = re.fullmatch(r"## \[(\d+)\.(\d+)\]", header)
    if not version:
        raise StopError("Missing or invalid protobuf release header in Changelog")
    major, minor = map(int, version.groups())
    version_file_data = (
        "#pragma once",
        f"#define PROTOBUF_MAJOR_VERSION {major}",
        f"#define PROTOBUF_MINOR_VERSION {minor}",
        "",
    )
    with open(str(target_file), "wt") as file:
        file.write("\n".join(version_file_data))


def CompileIcons(
    env,
    target_dir,
    source_dir,
    *,
    icon_bundle_name="assets_icons",
    fw_bundle=False,
    add_include=False,
):
    try:
        os.mkdir(str(source_dir))
    except FileExistsError:
        pass
    return env.IconBuilder(
        target_dir,
        None,
        ICON_SRC_DIR=source_dir,
        ICON_FILE_NAME=icon_bundle_name,
        ICON_FW_BUNDLE=int(fw_bundle),
        ICON_ADD_INCLUDE=int(add_include),
    )


def generate(env):
    env.SetDefault(
        ASSETS_COMPILER="${FBT_SCRIPT_DIR}/assets.py",
        NANOPB_COMPILER="${ROOT_DIR}/lib/nanopb/generator/nanopb_generator.py",
    )
    env.AddMethod(CompileIcons)

    if not env["VERBOSE"]:
        env.SetDefault(
            ICONSCOMSTR="\tICONS\t${TARGET}",
            PROTOCOMSTR="\tPROTO\t${SOURCE}",
            DOLPHINCOMSTR="\tDOLPHIN\t${DOLPHIN_RES_TYPE}",
            PACKSCOMSTR="\tPACKS\t${SOURCE}",
            PBVERCOMSTR="\tPBVER\t${TARGET}",
        )

    env.Append(
        BUILDERS={
            "IconBuilder": Builder(
                action=Action(
                    [
                        [
                            "${PYTHON3}",
                            "${ASSETS_COMPILER}",
                            "icons",
                            "${ICON_SRC_DIR}",
                            "${TARGET.dir}",
                            "--filename",
                            "${ICON_FILE_NAME}",
                            "--fw-bundle",
                            "${ICON_FW_BUNDLE}",
                            "--add-include",
                            "${ICON_ADD_INCLUDE}",
                        ],
                    ],
                    "${ICONSCOMSTR}",
                ),
                emitter=_icons_emitter,
            ),
            "ProtoBuilder": Builder(
                action=Action(
                    [
                        [
                            "${PYTHON3}",
                            "${NANOPB_COMPILER}",
                            "-q",
                            "-I${ASSETS_SRC_DIR}/protobuf_overrides",
                            "-I${ASSETS_SRC_DIR}/protobuf",
                            "-I${SOURCE.dir.posix}",
                            "-D${TARGET.dir.posix}",
                            "${SOURCES.posix}",
                        ],
                    ],
                    "${PROTOCOMSTR}",
                ),
                emitter=_proto_emitter,
                suffix=".pb.c",
                src_suffix=".proto",
            ),
            "DolphinSymBuilder": Builder(
                action=Action(
                    [
                        [
                            "${PYTHON3}",
                            "${ASSETS_COMPILER}",
                            "dolphin",
                            "-s",
                            "dolphin_${DOLPHIN_RES_TYPE}",
                            "${_DOLPHIN_SRC_DIR}",
                            "${_DOLPHIN_OUT_DIR}",
                        ],
                    ],
                    "${DOLPHINCOMSTR}",
                ),
                emitter=_dolphin_emitter,
            ),
            "DolphinExtBuilder": Builder(
                action=Action(
                    [
                        [
                            "${PYTHON3}",
                            "${ASSETS_COMPILER}",
                            "dolphin",
                            "${_DOLPHIN_SRC_DIR}",
                            "${_DOLPHIN_OUT_DIR}",
                        ],
                    ],
                    "${DOLPHINCOMSTR}",
                ),
                emitter=_dolphin_emitter,
            ),
            "AssetPacksBuilder": Builder(
                action=Action(
                    [
                        [
                            "${PYTHON3}",
                            "${ASSETS_COMPILER}",
                            "packs",
                            "${_PACKS_SRC_DIR}",
                            "${_PACKS_OUT_DIR}",
                        ],
                    ],
                    "${PACKSCOMSTR}",
                ),
                emitter=_packs_emitter,
            ),
            "ProtoVerBuilder": Builder(
                action=Action(
                    _proto_ver_generator,
                    "${PBVERCOMSTR}",
                ),
            ),
        }
    )


def exists(env):
    return True
