/*
    SPDX-FileCopyrightText: 2026 Cesar Guzman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "kube_effect_kcm.h"

#include "kube_effect_install.h"
#include "kube_effect_reload.h"

#include <KAboutData>
#include <KLocalizedString>
#include <KGuiItem>
#include <KMessageDialog>
#include <KPluginFactory>
#include <KStandardGuiItem>

#include <QApplication>
#include <QClipboard>
#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDialog>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFont>
#include <QFontDatabase>
#include <QGridLayout>
#include <QGroupBox>
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
#include <QProcess>
#include <QProcessEnvironment>
#include <QProgressBar>
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
    if (!fromMetadata.isEmpty()) {
        return fromMetadata;
    }
    const QString relative = QStringLiteral("plasma/kcms/systemsettings/kcm_kube_effect_plus.so");
    const QStringList paths = QCoreApplication::libraryPaths();
    for (const QString &directory : paths) {
        const QString candidate = directory + QLatin1Char('/') + relative;
        if (QFileInfo::exists(candidate)) {
            return candidate;
        }
    }
    return {};
}

QString dataLocation(const QString &relative)
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QLatin1Char('/') + relative;
}

QString stampPath()
{
    return dataLocation(QStringLiteral("kube-effect/native-stamp.json"));
}

QJsonObject readJsonObject(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        return {};
    }
    QJsonParseError error{};
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &error);
    if (error.error != QJsonParseError::NoError || !document.isObject()) {
        return {};
    }
    return document.object();
}

// Same lookup as the QML effect install: kpackagetool6 puts the package under
// <GenericDataLocation>/kwin/effects/kube-effect (user or system wide).
QString featuresPath()
{
    return QStandardPaths::locate(QStandardPaths::GenericDataLocation,
                                  QStringLiteral("kwin/effects/kube-effect/contents/config/features.json"));
}

// Feature requirement probes. Kept in sync with scripts/check-features.py: a
// label that is not here is a catalog typo, so it is reported as unverifiable
// instead of silently passing.
struct Probe {
    QString path;
    bool isDirectory = false;
};

QHash<QString, Probe> requirementProbes()
{
    const QString imports = QLibraryInfo::path(QLibraryInfo::QmlImportsPath);
    return {
        {QStringLiteral("QtQuick3D"), {imports + QStringLiteral("/QtQuick3D/qmldir"), false}},
        {QStringLiteral("QtQuick.Shapes"), {imports + QStringLiteral("/QtQuick/Shapes/qmldir"), false}},
        {QStringLiteral("QtMultimedia"), {imports + QStringLiteral("/QtMultimedia/qmldir"), false}},
        {QStringLiteral("org.kde.kwin"), {imports + QStringLiteral("/org/kde/kwin"), true}},
        {QStringLiteral("Kirigami"), {imports + QStringLiteral("/org/kde/kirigami/qmldir"), false}},
    };
}

enum class Availability {
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

// MainPID systemd has for the session compositor, 0 when it cannot be read.
// Used only to *confirm* the D-Bus KWin is that process: an unknown value never
// blocks the restart (the Wayland-socket guard is the primary one).
uint sessionCompositorPid(const QString &systemctl)
{
    QProcess query;
    query.start(systemctl,
                {QStringLiteral("--user"),
                 QStringLiteral("show"),
                 KubeReload::serviceUnit(),
                 QStringLiteral("-p"),
                 QStringLiteral("MainPID"),
                 QStringLiteral("--value")});
    if (!query.waitForFinished(2000)) {
        query.kill();
        return 0;
    }
    bool ok = false;
    const uint pid = query.readAllStandardOutput().trimmed().toUInt(&ok);
    return ok ? pid : 0;
}

// Command block for the "Comandos" box: copy/paste ready, real project path when
// the stamp carries "source" (written by native/build.sh). An old stamp without
// the field just gets the placeholder plus a note, never an empty cd.
QString commandsBlock(const QString &sourceRoot)
{
    const bool sourceExists = !sourceRoot.isEmpty() && QFileInfo(sourceRoot).isDir();
    // A store install keeps the sources under contents/native, so build.sh sits
    // directly in the stamp source; a build from the repo points at the repo
    // root (build.sh lives in native/, one level down). Both are supported by
    // build.sh itself, which derives everything from its own location.
    const bool packagedCopy = sourceExists
        && QFileInfo(sourceRoot + QStringLiteral("/build.sh")).isFile();
    const QString directory = sourceExists
        ? sourceRoot
        : QStringLiteral("~/.local/share/kwin/effects/kube-effect/contents/native");

    QString firstLine = QStringLiteral("cd %1").arg(directory);
    if (!sourceExists) {
        firstLine += QStringLiteral("  # ") + i18n("ruta no encontrada, ajústala");
    }

    // Comments start in the same column so the block reads as a table when
    // pasted into the shell (a long cd line simply pushes its own comment).
    const auto commandLine = [](const QString &command, const QString &comment) {
        return command.leftJustified(28, QLatin1Char(' ')) + QStringLiteral("# ") + comment;
    };

    if (packagedCopy) {
        return QStringList{
                   firstLine,
                   commandLine(QStringLiteral("./build.sh"), i18n("instala para tu usuario (sin root)")),
                   commandLine(QStringLiteral("./build.sh --system"), i18n("aparece en Preferencias (pide contraseña)")),
                   commandLine(QStringLiteral("./build.sh --clean"), i18n("borra los árboles de build")),
               }
                   .join(QLatin1Char('\n'))
            + QLatin1Char('\n');
    }

    return QStringList{
               firstLine,
               commandLine(QStringLiteral("make native"), i18n("instala para tu usuario (sin root)")),
               commandLine(QStringLiteral("make native-install"),
                           i18n("pide la contraseña solo al instalar")),
               commandLine(QStringLiteral("make native-status"), i18n("comprueba versión compilada vs instalada")),
           }
               .join(QLatin1Char('\n'))
        + QLatin1Char('\n');
}

// The build command is compiled out unless -DKUBE_SHOW_BUILD_COMMAND=ON
// (ADR-015): the nested harness builds native/ itself, so the hint would only
// invite a redundant build inside the throwaway session.
QString buildCommandHint()
{
#ifdef KUBE_SHOW_BUILD_COMMAND
    return i18n("Compilar e instalar sin root: bash native/build.sh (en el repo) o ./build.sh (desde la copia del paquete)");
#else
    return {};
#endif
}
} // namespace

KubeEffectKcm::KubeEffectKcm(QObject *parent, const KPluginMetaData &data)
    : KCModule(parent, data)
{
    auto *layout = new QVBoxLayout(widget());
    layout->setContentsMargins(0, 0, 0, 0);
    layout->addWidget(buildVersionLabel());
    layout->addWidget(buildStampBox());
    layout->addWidget(buildFeatureBox());
    layout->addWidget(buildActionBox());
    layout->addStretch();
}

QWidget *KubeEffectKcm::buildVersionLabel()
{
    // KF6 KCModule dropped setAboutData(), so KAboutData is only used to render
    // the identity/version header from the plugin metadata. The build versions
    // come from the compile definitions added in native/CMakeLists.txt.
    const KAboutData about(QStringLiteral("kcm_kube_effect_plus"), metaData().name(), metaData().version());

    auto *label = makeLabel(widget());
    label->setText(i18n("%1 %2 — compilado con Plasma %3 · Qt %4 · paquete %5",
                        about.displayName(),
                        about.version(),
                        QStringLiteral(KUBE_PLASMA_VERSION),
                        QStringLiteral(KUBE_QT_VERSION),
                        QStringLiteral(KUBE_PKG_VERSION)));

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
    installLine->setText(i18n("Instalación de sistema: make native-install → aparece en Preferencias → Gestión de ventanas "
                              "(la contraseña solo se pide al instalar)."));
    layout->addWidget(installLine);

    if (!KubeInstall::isSystemInstall(selfPluginFile(metaData()))) {
        auto *privateHint = makeLabel(box);
        privateHint->setObjectName(QStringLiteral("privateInstallWarning"));
        privateHint->setText(i18n("Este menú está instalado solo para tu usuario, por eso no aparece en Preferencias "
                                  "del sistema. Para verlo en Gestión de ventanas ejecuta make native-install, que pide "
                                  "la contraseña solo al instalar (o abre Preferencias con prefix.sh)."));
        markAsWarning(privateHint);
        layout->addWidget(privateHint);
    }

    if (stamp.isEmpty()) {
        m_stampLabel->setText(i18n("No hay stamp nativo en %1: este KCM no se ha compilado aquí "
                                   "para Plasma %2 / Qt %3. Ejecuta make native.\n"
                                   "El efecto QML no lo necesita.",
                                   QDir::toNativeSeparators(stampPath()),
                                   QStringLiteral(KUBE_PLASMA_VERSION),
                                   QStringLiteral(KUBE_QT_VERSION)));
        markAsWarning(m_stampLabel);
        const QString hint = buildCommandHint();
        if (!hint.isEmpty()) {
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
    if (plasma != currentPlasma || qt != currentQt) {
        m_stampLabel->setText(i18n("Compilado para Plasma %1 / Qt %2, tienes Plasma %3 / Qt %4 "
                                   "→ recompila (make native).",
                                   plasma,
                                   qt,
                                   currentPlasma,
                                   currentQt));
        markAsWarning(m_stampLabel);
    } else {
        m_stampLabel->setText(i18n("Al día: compilado para Plasma %1 / Qt %2 — paquete %3, %4.\n"
                                   "Prefijo: %5",
                                   plasma,
                                   qt,
                                   pkg,
                                   built,
                                   QDir::toNativeSeparators(prefix)));
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
    commands->setPlainText(commandsBlock(sourceRoot));
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
    connect(copyButton, &QPushButton::clicked, this, [commands, status]() {
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
    if (path.isEmpty()) {
        layout->addWidget(
            new QLabel(i18n("No encuentro features.json: instala el efecto primero (make install)."), box));
        return box;
    }

    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        layout->addWidget(new QLabel(i18n("No puedo leer %1.", QDir::toNativeSeparators(path)), box));
        return box;
    }
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll());
    if (!document.isArray()) {
        layout->addWidget(new QLabel(i18n("%1 no es un array JSON.", QDir::toNativeSeparators(path)), box));
        return box;
    }

    const QHash<QString, Probe> probes = requirementProbes();
    auto *grid = new QGridLayout;
    grid->setColumnStretch(2, 1);

    int row = 0;
    QStringList missingNotes;
    const QJsonArray features = document.array();
    for (const QJsonValue &value : features) {
        const QJsonObject feature = value.toObject();
        const QJsonValue labelValue = feature.value(QStringLiteral("label"));
        const QString label = labelValue.toString(feature.value(QStringLiteral("id")).toString());
        const QJsonArray requires = feature.value(QStringLiteral("requires")).toArray();

        bool available = true;
        bool unknown = false;
        QStringList requirementTexts;
        for (const QJsonValue &requirementValue : requires) {
            const QString requirement = requirementValue.toString();
            const auto it = probes.constFind(requirement);
            if (it == probes.constEnd()) {
                unknown = true;
                requirementTexts << i18n("%1 (desconocido)", requirement);
                continue;
            }
            const bool present = probeAvailability(*it) == Availability::Available;
            available = available && present;
            requirementTexts << QStringLiteral("%1 %2").arg(requirement, checkMark(present));
        }
        if (requirementTexts.isEmpty()) {
            requirementTexts << QStringLiteral("—");
        }

        auto *status = new QLabel(unknown && available ? QStringLiteral("?") : checkMark(available), box);
        status->setAlignment(Qt::AlignCenter);
        if (!available) {
            markAsWarning(status);
        }
        grid->addWidget(status, row, 0);
        grid->addWidget(new QLabel(label, box), row, 1);
        grid->addWidget(new QLabel(requirementTexts.join(QStringLiteral(", ")), box), row, 2);

        if (!available) {
            const QString notes = feature.value(QStringLiteral("notes")).toString();
            if (!notes.isEmpty()) {
                missingNotes << QStringLiteral("• %1: %2").arg(label, notes);
            }
        }
        ++row;
    }
    layout->addLayout(grid);

    // Notes only for the features that cannot run on this machine, so the box
    // stays short when everything is present.
    if (!missingNotes.isEmpty()) {
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

    // One line, two verbs, because "reconfigure" and "reload" sound alike but do
    // very different things: settings only vs. a new compositor process.
    auto *legend = makeLabel(box);
    legend->setText(i18n("Reconfigurar efecto: cambios de ajustes. "
                         "Recargar compositor: cambios de código (KWin guarda el QML en caché)."));
    layout->addWidget(legend);

    auto *reconfigureButton = new QPushButton(i18n("Reconfigurar efecto"), box);
    reconfigureButton->setIcon(QIcon::fromTheme(QStringLiteral("view-refresh")));
    connect(reconfigureButton, &QPushButton::clicked, this, &KubeEffectKcm::reconfigureEffect);

    m_reloadButton = new QPushButton(i18n("Recargar compositor"), box);
    m_reloadButton->setIcon(QIcon::fromTheme(QStringLiteral("system-reboot")));
    if (KubeReload::isNestedSession(QProcessEnvironment::systemEnvironment())) {
        m_reloadButton->setToolTip(
            i18n("No disponible en el compositor de pruebas: relanza el script para recargar el código."));
    }
    connect(m_reloadButton, &QPushButton::clicked, this, &KubeEffectKcm::reloadCompositor);

    auto *buttons = new QHBoxLayout;
    buttons->addWidget(reconfigureButton);
    buttons->addWidget(m_reloadButton);
    buttons->addStretch();
    layout->addLayout(buttons);

    m_actionStatusLabel = makeLabel(box);
    layout->addWidget(m_actionStatusLabel);

    // Indeterminate bar: the restart takes seconds and the button is disabled
    // meanwhile, so the user needs to see that something is running.
    m_reloadSpinner = new QProgressBar(box);
    m_reloadSpinner->setRange(0, 0);
    m_reloadSpinner->setTextVisible(false);
    m_reloadSpinner->setMaximumHeight(10);
    m_reloadSpinner->setVisible(false);
    layout->addWidget(m_reloadSpinner);

    m_reloadStatusLabel = makeLabel(box);
    layout->addWidget(m_reloadStatusLabel);

    // Hidden unless the build was configured with KUBE_SHOW_BUILD_COMMAND (ADR-015).
    // Install locations are explained in the stamp box, not here.
    const QString hint = buildCommandHint();
    if (!hint.isEmpty()) {
        auto *command = makeLabel(box);
        command->setText(hint);
        layout->addWidget(command);
    }

    return box;
}

void KubeEffectKcm::reconfigureEffect()
{
    QDBusInterface interface(QStringLiteral("org.kde.KWin"),
                             QStringLiteral("/Effects"),
                             QStringLiteral("org.kde.kwin.Effects"),
                             QDBusConnection::sessionBus());
    if (!interface.isValid()) {
        m_actionStatusLabel->setText(i18n("KWin no responde por D-Bus (org.kde.KWin /Effects): %1",
                                          interface.lastError().message()));
        return;
    }

    const QDBusMessage reply = interface.call(QStringLiteral("reconfigureEffect"), QStringLiteral("kube-effect"));
    if (reply.type() == QDBusMessage::ErrorMessage) {
        m_actionStatusLabel->setText(i18n("reconfigureEffect falló: %1", reply.errorMessage()));
        return;
    }
    m_actionStatusLabel->setText(
        i18n("Ajustes reconfigurados. Si has cambiado código QML, usa «Recargar compositor»."));
}

void KubeEffectKcm::reloadCompositor()
{
    if (m_reloadProcess) {
        return; // one restart at a time
    }

    // Never from the nested harness. There the compositor is a throwaway
    // process the script owns; restarting it from inside would leave the test
    // session without a compositor, and a detection bug must never reach the
    // real session.
    if (KubeReload::isNestedSession(QProcessEnvironment::systemEnvironment())) {
        m_reloadStatusLabel->setText(i18n("No disponible en el compositor de pruebas: reinícialo "
                                          "cerrando y volviendo a lanzar el script."));
        return;
    }

    const QString program = QStandardPaths::findExecutable(QStringLiteral("systemctl"));
    if (program.isEmpty()) {
        m_reloadStatusLabel->setText(KubeReload::failureHint(QString(), 0, QString()));
        return;
    }

    // Second, independent guard. Inside the nested session the D-Bus KWin is the
    // script's process, while "systemctl --user" still talks to the HOST user
    // manager: if the socket check ever regressed, this comparison would still
    // catch it. Only a positive mismatch refuses, so a missing /proc or a dead
    // unit keeps today's behaviour instead of breaking the button.
    const uint kwinPid = QDBusConnection::sessionBus().interface()->servicePid(QStringLiteral("org.kde.KWin"));
    const uint sessionPid = sessionCompositorPid(program);
    if (kwinPid != 0 && sessionPid != 0 && !KubeReload::isInProcessTree(kwinPid, sessionPid)
        && !KubeReload::isInProcessTree(sessionPid, kwinPid)) {
        m_reloadStatusLabel->setText(i18n("No puedo confirmar que este compositor sea el de tu sesión: "
                                          "reinicia la sesión a mano para aplicar los cambios."));
        return;
    }

    // Closing every window justifies a dialog (the only one in this KCM).
    // KMessageDialog is asynchronous on purpose: no nested event loop inside a
    // KCM page, and the restart keeps the module responsive.
    auto *dialog = new KMessageDialog(
        KMessageDialog::WarningContinueCancel,
        i18n("Se reiniciará el compositor para aplicar los cambios de código. Las ventanas se cerrarán "
             "y volverán a abrirse (unos 10 segundos). ¿Continuar?"),
        widget());
    dialog->setCaption(i18n("Recargar compositor"));
    dialog->setButtons(KGuiItem(i18n("&Recargar"), QStringLiteral("system-reboot")),
                       KGuiItem(),
                       KStandardGuiItem::cancel());
    dialog->setAttribute(Qt::WA_DeleteOnClose);
    dialog->setWindowModality(Qt::WindowModal);

    // One dialog at a time: the button stays disabled until it is answered.
    m_reloadButton->setEnabled(false);
    connect(dialog, &QDialog::finished, this, [this, program](int result) {
        if (result != KMessageDialog::PrimaryAction) {
            m_reloadButton->setEnabled(true);
            return;
        }
        startReload(program);
    });
    dialog->show();
}

void KubeEffectKcm::startReload(const QString &program)
{
    m_reloadButton->setEnabled(false);
    m_reloadSpinner->setVisible(true);
    m_reloadStatusLabel->setText(i18n("Reiniciando… las ventanas se cerrarán y volverán a abrirse."));

    // Parented to the application, not to this page: closing the KCM while the
    // restart runs must not destroy QProcess (its destructor would kill
    // systemctl halfway through the restart).
    auto *process = new QProcess(QCoreApplication::instance());
    connect(process, &QProcess::finished, process, &QObject::deleteLater);
    m_reloadProcess = process;
    process->setProgram(program);
    process->setArguments(KubeReload::restartCommand().mid(1));

    // A successful restart takes this process down with the old compositor, so
    // the branch that matters in practice is the failure one: that is when the
    // user has to be told why nothing happened.
    connect(process,
            QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this,
            [this, process, program](int exitCode, QProcess::ExitStatus status) {
                finishReload(exitCode == 0 && status == QProcess::NormalExit,
                             exitCode,
                             program,
                             QString::fromLocal8Bit(process->readAllStandardError()));
            });
    connect(process, &QProcess::errorOccurred, this, [this, process, program](QProcess::ProcessError error) {
        // FailedToStart does not emit finished(), so it needs its own path.
        if (error == QProcess::FailedToStart) {
            finishReload(false, -1, program, process->errorString());
        }
    });

    process->start();
}

void KubeEffectKcm::finishReload(bool succeeded, int exitCode, const QString &program, const QString &errorText)
{
    // finished() and errorOccurred() can both arrive; act once.
    if (!m_reloadProcess) {
        return;
    }
    m_reloadProcess->deleteLater();
    m_reloadProcess = nullptr;

    m_reloadSpinner->setVisible(false);
    m_reloadButton->setEnabled(true);

    if (!succeeded && exitCode < 0) {
        // FailedToStart: there is no exit code to show, the reason is in the text.
        m_reloadStatusLabel->setText(i18n("No pude lanzar systemctl:\n%1", errorText));
        return;
    }
    if (succeeded) {
        m_reloadStatusLabel->setText(
            i18n("Compositor reiniciado (código 0). Las ventanas vuelven solas y el código nuevo ya está activo."));
        return;
    }
    m_reloadStatusLabel->setText(KubeReload::failureHint(program, exitCode, errorText));
}

K_PLUGIN_CLASS_WITH_JSON(KubeEffectKcm, "kube_effect_kcm.json")

#include "kube_effect_kcm.moc"
