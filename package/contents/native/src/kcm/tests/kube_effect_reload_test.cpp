/*
    SPDX-FileCopyrightText: 2026 Cesar Guzman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "kube_effect_reload.h"

#include <QCoreApplication>
#include <QFile>
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

    void isInProcessTreeSelf();
    void isInProcessTreeParent();
    void isInProcessTreeUnknown();

    void summarizeErrorEmpty();
    void summarizeErrorKeepsTailOnly();
    void summarizeErrorDropsBlankLines();
    void summarizeErrorExactlyMaxLines();
    void summarizeErrorCarriageReturns();

    void failureHintWithoutSystemctl();
    void failureHintWithStderr();
    void failureHintWithoutStderr();
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
    // What QProcess actually receives: the program plus restartCommand().mid(1).
    QCOMPARE(command.mid(1),
             QStringList({QStringLiteral("--user"), QStringLiteral("restart"), KubeReload::serviceUnit()}));
}

void KubeReloadTest::nestedSocketWithAbsolutePath()
{
    // Real nested value is an absolute Wayland socket path, not a bare name.
    QProcessEnvironment environment;
    environment.insert(QStringLiteral("WAYLAND_DISPLAY"), QStringLiteral("/run/user/1000/kube-effect-nested-0"));
    QVERIFY(KubeReload::isNestedSession(environment));
}

void KubeReloadTest::isInProcessTreeSelf()
{
    const uint self = QCoreApplication::applicationPid();
    QVERIFY(KubeReload::isInProcessTree(self, self, 0));
    QVERIFY(!KubeReload::isInProcessTree(0, self));
    QVERIFY(!KubeReload::isInProcessTree(self, 0));
}

void KubeReloadTest::isInProcessTreeParent()
{
    const uint self = QCoreApplication::applicationPid();
    // The parent is the test runner (or the shell): always one level up.
    QFile stat(QStringLiteral("/proc/%1/stat").arg(self));
    if (!stat.open(QIODevice::ReadOnly)) {
        QSKIP("/proc not available");
    }
    const QString contents = QString::fromLatin1(stat.readAll());
    const QStringList tokens =
        contents.mid(contents.lastIndexOf(QLatin1Char(')')) + 1).split(QLatin1Char(' '), Qt::SkipEmptyParts);
    QByteArray parentToken;
    if (tokens.size() > 1) {
        parentToken = tokens.at(1).toLatin1();
    }
    bool ok = false;
    const uint parent = parentToken.toUInt(&ok);
    if (!ok) {
        QSKIP("cannot read the parent pid");
    }
    QVERIFY(KubeReload::isInProcessTree(self, parent, 1));
}

void KubeReloadTest::isInProcessTreeUnknown()
{
    // A pid that does not exist cannot be in any tree.
    QVERIFY(!KubeReload::isInProcessTree(4194303, 1));
    QVERIFY(!KubeReload::isInProcessTree(1, 4194303));
}

void KubeReloadTest::summarizeErrorEmpty()
{
    QVERIFY(KubeReload::summarizeError(QString()).isEmpty());
    QVERIFY(KubeReload::summarizeError(QStringLiteral("  \n\t\n")).isEmpty());
    QVERIFY(KubeReload::summarizeError(QStringLiteral("x"), 0).isEmpty());
}

void KubeReloadTest::summarizeErrorKeepsTailOnly()
{
    const QString stderrText = QStringLiteral("Job for plasma-kwin_wayland.service failed.\n"
                                              "See \"systemctl --user status plasma-kwin_wayland.service\"\n"
                                              "and \"journalctl --user -xeu plasma-kwin_wayland.service\"\n"
                                              "for details.\n"
                                              "Real cause: unit not found");
    const QString summary = KubeReload::summarizeError(stderrText);
    const QStringList lines = summary.split(QLatin1Char('\n'));

    // Ellipsis marker + the last three lines: the cause survives, the header goes.
    QCOMPARE(lines.size(), 4);
    QCOMPARE(lines.first(), QStringLiteral("…"));
    QCOMPARE(lines.last(), QStringLiteral("Real cause: unit not found"));
    QVERIFY(!summary.contains(QStringLiteral("Job for")));
}

void KubeReloadTest::summarizeErrorDropsBlankLines()
{
    const QString summary = KubeReload::summarizeError(QStringLiteral("a\n\n  \nb"), 5);
    QCOMPARE(summary, QStringLiteral("a\nb"));
}

void KubeReloadTest::summarizeErrorExactlyMaxLines()
{
    // Exactly maxLines: everything fits, so no ellipsis marker is added.
    const QString summary = KubeReload::summarizeError(QStringLiteral("one\ntwo\nthree"), 3);
    QCOMPARE(summary, QStringLiteral("one\ntwo\nthree"));
}

void KubeReloadTest::summarizeErrorCarriageReturns()
{
    // CRLF stderr must not leave stray CR at the end of the shown lines.
    const QString summary = KubeReload::summarizeError(QStringLiteral("first\r\nsecond\r\n"), 5);
    QCOMPARE(summary, QStringLiteral("first\nsecond"));
}

void KubeReloadTest::failureHintWithoutSystemctl()
{
    const QString hint = KubeReload::failureHint(QString(), 0, QString());
    QVERIFY(hint.contains(QStringLiteral("systemctl")));
    QVERIFY(hint.contains(QStringLiteral("Reinicia")));
}

void KubeReloadTest::failureHintWithStderr()
{
    const QString hint = KubeReload::failureHint(QStringLiteral("/usr/bin/systemctl"), 5, QStringLiteral("boom"));
    QVERIFY(hint.contains(QStringLiteral("código 5")));
    QVERIFY(hint.contains(QStringLiteral("boom")));
}

void KubeReloadTest::failureHintWithoutStderr()
{
    const QString hint = KubeReload::failureHint(QStringLiteral("/usr/bin/systemctl"), 5, QString());
    QVERIFY(hint.contains(QStringLiteral("código 5")));
    QVERIFY(hint.contains(QStringLiteral("Reinicia")));
}

QTEST_GUILESS_MAIN(KubeReloadTest)

#include "kube_effect_reload_test.moc"
