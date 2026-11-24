# SPDX-FileCopyrightText: 2026 Cesar Guzman
# SPDX-License-Identifier: GPL-2.0-or-later
#
# The KCM is an independent plugin (ADR-011): its metadata is embedded in the
# .so, so nothing else has to be installed next to it.

set(kube_effect_plus_SOURCES
    kube_effect_kcm.cpp
    kube_effect_kcm.json
    # Pure helpers for the compositor restart (nested-session guard, command,
    # stderr trimming). Separate file so tests can exercise them without
    # creating a widget or starting a process.
    kube_effect_reload.cpp
    # Pure decision behind the "installed only for your user" notice: does the
    # .so live under a system prefix? No widget, no filesystem scan.
    kube_effect_install.cpp
)

kcoreaddons_add_plugin(kcm_kube_effect_plus
    INSTALL_NAMESPACE "plasma/kcms/systemsettings"
    SOURCES ${kube_effect_plus_SOURCES}
)

# The .json is included by the moc-generated code, so the source dir must be on
# the include path.
target_include_directories(kcm_kube_effect_plus PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

target_link_libraries(kcm_kube_effect_plus
    Qt6::Core
    Qt6::Gui
    Qt6::Widgets
    Qt6::DBus
    KF6::ConfigCore
    KF6::ConfigWidgets
    KF6::CoreAddons
    KF6::I18n
    KF6::KCMUtils
    # KMessageDialog / KGuiItem: confirmation before restarting the compositor.
    KF6::WidgetsAddons
)

target_compile_definitions(kcm_kube_effect_plus PRIVATE
    TRANSLATION_DOMAIN="kube_effect_kcm"
)

if(KUBE_SHOW_BUILD_COMMAND)
    target_compile_definitions(kcm_kube_effect_plus PRIVATE KUBE_SHOW_BUILD_COMMAND)
endif()
