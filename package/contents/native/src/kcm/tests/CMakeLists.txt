# SPDX-FileCopyrightText: 2026 Cesar Guzman
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Unit test for kube_effect_reload.cpp: it decides whether "Recargar
# compositor" may run at all. Every case is pure data; the test never starts
# systemctl and never touches the session.

add_executable(kube_effect_reload_test
    kube_effect_reload_test.cpp
    ../kube_effect_reload.cpp
)

target_include_directories(kube_effect_reload_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/..)

target_link_libraries(kube_effect_reload_test
    Qt6::Core
    Qt6::Test
    KF6::I18n
)

# Same domain as the KCM so i18n() does not warn about a missing domain in tests.
target_compile_definitions(kube_effect_reload_test PRIVATE TRANSLATION_DOMAIN="kube_effect_kcm")

# Install-location decision (system prefix vs private prefix). Pure path strings:
# it never scans the filesystem nor creates a widget.
add_executable(kube_effect_install_test
    kube_effect_install_test.cpp
    ../kube_effect_install.cpp
)

target_include_directories(kube_effect_install_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/..)

target_link_libraries(kube_effect_install_test
    Qt6::Core
    Qt6::Test
)

add_test(NAME kube_effect_install COMMAND kube_effect_install_test)

add_test(NAME kube_effect_reload COMMAND kube_effect_reload_test)
set_tests_properties(kube_effect_reload PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
