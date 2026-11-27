/*
    SPDX-FileCopyrightText: 2026 Cesar Guzman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "kube_effect_install.h"

#include <QDir>
#include <QString>
#include <QTest>

/**
 * Two helpers of the Plus page: the system-prefix decision (path strings only,
 * never the filesystem) and the commands block with its shell quoting
 * (ADR-022). The commands cases stat directories through QFileInfo and create
 * one temporary folder; no process is started.
 */
class KubeInstallTest : public QObject
{
  Q_OBJECT

private Q_SLOTS:
  void systemInstall_data();
  void systemInstall();

  void shellQuote();
  void commandsBlockQuotesStampPath();
  void commandsBlockPlaceholder();
};

void KubeInstallTest::systemInstall_data()
{
  QTest::addColumn<QString>("pluginFile");
  QTest::addColumn<bool>("expected");

  QTest::newRow("usr plugins")
      << QStringLiteral("/usr/lib/qt6/plugins/plasma/kcms/systemsettings/kcm_kube_effect_plus.so")
      << true;
  QTest::newRow("usr local")
      << QStringLiteral(
             "/usr/local/lib64/plugins/plasma/kcms/systemsettings/kcm_kube_effect_plus.so")
      << true;
  QTest::newRow("usr root") << QStringLiteral("/usr") << true;
  QTest::newRow("usr prefix trap")
      << QStringLiteral("/usr2/lib/plugins/kcm_kube_effect_plus.so") << false;
  QTest::newRow("private prefix")
      << QStringLiteral(
             "/home/cesar/.local/lib/plugins/plasma/kcms/systemsettings/kcm_kube_effect_plus.so")
      << false;
  QTest::newRow("build tree") << QStringLiteral("build/bin/kcm_kube_effect_plus.so") << false;
  QTest::newRow("relative escape") << QStringLiteral("../usr/lib/kcm_kube_effect_plus.so") << false;
  QTest::newRow("dot-dot inside usr")
      << QStringLiteral("/usr/lib/plugins/../kcms/systemsettings/kcm_kube_effect_plus.so") << true;
  QTest::newRow("dot-dot stays outside")
      << QStringLiteral("/home/cesar/../usr/lib/kcm_kube_effect_plus.so") << false;
  QTest::newRow("empty metadata") << QString() << false;
  QTest::newRow("opt prefix") << QStringLiteral("/opt/kube/lib/plugins/kcm_kube_effect_plus.so")
                              << false;
}

void KubeInstallTest::systemInstall()
{
  QFETCH(QString, pluginFile);
  QFETCH(bool, expected);

  QCOMPARE(KubeInstall::isSystemInstall(pluginFile), expected);
}

void KubeInstallTest::shellQuote()
{
  // Ordinary words: just wrapped.
  QCOMPARE(KubeInstall::shellQuote(QStringLiteral("repo")), QStringLiteral("'repo'"));
  // Spaces and metacharacters stay inert inside single quotes.
  QCOMPARE(KubeInstall::shellQuote(QStringLiteral("/tmp/my repo; rm -rf /")),
           QStringLiteral("'/tmp/my repo; rm -rf /'"));
  // The only thing that needs escaping is the quote itself: close the
  // string, emit an escaped quote, reopen it (four chars: ' \ ' ').
  QCOMPARE(KubeInstall::shellQuote(QStringLiteral("a'b")), QStringLiteral("'a'\\''b'"));
  // Command substitutions never expand inside quotes.
  QCOMPARE(KubeInstall::shellQuote(QStringLiteral("$(whoami)")), QStringLiteral("'$(whoami)'"));
  // Empty word: valid empty argument, not an empty string.
  QCOMPARE(KubeInstall::shellQuote(QString()), QStringLiteral("''"));
}

void KubeInstallTest::commandsBlockQuotesStampPath()
{
  // An absolute existing directory carrying a quote and a space: the cd line
  // must hand it to the shell as one quoted argument (ADR-022).
  const QString dir = QDir::tempPath() + QStringLiteral("/kube-quotes 'test'");
  QVERIFY(QDir().mkpath(dir));
  const QString block = KubeInstall::commandsBlock(dir);
  // The cd line carries exactly shellQuote(dir): the embedded quotes
  // come out as the '\\'' sequence, so compare against the helper itself.
  QVERIFY2(block.contains(QStringLiteral("cd ") + KubeInstall::shellQuote(dir)), qPrintable(block));
  QVERIFY(block.contains(QStringLiteral("make native")));
  QVERIFY(!block.contains(QStringLiteral("ruta no encontrada")));
  QDir().rmdir(dir);
}

void KubeInstallTest::commandsBlockPlaceholder()
{
  // A relative "source" (tampered stamp) is NOT trusted as a path (ADR-022):
  // the block falls back to the unquoted tilde placeholder with its note.
  const QString block = KubeInstall::commandsBlock(QStringLiteral("relative/path"));
  QVERIFY(
      block.contains(QStringLiteral("cd ~/.local/share/kwin/effects/kube-effect/contents/native")));
  QVERIFY(block.contains(QStringLiteral("ruta no encontrada")));
  QVERIFY(!block.contains(QStringLiteral("relative/path")));

  // An absolute-but-missing path with an injection payload also falls back:
  // the payload never reaches a cd line.
  const QString tricky = QStringLiteral("/nonexistent-kube/x'; touch /tmp/pwn");
  const QString block2 = KubeInstall::commandsBlock(tricky);
  QVERIFY(block2.contains(QStringLiteral("ruta no encontrada")));
  QVERIFY(!block2.contains(QStringLiteral("touch")));
}

QTEST_GUILESS_MAIN(KubeInstallTest)

#include "kube_effect_install_test.moc"
