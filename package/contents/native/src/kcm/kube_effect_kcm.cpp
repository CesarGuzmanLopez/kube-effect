/*
    SPDX-FileCopyrightText: 2026 Cesar Guzman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "kube_effect_kcm.h"

#include "kube_effect_install.h"
#include "kube_effect_reload.h"

#include <KAboutData>
#include <KConfigGroup>
#include <KGuiItem>
#include <KLocalizedString>
#include <KMessageDialog>
#include <KPluginFactory>
#include <KSharedConfig>
#include <KStandardGuiItem>
#include <QApplication>
#include <QClipboard>
#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDialog>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFont>
#include <QFontDatabase>
#include <QGridLayout>
#include <QGroupBox>
#include <QGuiApplication>
#include <QHBoxLayout>
#include <QHash>
#include <QIcon>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>
#include <QLabel>
#include <QLibraryInfo>
#include <QPalette>
#include <QPlainTextEdit>
#include <QProcessEnvironment>
#include <QPushButton>
#include <QStandardPaths>
#include <QStringList>
#include <QTextOption>
#include <QTimer>
#include <QVBoxLayout>

namespace
{
  // Path helpers -------------------------------------------------------------

  // Path of the .so this module was loaded from. Metadata carries it when the
  // plugin came through KPluginFactory; the library-path scan is the fallback for
  // builds where it is empty (same search order Qt used to find us).
  QString selfPluginFile(const KPluginMetaData &data)
  {
    const QString fromMetadata = data.fileName();
    if (!fromMetadata.isEmpty())
    {
      return fromMetadata;
    }
    const QString relative = QStringLiteral("plasma/kcms/systemsettings/kcm_kube_effect_plus.so");
    const QStringList paths = QCoreApplication::libraryPaths();
    for (const QString &directory : paths)
    {
      const QString candidate = directory + QLatin1Char('/') + relative;
      if (QFileInfo::exists(candidate))
      {
        return candidate;
      }
    }
    return {};
  }

  QString dataLocation(const QString &relative)
  {
    return QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) +
           QLatin1Char('/') + relative;
  }

  QString stampPath()
  {
    return dataLocation(QStringLiteral("kube-effect/native-stamp.json"));
  }

  QJsonObject readJsonObject(const QString &path)
  {
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
    {
      return {};
    }
    QJsonParseError error{};
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &error);
    if (error.error != QJsonParseError::NoError || !document.isObject())
    {
      return {};
    }
    return document.object();
  }

  // Same lookup as the QML effect install: kpackagetool6 puts the package under
  // <GenericDataLocation>/kwin/effects/kube-effect (user or system wide).
  QString featuresPath()
  {
    return QStandardPaths::locate(
        QStandardPaths::GenericDataLocation,
        QStringLiteral("kwin/effects/kube-effect/contents/config/features.json"));
  }

  // Feature requirement probes. Kept in sync with scripts/check-features.py: a
  // label that is not here is a catalog typo, so it is reported as unverifiable
  // instead of silently passing.
  struct Probe
  {
    QString path;
    bool isDirectory = false;
  };

  QHash<QString, Probe> requirementProbes()
  {
    const QString imports = QLibraryInfo::path(QLibraryInfo::QmlImportsPath);
    return {
        {QStringLiteral("QtQuick3D"), {imports + QStringLiteral("/QtQuick3D/qmldir"), false}},
        {QStringLiteral("QtQuick.Shapes"),
         {imports + QStringLiteral("/QtQuick/Shapes/qmldir"), false}},
        {QStringLiteral("QtMultimedia"), {imports + QStringLiteral("/QtMultimedia/qmldir"), false}},
        {QStringLiteral("org.kde.kwin"), {imports + QStringLiteral("/org/kde/kwin"), true}},
        {QStringLiteral("Kirigami"), {imports + QStringLiteral("/org/kde/kirigami/qmldir"), false}},
    };
  }

  enum class Availability
  {
    Available,
    Missing,
  };

  Availability probeAvailability(const Probe &probe)
  {
    const QFileInfo info(probe.path);
    const bool exists = probe.isDirectory ? info.isDir() : info.exists();
    return exists ? Availability::Available : Availability::Missing;
  }

  // Highlight without dialogs (ADR-012): bold text on the tooltip colours, which
  // follow the active colour scheme in both light and dark themes.
  void markAsWarning(QLabel *label)
  {
    QFont font = label->font();
    font.setBold(true);
    label->setFont(font);
    QPalette palette = label->palette();
    palette.setColor(QPalette::Window, palette.color(QPalette::ToolTipBase));
    palette.setColor(QPalette::WindowText, palette.color(QPalette::ToolTipText));
    label->setAutoFillBackground(true);
    label->setPalette(palette);
  }

  QLabel *makeLabel(QWidget *parent)
  {
    auto *label = new QLabel(parent);
    label->setWordWrap(true);
    label->setTextFormat(Qt::PlainText);
    label->setTextInteractionFlags(Qt::TextSelectableByMouse);
    return label;
  }

  QString checkMark(bool available)
  {
    return available ? QStringLiteral("\u2713") : QStringLiteral("\u2717");
  }

  // The build command (KubeInstall::commandsBlock, in kube_effect_install.*)
  // lives with the quoting helper so ctest can exercise both without a widget.

  // The build command is compiled out unless -DKUBE_SHOW_BUILD_COMMAND=ON
  // (ADR-015): the nested harness builds native/ itself, so the hint would only
  // invite a redundant build inside the throwaway session.
  QString buildCommandHint()
  {
#ifdef KUBE_SHOW_BUILD_COMMAND
    return i18n("Compilar e instalar sin root: bash native/build.sh (en el repo) o ./build.sh "
                "(desde la copia del paquete)");
#else
    return {};
#endif
  }
} // namespace

KubeEffectKcm::KubeEffectKcm(QObject *parent, const KPluginMetaData &data) : KCModule(parent, data)
{
  auto *layout = new QVBoxLayout(widget());
  layout->setContentsMargins(0, 0, 0, 0);
  layout->addWidget(buildVersionLabel());
  layout->addWidget(buildStampBox());
  layout->addWidget(buildFeatureBox());
  layout->addWidget(buildActionBox());
  layout->addStretch();
}

// The effect only paints a picture or a clip when "Modo de fondo" says so.
// kwinrc can hold a SkyBox image from before the mode enum was renamed
// (SkyBox -> Background, and the URL key took the old name back), leaving the
// mode at its Color default: the picture is then silently ignored. Same for a
// mode that points at media that is no longer set. Returns user-facing hints,
// empty when the combination is coherent.
QString backgroundHint()
{
  KConfigGroup group(KSharedConfig::openConfig(QStringLiteral("kwinrc")),
                     QStringLiteral("Effect-kube-effect"));
  // Same indices as the Background enum of contents/config/main.xml.
  const int mode = group.readEntry(QStringLiteral("Background"), 0);
  const QString image = group.readEntry(QStringLiteral("SkyBox"), QString());
  const QString video = group.readEntry(QStringLiteral("BackgroundVideo"), QString());

  if (mode == 0 && (!image.isEmpty() || !video.isEmpty()))
  {
    return i18n(
        "Hay una imagen o un vídeo de fondo configurado, pero «Modo de fondo» está en Color: "
        "no se pinta nada. Elige Imagen o Vídeo en el menú del efecto.");
  }
  if (mode == 1 && image.isEmpty())
  {
    return i18n("«Modo de fondo» es Imagen y no hay ninguna imagen elegida: solo se ve el "
                "color de fondo.");
  }
  if (mode == 3 && video.isEmpty())
  {
    return i18n("«Modo de fondo» es Vídeo y no hay ningún vídeo elegido: solo se ve el color "
                "de fondo.");
  }
  return {};
}

QWidget *KubeEffectKcm::buildVersionLabel()
{
  // KF6 KCModule dropped setAboutData(), so KAboutData is only used to render
  // the identity/version header from the plugin metadata. The build versions
  // come from the compile definitions added in native/CMakeLists.txt.
  const KAboutData about(QStringLiteral("kcm_kube_effect_plus"), metaData().name(),
                         metaData().version());

  auto *label = makeLabel(widget());
  label->setText(i18n("%1 %2 — compilado con Plasma %3 · Qt %4 · paquete %5", about.displayName(),
                      about.version(), QStringLiteral(KUBE_PLASMA_VERSION),
                      QStringLiteral(KUBE_QT_VERSION), QStringLiteral(KUBE_PKG_VERSION)));

  QFont font = label->font();
  font.setBold(true);
  font.setPointSizeF(font.pointSizeF() * 1.15);
  label->setFont(font);
  return label;
}

QWidget *KubeEffectKcm::buildStampBox()
{
  auto *box = new QGroupBox(i18n("Instalación nativa (KCM opcional)"), widget());
  auto *layout = new QVBoxLayout(box);

  // Read first: the commands block needs "source" (repo root) from the stamp,
  // and a stamp written by an older build.sh simply has no such field.
  const QJsonObject stamp = readJsonObject(stampPath());

  m_stampLabel = makeLabel(box);
  layout->addWidget(m_stampLabel);

  // Where the .so lives decides whether System Settings can list it, so the
  // page says it in plain words (doc/trucos-aprendidos.md, section L):
  // a private prefix is only reachable through prefix.sh.
  auto *installLine = makeLabel(box);
  installLine->setObjectName(QStringLiteral("systemInstallHint"));
  installLine->setText(i18n("Instalación de sistema: make native-install → aparece en "
                            "Preferencias → Gestión de ventanas "
                            "(la contraseña solo se pide al instalar)."));
  layout->addWidget(installLine);

  if (!KubeInstall::isSystemInstall(selfPluginFile(metaData())))
  {
    auto *privateHint = makeLabel(box);
    privateHint->setObjectName(QStringLiteral("privateInstallWarning"));
    privateHint->setText(
        i18n("Este menú está instalado solo para tu usuario, por eso no aparece en Preferencias "
             "del sistema. Para verlo en Gestión de ventanas ejecuta make native-install, que pide "
             "la contraseña solo al instalar (o abre Preferencias con prefix.sh)."));
    markAsWarning(privateHint);
    layout->addWidget(privateHint);
  }

  if (stamp.isEmpty())
  {
    m_stampLabel->setText(i18n("No hay stamp nativo en %1: este KCM no se ha compilado aquí "
                               "para Plasma %2 / Qt %3. Ejecuta make native.\n"
                               "El efecto QML no lo necesita.",
                               QDir::toNativeSeparators(stampPath()),
                               QStringLiteral(KUBE_PLASMA_VERSION),
                               QStringLiteral(KUBE_QT_VERSION)));
    markAsWarning(m_stampLabel);
    const QString hint = buildCommandHint();
    if (!hint.isEmpty())
    {
      layout->addWidget(new QLabel(hint, box));
    }
    layout->addWidget(buildCommandsBox(QString(), box));
    return box;
  }

  const QString plasma = stamp.value(QStringLiteral("plasma")).toString();
  const QString qt = stamp.value(QStringLiteral("qt")).toString();
  const QString pkg = stamp.value(QStringLiteral("pkg")).toString();
  const QString built = stamp.value(QStringLiteral("built")).toString();
  const QString prefix = stamp.value(QStringLiteral("prefix")).toString();

  // Plasma has no stable ABI across releases (ADR-012): a mismatch means the
  // .so may be rejected by KWin or fail to load, so say so plainly.
  const QString currentPlasma = QStringLiteral(KUBE_PLASMA_VERSION);
  const QString currentQt = QStringLiteral(KUBE_QT_VERSION);
  if (plasma != currentPlasma || qt != currentQt)
  {
    m_stampLabel->setText(i18n("Compilado para Plasma %1 / Qt %2, tienes Plasma %3 / Qt %4 "
                               "→ recompila (make native).",
                               plasma, qt, currentPlasma, currentQt));
    markAsWarning(m_stampLabel);
  }
  else
  {
    m_stampLabel->setText(i18n("Al día: compilado para Plasma %1 / Qt %2 — paquete %3, %4.\n"
                               "Prefijo: %5",
                               plasma, qt, pkg, built, QDir::toNativeSeparators(prefix)));
  }

  layout->addWidget(buildCommandsBox(stamp.value(QStringLiteral("source")).toString(), box));
  return box;
}

QWidget *KubeEffectKcm::buildCommandsBox(const QString &sourceRoot, QWidget *parent)
{
  auto *box = new QGroupBox(i18n("Comandos"), parent);
  auto *layout = new QVBoxLayout(box);

  // Plain text, monospaced and without wrapping: the block is meant to be
  // selected and pasted verbatim, so a soft-wrapped long path would be
  // copied with a newline inside the command.
  auto *commands = new QPlainTextEdit(box);
  commands->setObjectName(QStringLiteral("commandsBlock"));
  commands->setReadOnly(true);
  commands->setWordWrapMode(QTextOption::NoWrap);
  commands->setFont(QFontDatabase::systemFont(QFontDatabase::FixedFont));
  commands->setPlainText(KubeInstall::commandsBlock(sourceRoot));
  commands->setFixedHeight(commands->fontMetrics().lineSpacing() * 4 + 24);
  layout->addWidget(commands);

  auto *copyButton = new QPushButton(i18n("Copiar comandos"), box);
  copyButton->setObjectName(QStringLiteral("copyCommandsButton"));
  copyButton->setIcon(QIcon::fromTheme(QStringLiteral("edit-copy")));
  auto *status = makeLabel(box);
  status->setObjectName(QStringLiteral("copyCommandsStatus"));

  auto *row = new QHBoxLayout;
  row->addWidget(copyButton);
  row->addWidget(status, 1);
  layout->addLayout(row);

  // The clipboard belongs to the application, so this also works with the KCM
  // embedded in System Settings (same process as the settings window).
  connect(copyButton, &QPushButton::clicked, this,
          [commands, status]()
          {
            QApplication::clipboard()->setText(commands->toPlainText());
            status->setText(i18n("Comandos copiados."));
            // Confirmation goes away by itself; the clipboard keeps the commands.
            QTimer::singleShot(4000, status, &QLabel::clear);
          });
  return box;
}

QWidget *KubeEffectKcm::buildFeatureBox()
{
  auto *box = new QGroupBox(i18n("Dependencias de features (features.json)"), widget());
  auto *layout = new QVBoxLayout(box);

  const QString path = featuresPath();
  if (path.isEmpty())
  {
    layout->addWidget(new QLabel(
        i18n("No encuentro features.json: instala el efecto primero (make install)."), box));
    return box;
  }

  QFile file(path);
  if (!file.open(QIODevice::ReadOnly))
  {
    layout->addWidget(new QLabel(i18n("No puedo leer %1.", QDir::toNativeSeparators(path)), box));
    return box;
  }
  const QJsonDocument document = QJsonDocument::fromJson(file.readAll());
  if (!document.isArray())
  {
    layout->addWidget(
        new QLabel(i18n("%1 no es un array JSON.", QDir::toNativeSeparators(path)), box));
    return box;
  }

  const QHash<QString, Probe> probes = requirementProbes();
  auto *grid = new QGridLayout;
  grid->setColumnStretch(2, 1);

  int row = 0;
  QStringList missingNotes;
  const QJsonArray features = document.array();
  for (const QJsonValue &value : features)
  {
    const QJsonObject feature = value.toObject();
    const QJsonValue labelValue = feature.value(QStringLiteral("label"));
    const QString label = labelValue.toString(feature.value(QStringLiteral("id")).toString());
    const QJsonArray
      requires
    = feature.value(QStringLiteral("requires")).toArray();

    bool available = true;
    bool unknown = false;
    QStringList requirementTexts;
    for (const QJsonValue &requirementValue : requires)
    {
      const QString requirement = requirementValue.toString();
      const auto it = probes.constFind(requirement);
      if (it == probes.constEnd())
      {
        unknown = true;
        requirementTexts << i18n("%1 (desconocido)", requirement);
        continue;
      }
      const bool present = probeAvailability(*it) == Availability::Available;
      available = available && present;
      requirementTexts << QStringLiteral("%1 %2").arg(requirement, checkMark(present));
    }
    if (requirementTexts.isEmpty())
    {
      requirementTexts << QStringLiteral("—");
    }

    auto *status =
        new QLabel(unknown && available ? QStringLiteral("?") : checkMark(available), box);
    status->setAlignment(Qt::AlignCenter);
    if (!available)
    {
      markAsWarning(status);
    }
    grid->addWidget(status, row, 0);
    grid->addWidget(new QLabel(label, box), row, 1);
    grid->addWidget(new QLabel(requirementTexts.join(QStringLiteral(", ")), box), row, 2);

    if (!available)
    {
      const QString notes = feature.value(QStringLiteral("notes")).toString();
      if (!notes.isEmpty())
      {
        missingNotes << QStringLiteral("• %1: %2").arg(label, notes);
      }
    }
    ++row;
  }
  layout->addLayout(grid);

  // Notes only for the features that cannot run on this machine, so the box
  // stays short when everything is present.
  if (!missingNotes.isEmpty())
  {
    auto *notes = makeLabel(box);
    notes->setText(missingNotes.join(QLatin1Char('\n')));
    layout->addWidget(notes);
  }
  return box;
}

QWidget *KubeEffectKcm::buildActionBox()
{
  auto *box = new QGroupBox(i18n("Efecto"), widget());
  auto *layout = new QVBoxLayout(box);

  // A silent mismatch between the background mode and the configured media
  // looks like "the background never works", so it is said here, in the one
  // place that reads the real kwinrc.
  const QString backgroundWarning = backgroundHint();
  if (!backgroundWarning.isEmpty())
  {
    auto *warning = makeLabel(box);
    warning->setText(backgroundWarning);
    markAsWarning(warning);
    layout->addWidget(warning);
  }

  // One line, two verbs, because "reconfigure" and "reload" sound alike but do
  // very different things: settings only vs. a new compositor process.
  auto *legend = makeLabel(box);
  legend->setText(i18n("Reconfigurar efecto: cambios de ajustes. "
                       "Aplicar cambios de código: cierra la sesión y vuelve a entrar (KWin "
                       "guarda el QML en caché)."));
  layout->addWidget(legend);

  auto *reconfigureButton = new QPushButton(i18n("Reconfigurar efecto"), box);
  reconfigureButton->setIcon(QIcon::fromTheme(QStringLiteral("view-refresh")));
  connect(reconfigureButton, &QPushButton::clicked, this, &KubeEffectKcm::reconfigureEffect);

  m_reloadButton = new QPushButton(i18n("Aplicar cambios de código"), box);
  m_reloadButton->setIcon(QIcon::fromTheme(QStringLiteral("system-log-out")));
  if (KubeReload::isNestedSession(QProcessEnvironment::systemEnvironment()))
  {
    m_reloadButton->setToolTip(i18n("No disponible en el compositor de pruebas: relanza el "
                                    "script para recargar el código."));
  }
  connect(m_reloadButton, &QPushButton::clicked, this, &KubeEffectKcm::reloadCompositor);

  auto *buttons = new QHBoxLayout;
  buttons->addWidget(reconfigureButton);
  buttons->addWidget(m_reloadButton);
  buttons->addStretch();
  layout->addLayout(buttons);

  m_actionStatusLabel = makeLabel(box);
  layout->addWidget(m_actionStatusLabel);

  m_reloadStatusLabel = makeLabel(box);
  layout->addWidget(m_reloadStatusLabel);

  // Hidden unless the build was configured with KUBE_SHOW_BUILD_COMMAND (ADR-015).
  // Install locations are explained in the stamp box, not here.
  const QString hint = buildCommandHint();
  if (!hint.isEmpty())
  {
    auto *command = makeLabel(box);
    command->setText(hint);
    layout->addWidget(command);
  }

  return box;
}

void KubeEffectKcm::reconfigureEffect()
{
  // Asynchronous (ADR-022): QDBusInterface::call blocks the GUI thread while
  // D-Bus waits for the reply, and an unresponsive KWin froze the settings
  // window for up to 25 s. asyncCall + watcher keeps the thread free; the
  // outcome lands in the same label. No signals, no extra threads.
  m_actionStatusLabel->setText(i18n("Reconfigurando efecto…"));
  QDBusMessage message = QDBusMessage::createMethodCall(
      QStringLiteral("org.kde.KWin"), QStringLiteral("/Effects"),
      QStringLiteral("org.kde.kwin.Effects"), QStringLiteral("reconfigureEffect"));
  message << QStringLiteral("kube-effect");
  // asyncCall() is this Qt's non-blocking call: Qt 6 dropped the
  // QDBusMessage -> QDBusPendingCall conversion that made
  // call(message, QDBus::NoBlock) usable in Qt 5. Same semantics, no sync wait.
  const QDBusPendingCall pending = QDBusConnection::sessionBus().asyncCall(message);
  auto *watcher = new QDBusPendingCallWatcher(pending, this);
  connect(watcher, &QDBusPendingCallWatcher::finished, this,
          [this](QDBusPendingCallWatcher *w)
          {
            const QDBusPendingReply<> reply = *w;
            if (reply.isError())
            {
              m_actionStatusLabel->setText(
                  i18n("reconfigureEffect falló: %1", reply.error().message()));
              w->deleteLater();
              return;
            }
            m_actionStatusLabel->setText(i18n("Ajustes reconfigurados. Si has cambiado código "
                                              "QML, usa «Aplicar cambios de código»."));
            w->deleteLater();
          });
}

void KubeEffectKcm::reloadCompositor()
{
  // Never from the nested harness. There the compositor is a throwaway
  // process the script owns; relaunch the script to reload the code.
  if (KubeReload::isNestedSession(QProcessEnvironment::systemEnvironment()))
  {
    m_reloadStatusLabel->setText(i18n("No disponible en el compositor de pruebas: reinícialo "
                                      "cerrando y volviendo a lanzar el script."));
    return;
  }

  // Wayland safety (2026-11-25, measured): restarting
  // plasma-kwin_wayland.service from inside the session kills every Wayland
  // client (plasmashell, kded, every app) and the new compositor comes up on
  // a new socket without owning org.kde.KWin, so nothing reconnects: the
  // desktop stays dead. There is no "restart only the compositor": on
  // Wayland KWin *is* the display server, and neither reconfigure() nor
  // loadEffect()/unloadEffect() recompiles the cached QML (bug #514131). The
  // safe equivalent is a clean logout: SDDM brings the session back and the
  // new kwin_wayland process compiles the QML from disk.
  const QString command = KubeReload::restartCommand().join(QLatin1Char(' '));
  auto *dialog = new KMessageDialog(
      KMessageDialog::WarningContinueCancel,
      i18n("Se cerrará la sesión para aplicar los cambios de código: se cierran todas las "
           "aplicaciones abiertas y se vuelve a entrar sola (unos segundos).\n\n"
           "No se reinicia KWin en caliente: en Wayland eso deja el escritorio muerto.\n\n"
           "Para probar sin cerrar nada usa el KWin anidado (scripts/kwin-nested-test.sh).\n\n"
           "Comando manual, solo desde TTY y bajo tu responsabilidad:\n%1",
           command),
      widget());
  dialog->setCaption(i18n("Aplicar cambios de código"));
  dialog->setButtons(KGuiItem(i18n("&Cerrar sesión"), QStringLiteral("system-log-out")),
                     KGuiItem(i18n("&Copiar comando"), QStringLiteral("edit-copy")),
                     KStandardGuiItem::cancel());
  dialog->setAttribute(Qt::WA_DeleteOnClose);
  dialog->setWindowModality(Qt::WindowModal);

  m_reloadButton->setEnabled(false);
  connect(dialog, &QDialog::finished, this,
          [this, command](int result)
          {
            if (result == KMessageDialog::PrimaryAction)
            {
              requestLogout();
              return;
            }
            if (result == KMessageDialog::SecondaryAction)
            {
              if (QClipboard *clipboard = QGuiApplication::clipboard())
              {
                clipboard->setText(command);
              }
              m_reloadStatusLabel->setText(
                  i18n("Comando copiado al portapapeles. Úsalo solo desde TTY: "
                       "cierra sesión y vuelve a entrar para aplicar los cambios."));
            }
            else
            {
              m_reloadStatusLabel->setText(
                  i18n("Sin cambios aplicados. Cierra sesión y vuelve a entrar "
                       "para activar el código nuevo, o usa el KWin anidado."));
            }
            m_reloadButton->setEnabled(true);
          });
  dialog->show();
}

void KubeEffectKcm::requestLogout()
{
  // The supported route: Plasma's shutdown service, not a systemctl verb. It
  // is the same call the desktop's own "Log Out" uses, so apps get their
  // usual close notification instead of being killed with the compositor.
  // Asynchronous for the same reason as reconfigureEffect (ADR-022): a hung
  // org.kde.Shutdown must not freeze this window before the logout happens.
  m_reloadStatusLabel->setText(i18n("Cerrando sesión…"));
  const QDBusMessage message = QDBusMessage::createMethodCall(
      QStringLiteral("org.kde.Shutdown"), QStringLiteral("/Shutdown"),
      QStringLiteral("org.kde.Shutdown"), QStringLiteral("logout"));
  // asyncCall(): non-blocking on Qt 6 (see reconfigureEffect).
  const QDBusPendingCall pending = QDBusConnection::sessionBus().asyncCall(message);
  auto *watcher = new QDBusPendingCallWatcher(pending, this);
  connect(watcher, &QDBusPendingCallWatcher::finished, this,
          [this](QDBusPendingCallWatcher *w)
          {
            const QDBusPendingReply<> reply = *w;
            if (reply.isError())
            {
              m_reloadStatusLabel->setText(
                  i18n("No se pudo cerrar la sesión (%1). Ciérrala a mano: "
                       "en Wayland es la única forma de recompilar el QML.",
                       reply.error().message()));
              m_reloadButton->setEnabled(true);
              w->deleteLater();
              return;
            }
            // No need to re-enable: the session is going away.
            m_reloadStatusLabel->setText(
                i18n("Cerrando sesión… al volver a entrar, KWin recompila el QML y "
                     "el código nuevo queda activo."));
            w->deleteLater();
          });
}
K_PLUGIN_CLASS_WITH_JSON(KubeEffectKcm, "kube_effect_kcm.json")

#include "kube_effect_kcm.moc"
