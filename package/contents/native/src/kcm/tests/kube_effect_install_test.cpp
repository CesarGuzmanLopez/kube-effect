/*
    SPDX-FileCopyrightText: 2026 Cesar Guzman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "kube_effect_install.h"

#include <QString>
#include <QTest>

/**
 * The notice depends on one decision only: was this .so installed under a
 * system prefix? Every case here is a path string; the test never touches the
 * filesystem.
 */
class KubeInstallTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void systemInstall_data();
    void systemInstall();
};

void KubeInstallTest::systemInstall_data()
{
    QTest::addColumn<QString>("pluginFile");
    QTest::addColumn<bool>("expected");

    QTest::newRow("usr plugins") << QStringLiteral("/usr/lib/qt6/plugins/plasma/kcms/systemsettings/kcm_kube_effect_plus.so")
                                 << true;
    QTest::newRow("usr local") << QStringLiteral("/usr/local/lib64/plugins/plasma/kcms/systemsettings/kcm_kube_effect_plus.so")
                               << true;
    QTest::newRow("usr root") << QStringLiteral("/usr") << true;
    QTest::newRow("usr prefix trap") << QStringLiteral("/usr2/lib/plugins/kcm_kube_effect_plus.so") << false;
    QTest::newRow("private prefix") << QStringLiteral("/home/cesar/.local/lib/plugins/plasma/kcms/systemsettings/kcm_kube_effect_plus.so")
                                    << false;
    QTest::newRow("build tree") << QStringLiteral("build/bin/kcm_kube_effect_plus.so") << false;
    QTest::newRow("relative escape") << QStringLiteral("../usr/lib/kcm_kube_effect_plus.so") << false;
    QTest::newRow("dot-dot inside usr") << QStringLiteral("/usr/lib/plugins/../kcms/systemsettings/kcm_kube_effect_plus.so")
                                        << true;
    QTest::newRow("dot-dot stays outside") << QStringLiteral("/home/cesar/../usr/lib/kcm_kube_effect_plus.so") << false;
    QTest::newRow("empty metadata") << QString() << false;
    QTest::newRow("opt prefix") << QStringLiteral("/opt/kube/lib/plugins/kcm_kube_effect_plus.so") << false;
}

void KubeInstallTest::systemInstall()
{
    QFETCH(QString, pluginFile);
    QFETCH(bool, expected);

    QCOMPARE(KubeInstall::isSystemInstall(pluginFile), expected);
}

QTEST_GUILESS_MAIN(KubeInstallTest)

#include "kube_effect_install_test.moc"
