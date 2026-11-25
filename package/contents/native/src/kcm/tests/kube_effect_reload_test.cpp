/*
    SPDX-FileCopyrightText: 2026 Cesar Guzman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "kube_effect_reload.h"

#include <QProcessEnvironment>
#include <QStringList>
#include <QTest>

class KubeReloadTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void nestedSession_data();
    void nestedSession();

    void restartCommandTargetsTheSessionUnit();
    void nestedSocketWithAbsolutePath();
};

void KubeReloadTest::nestedSession_data()
{
    QTest::addColumn<QString>("waylandDisplay");
    QTest::addColumn<QString>("nestedFlag");
    QTest::addColumn<bool>("expected");

    QTest::newRow("host session") << QStringLiteral("wayland-0") << QString() << false;
    QTest::newRow("host session no marker") << QStringLiteral("wayland-1") << QString() << false;
    QTest::newRow("nested socket") << QStringLiteral("kube-effect-nested-0") << QString() << true;
    QTest::newRow("nested flag only") << QStringLiteral("wayland-0") << QStringLiteral("1") << true;
    QTest::newRow("flag other value") << QStringLiteral("wayland-0") << QStringLiteral("0") << false;
    QTest::newRow("empty environment") << QString() << QString() << false;
}

void KubeReloadTest::nestedSession()
{
    QFETCH(QString, waylandDisplay);
    QFETCH(QString, nestedFlag);
    QFETCH(bool, expected);

    QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
    // The real value must not leak into the test: set or remove explicitly.
    if (waylandDisplay.isEmpty()) {
        environment.remove(QStringLiteral("WAYLAND_DISPLAY"));
    } else {
        environment.insert(QStringLiteral("WAYLAND_DISPLAY"), waylandDisplay);
    }
    if (nestedFlag.isEmpty()) {
        environment.remove(QStringLiteral("KUBE_NESTED"));
    } else {
        environment.insert(QStringLiteral("KUBE_NESTED"), nestedFlag);
    }

    QCOMPARE(KubeReload::isNestedSession(environment), expected);
}

void KubeReloadTest::restartCommandTargetsTheSessionUnit()
{
    const QStringList command = KubeReload::restartCommand();
    QCOMPARE(command.size(), 4);
    QCOMPARE(command.at(0), QStringLiteral("systemctl"));
    QCOMPARE(command.at(1), QStringLiteral("--user"));
    QCOMPARE(command.at(2), QStringLiteral("restart"));
    QCOMPARE(command.at(3), QStringLiteral("plasma-kwin_wayland.service"));
    QCOMPARE(command.at(3), KubeReload::serviceUnit());
    // The KCM never spawns a process: it only joins the argv into the text it
    // offers to copy for a manual, TTY-only restart.
    QCOMPARE(command.join(QLatin1Char(' ')),
             QStringLiteral("systemctl --user restart plasma-kwin_wayland.service"));
}

void KubeReloadTest::nestedSocketWithAbsolutePath()
{
    // Real nested value is an absolute Wayland socket path, not a bare name.
    QProcessEnvironment environment;
    environment.insert(QStringLiteral("WAYLAND_DISPLAY"), QStringLiteral("/run/user/1000/kube-effect-nested-0"));
    QVERIFY(KubeReload::isNestedSession(environment));
}

QTEST_GUILESS_MAIN(KubeReloadTest)

#include "kube_effect_reload_test.moc"
