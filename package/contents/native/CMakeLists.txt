# SPDX-FileCopyrightText: 2026 Cesar Guzman
# SPDX-License-Identifier: GPL-2.0-or-later
#
# kube-effect — optional native side (ADR-011 / ADR-012 / ADR-018).
#
# The cube itself is QML-only: its settings menu is the generic KCM
# (config.ui via kcm_kwin4_genericscripted) and it works with nothing compiled.
# This project builds the INDEPENDENT "Kube Effect Plus" KCM
# (kcm_kube_effect_plus), which adds diagnostics, the feature dependency check
# and reconfigureEffect. It is built on demand (make native) and never
# automatically.

cmake_minimum_required(VERSION 3.16)

project(kube_effect_native VERSION 0.0.0.2 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(ECM 6.0 REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH} ${CMAKE_MODULE_PATH})

# Qt6 must be found BEFORE KDEInstallDirs: its dispatcher (QtVersionOption)
# decides between KDEInstallDirs5/6 from TARGET Qt6::Core or an explicit
# QT_MAJOR_VERSION. Finding Qt later silently picks KDEInstallDirs5 and then
# Qt5Core poisons QT_DEFAULT_MAJOR_VERSION for every later KF6 find_dependency.
find_package(Qt6 REQUIRED COMPONENTS Core Gui Widgets DBus)

# Private prefix by default (~/.local): no root needed (ADR-012). Plugins under
# a private prefix are found through prefix.sh / QT_PLUGIN_PATH, never globally.
#
# KDE_INSTALL_USE_QT_SYS_PATHS ON makes QTPLUGINDIR/QMLDIR absolute (Qt's own
# dirs), so it is only correct when installing into the same prefix as Qt. ECM
# already turns it ON by itself when QT_INSTALL_PREFIX == CMAKE_INSTALL_PREFIX
# (/usr installs); forcing it unconditionally would send a ~/.local install to
# /usr/lib/qt6/plugins, i.e. require root, which ADR-012 forbids.
if(CMAKE_INSTALL_PREFIX STREQUAL "/usr")
    set(KDE_INSTALL_USE_QT_SYS_PATHS ON)
endif()

# KDEInstallDirs (the ECM dispatcher; there is no "ECMQt6/KDEInstallDirs" file in
# ECM >= 6.30) also generates prefix.sh in the build dir, the only way a
# private-prefix KCM is found by systemsettings.
include(KDEInstallDirs)
# KDECMakeSettings sets CMAKE_LIBRARY_OUTPUT_DIRECTORY, which
# kcoreaddons_add_plugin() refuses to work without, plus AUTOMOC.
include(KDECMakeSettings)

# KCMUtils is not in the minimal component list but KCModule lives there and this
# KCM derives from it. KConfigCore/KConfigWidgets provide the config helpers.
# WidgetsAddons carries KMessageDialog, used to confirm the compositor restart.
find_package(KF6 REQUIRED COMPONENTS Config CoreAddons ConfigWidgets I18n KCMUtils WidgetsAddons)

# Qt Test is only needed by the helper unit test below; QUIET + TARGET check so a
# machine without the Test module still builds the KCM.
find_package(Qt6 QUIET COMPONENTS Test)

# Plasma (KWin) version. There is no stable ABI between Plasma releases, so the
# .so is stamped and the KCM warns when it stops matching (ADR-012).
#
# Chosen detection order:
#   1. find_package(KWin) -> KWin_VERSION. Authoritative: it is the version of
#      the KWin we link/run against (the KWin CMake package ships the version in
#      KWinConfigVersion.cmake).
#   2. Fallback: run "kwin_wayland --version" at configure time and keep the
#      version string. Used on machines without the KWin CMake package.
# KWindowSystem is NOT a substitute: it reports the KF6 framework version, not
# Plasma's.
find_package(KWin QUIET)
if(KWin_VERSION)
    set(KUBE_PLASMA_VERSION "${KWin_VERSION}")
else()
    execute_process(
        COMMAND kwin_wayland --version
        OUTPUT_VARIABLE _kube_kwin_version_output
        ERROR_QUIET
        OUTPUT_STRIP_TRAILING_WHITESPACE
    )
    string(REGEX MATCH "[0-9]+\\.[0-9]+\\.[0-9]+" KUBE_PLASMA_VERSION "${_kube_kwin_version_output}")
endif()
if(NOT KUBE_PLASMA_VERSION)
    set(KUBE_PLASMA_VERSION "unknown")
    message(WARNING "kube-effect: cannot detect the KWin version; the KCM will report it as unknown")
endif()

message(STATUS "kube-effect native: Plasma/KWin ${KUBE_PLASMA_VERSION}, Qt ${Qt6_VERSION}, package ${PROJECT_VERSION}")

# Stamped into the .so: the KCM compares them with the running KWin/Qt and the
# native-stamp.json written by build.sh.
add_compile_definitions(
    KUBE_PKG_VERSION="${PROJECT_VERSION}"
    KUBE_QT_VERSION="${Qt6_VERSION}"
    KUBE_PLASMA_VERSION="${KUBE_PLASMA_VERSION}"
)

# OFF by default on purpose (ADR-015): the nested harness compiles native/
# before launching, so the KCM is always up to date in the test session. Showing
# the build command there only invites a redundant build/install inside a
# throwaway session. Distributions/packagers enable it if they want the hint.
option(KUBE_SHOW_BUILD_COMMAND "Show the native build command inside the KCM" OFF)

add_subdirectory(src/kcm)

# Unit test for the restart helpers (nested guard, command, stderr trimming).
# No widget, no process: it never restarts anything.
if(TARGET Qt6::Test)
    add_subdirectory(src/kcm/tests)
endif()

# Smoke test: instantiates the KCM (KCModule + widget tree) headless. `ctest`
# from the build dir; it does not install anything. kcmshell6 only learned
# --smoke-test in KF6 6.27, so skip it on older frameworks instead of failing.
enable_testing()
if(KF6KCMUtils_VERSION VERSION_GREATER_EQUAL "6.27.0")
    add_test(NAME kcm_kube_effect_plus_smoke COMMAND kcmshell6 --smoke-test kcm_kube_effect_plus)
    set_tests_properties(kcm_kube_effect_plus_smoke PROPERTIES
        ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_PLUGIN_PATH=${CMAKE_BINARY_DIR}/bin")
endif()

# Machine-readable summary of what this build was compiled against.
# build.sh turns it into ~/.local/share/kube-effect/native-stamp.json (plus
# prefix.sh) after a successful install.
configure_file(kube-native-info.json.in ${CMAKE_BINARY_DIR}/kube-native-info.json @ONLY)
