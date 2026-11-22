#!/usr/bin/env python3
"""Writes ios/MacDuo.xcodeproj (project + shared scheme).

Run it after adding or removing a source file:  python3 tools/make_project.py
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
IOS = ROOT / "ios"

SWIFT = ["MacDuoApp.swift", "MacLibrary.swift", "MacSession.swift", "MacScreenView.swift",
         "MacKeyboard.swift", "MacView.swift", "LibraryView.swift", "HingeReader.swift"]
CORE_C = ["MVGlue.c"]
CORE_H = ["MVCore.h", "MacDuo-Bridging-Header.h"]
VENDOR_C = ["MINEM68K", "GLOBGLUE", "M68KITAB", "VIAEMDEV", "VIA2EMDV", "IWMEMDEV", "SCCEMDEV",
            "RTCEMDEV", "ROMEMDEV", "SCSIEMDV", "SONYEMDV", "SCRNEMDV", "VIDEMDEV", "ADBEMDEV",
            "ASCEMDEV", "MOUSEMDV", "PROGMAIN"]

counter = 0


def new_id(prefix):
    global counter
    counter += 1
    return f"{prefix}{counter:022X}"


objects = []
sources = []
resources = []


def file_ref(path, kind, tree='"<group>"', name=None):
    ref = new_id("AA")
    extra = f' name = "{name}";' if name else ""
    objects.append(f'{ref} = {{isa = PBXFileReference; lastKnownFileType = {kind};{extra} path = "{path}"; sourceTree = {tree};}};')
    return ref


def build_file(ref, phase):
    bid = new_id("AB")
    objects.append(f"{bid} = {{isa = PBXBuildFile; fileRef = {ref};}};")
    phase.append(bid)


def group(children, path=None, name=None, tree='"<group>"'):
    gid = new_id("C0")
    attrs = f"children = ({', '.join(children)});"
    if path is not None:
        attrs += f' path = "{path}";'
    if name is not None:
        attrs += f' name = "{name}";'
    objects.append(f"{gid} = {{isa = PBXGroup; {attrs} sourceTree = {tree};}};")
    return gid


app_children = []
for f in SWIFT:
    ref = file_ref(f, "sourcecode.swift")
    build_file(ref, sources)
    app_children.append(ref)

core_children = []
for f in CORE_C:
    ref = file_ref(f, "sourcecode.c.c")
    build_file(ref, sources)
    core_children.append(ref)
for f in CORE_H:
    core_children.append(file_ref(f, "sourcecode.c.h"))
app_children.append(group(core_children, path="Core"))

assets = file_ref("Assets.xcassets", "folder.assetcatalog")
build_file(assets, resources)
app_children.append(assets)
app_group = group(app_children, path="MacDuo")

vendor_children = []
for f in VENDOR_C:
    ref = file_ref(f"{f}.c", "sourcecode.c.c")
    build_file(ref, sources)
    vendor_children.append(ref)
vendor_group = group(vendor_children, path="../vendor/minivmac/src", name="Mini vMac", tree="SOURCE_ROOT")

license_ref = file_ref("../vendor/minivmac/COPYING.txt", "text", tree="SOURCE_ROOT", name="COPYING.txt")
build_file(license_ref, resources)

xcconfig = file_ref("App.xcconfig", "text.xcconfig", tree="SOURCE_ROOT")
plist = file_ref("Info.plist", "text.plist.xml", tree="SOURCE_ROOT")
product = new_id("B2")
objects.append(f"{product} = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = MacDuo.app; sourceTree = BUILT_PRODUCTS_DIR;}};")
products = group([product], name="Products")
main_group = group([app_group, vendor_group, license_ref, xcconfig, plist, products])

src_phase = new_id("D0")
objects.append(f"{src_phase} = {{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({', '.join(sources)}); runOnlyForDeploymentPostprocessing = 0;}};")
res_phase = new_id("D1")
objects.append(f"{res_phase} = {{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({', '.join(resources)}); runOnlyForDeploymentPostprocessing = 0;}};")

proj_debug = new_id("E0")
objects.append(f'{proj_debug} = {{isa = XCBuildConfiguration; buildSettings = {{ENABLE_TESTABILITY = YES; IPHONEOS_DEPLOYMENT_TARGET = 17.0; SDKROOT = iphoneos; SWIFT_OPTIMIZATION_LEVEL = "-Onone"; SWIFT_VERSION = 5.0;}}; name = Debug;}};')
proj_release = new_id("E1")
objects.append(f"{proj_release} = {{isa = XCBuildConfiguration; buildSettings = {{IPHONEOS_DEPLOYMENT_TARGET = 17.0; SDKROOT = iphoneos; SWIFT_VERSION = 5.0;}}; name = Release;}};")
tgt_debug = new_id("E2")
objects.append(f"{tgt_debug} = {{isa = XCBuildConfiguration; baseConfigurationReference = {xcconfig}; buildSettings = {{}}; name = Debug;}};")
tgt_release = new_id("E3")
objects.append(f"{tgt_release} = {{isa = XCBuildConfiguration; baseConfigurationReference = {xcconfig}; buildSettings = {{}}; name = Release;}};")
proj_list = new_id("E4")
objects.append(f"{proj_list} = {{isa = XCConfigurationList; buildConfigurations = ({proj_debug}, {proj_release}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;}};")
tgt_list = new_id("E5")
objects.append(f"{tgt_list} = {{isa = XCConfigurationList; buildConfigurations = ({tgt_debug}, {tgt_release}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;}};")

TARGET = "F00000000000000000000002"
PROJECT = "F00000000000000000000001"
objects.append(f'{TARGET} = {{isa = PBXNativeTarget; buildConfigurationList = {tgt_list}; buildPhases = ({src_phase}, {res_phase}); buildRules = (); dependencies = (); name = MacDuo; productName = MacDuo; productReference = {product}; productType = "com.apple.product-type.application";}};')
objects.append(f'{PROJECT} = {{isa = PBXProject; attributes = {{LastUpgradeCheck = 2600; TargetAttributes = {{{TARGET} = {{CreatedOnToolsVersion = 26.0;}};}};}}; buildConfigurationList = {proj_list}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = {main_group}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = ({TARGET});}};')

project = IOS / "MacDuo.xcodeproj"
(project / "xcshareddata" / "xcschemes").mkdir(parents=True, exist_ok=True)
(project / "project.pbxproj").write_text(
    "// !$*UTF8*$!\n{\n    archiveVersion = 1;\n    classes = {};\n    objectVersion = 56;\n    objects = {\n"
    + "".join(f"        {o}\n" for o in objects)
    + f"    }};\n    rootObject = {PROJECT};\n}}\n"
)
ref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{TARGET}" BuildableName="MacDuo.app" BlueprintName="MacDuo" ReferencedContainer="container:MacDuo.xcodeproj"/>'
(project / "xcshareddata" / "xcschemes" / "MacDuo.xcscheme").write_text(
    '<?xml version="1.0" encoding="UTF-8"?>\n<Scheme LastUpgradeVersion="2700" version="1.3">\n'
    f'<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref}</BuildActionEntry></BuildActionEntries></BuildAction>\n'
    f'<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></LaunchAction>\n'
    '<ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>\n</Scheme>\n'
)
print(f"wrote {project} ({len(objects)} objects)")
