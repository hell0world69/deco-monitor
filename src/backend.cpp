#include "backend.h"

#include <QClipboard>
#include <QDateTime>
#include <QGuiApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkInterface>
#include <QStandardPaths>

namespace {

QString clip(const QJsonValue &v, int max = 64) { return v.toString().left(max); }
double positive(const QJsonValue &v) { const double d = v.toDouble(); return d > 0 ? d : 0; }

}

Backend::Backend(const QString &statusPath, const QString &decoCommand, QObject *parent)
    : QObject(parent),
      m_path(!statusPath.isEmpty() ? statusPath
             : qEnvironmentVariable("XDG_RUNTIME_DIR", QDir::tempPath()) + "/deco-monitor/status.json"),
      m_deco(!decoCommand.isEmpty() ? decoCommand : QStandardPaths::findExecutable("deco")) {
    // The service replaces the file atomically, which drops inotify watches,
    // so re-arm on every change and keep a slow poll as a safety net.
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, &Backend::reload);
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, &Backend::reload);
    m_poll.setInterval(3000);
    connect(&m_poll, &QTimer::timeout, this, &Backend::reload);
    m_poll.start();

    connect(&m_reboot, &QProcess::finished, this, [this](int code, QProcess::ExitStatus status) {
        const QByteArray out = m_reboot.readAllStandardOutput();
        const QJsonObject result = QJsonDocument::fromJson(out).object();
        if (status == QProcess::NormalExit && code == 0)
            m_rebootMessage = tr("Reboot started. The Deco units will be back in about two minutes.");
        else
            m_rebootMessage = tr("Reboot failed: %1").arg(result.value("error").toString(tr("unknown error")));
        emit rebootingChanged();
    });
    connect(&m_reboot, &QProcess::errorOccurred, this, [this](QProcess::ProcessError) {
        if (m_reboot.state() != QProcess::NotRunning) return;
        m_rebootMessage = tr("Could not run deco: %1").arg(m_reboot.errorString());
        emit rebootingChanged();
    });
    connect(&m_block, &QProcess::finished, this, [this](int code, QProcess::ExitStatus status) {
        const QJsonObject result = QJsonDocument::fromJson(m_block.readAllStandardOutput()).object();
        const bool ok = status == QProcess::NormalExit && code == 0;
        if (ok)
            m_blockMessage = m_blockVerb == "block" ? tr("%1 is blocked.").arg(m_blockName)
                                                    : tr("%1 is unblocked.").arg(m_blockName);
        else
            m_blockMessage = tr("Couldn't %1 %2: %3")
                                 .arg(m_blockVerb == "block" ? tr("block") : tr("unblock"), m_blockName,
                                      result.value("error").toString(tr("unknown error")));
        emit blockingChanged();
        reload();
    });
    connect(&m_block, &QProcess::errorOccurred, this, [this](QProcess::ProcessError) {
        if (m_block.state() != QProcess::NotRunning) return;
        m_blockMessage = tr("Could not run deco: %1").arg(m_block.errorString());
        emit blockingChanged();
    });

    // This computer's own MACs: the app hides Block for them, so a click
    // can't cut off the machine it's running on.
    for (const QNetworkInterface &i : QNetworkInterface::allInterfaces())
        if (!i.hardwareAddress().isEmpty())
            m_ownMacs << i.hardwareAddress().toUpper().replace(':', '-');
    reload();
}

void Backend::watch() {
    const auto paths = m_watcher.files() + m_watcher.directories();
    if (!paths.isEmpty())
        m_watcher.removePaths(paths);
    if (QFileInfo::exists(m_path))
        m_watcher.addPath(m_path);
    const QString dir = QFileInfo(m_path).absolutePath();
    if (QFileInfo::exists(dir))
        m_watcher.addPath(dir);
}

void Backend::reload() {
    watch();
    QFile file(m_path);
    if (!file.open(QIODevice::ReadOnly)) {
        if (m_state != NoService) {
            m_state = NoService;
            emit changed();
        }
        return;
    }
    applyStatus(file.read(4 * 1024 * 1024), QDateTime::currentSecsSinceEpoch());
}

void Backend::applyStatus(const QByteArray &json, qint64 now) {
    const QJsonObject d = QJsonDocument::fromJson(json).object();
    if (d.isEmpty())
        return;  // a half-written file; the next change brings a whole one

    m_updated = qint64(d.value("time").toDouble());
    m_interval = qBound(2.0, d.value("interval").toDouble(3), 60.0);
    m_error = clip(d.value("error"), 300);
    const bool ok = d.value("ok").toBool();
    // The service writes every few seconds, even when the Deco fails; an old
    // file means the service itself has stopped.
    const bool stale = m_updated > 0 && now - m_updated > qMax<qint64>(30, qint64(m_interval * 6));
    m_state = stale ? Stale : ok ? Ok : Failing;

    m_blockedError = clip(d.value("blocked_error"), 300);
    // "blocked_time" is set once the service has really read the list.
    if (d.contains("blocked") && d.value("blocked_time").toDouble() > 0) {
        m_blockedKnown = true;
        m_blocked.clear();
        const QJsonArray bl = d.value("blocked").toArray();
        for (int i = 0; i < bl.size() && i < 256; ++i) {
            const QJsonObject b = bl.at(i).toObject();
            m_blocked.append(QVariantMap{{"name", clip(b.value("name"), 64)},
                                         {"mac", clip(b.value("mac"), 20)},
                                         {"type", clip(b.value("type"), 24)}});
        }
    }

    if (ok) {
        m_down = positive(d.value("down_kbps"));
        m_up = positive(d.value("up_kbps"));

        m_clients.clear();
        const QJsonArray cl = d.value("clients").toArray();
        for (int i = 0; i < cl.size() && i < 256; ++i) {
            const QJsonObject c = cl.at(i).toObject();
            m_clients.append(QVariantMap{
                {"name", clip(c.value("name"), 64)},
                {"mac", clip(c.value("mac"), 20)},
                {"ip", clip(c.value("ip"), 40)},
                {"connection", clip(c.value("connection"), 16)},
                {"network", clip(c.value("network"), 16)},
                {"type", clip(c.value("type"), 24)},
                {"down", positive(c.value("down_kbps"))},
                {"up", positive(c.value("up_kbps"))},
                {"online", c.value("online").toBool(true)},
                {"isNew", c.value("new").toBool(false)},
            });
        }

        m_nodes.clear();
        const QJsonArray ns = d.value("nodes").toArray();
        for (int i = 0; i < ns.size() && i < 32; ++i) {
            const QJsonObject n = ns.at(i).toObject();
            m_nodes.append(QVariantMap{
                {"name", clip(n.value("name"), 40)},
                {"mac", clip(n.value("mac"), 20)},
                {"ip", clip(n.value("ip"), 40)},
                {"model", clip(n.value("model"), 24)},
                {"firmware", clip(n.value("firmware"), 48)},
                {"main", n.value("role").toString() == "master"},
                {"online", n.value("online").toBool(true)},
                {"internet", n.value("internet").toBool(true)},
            });
        }

        m_history.clear();
        const QJsonArray h = d.value("history").toArray();
        for (int i = qMax(0, int(h.size()) - 120); i < h.size(); ++i) {
            const QJsonArray p = h.at(i).toArray();
            // Wrapped in a QVariant: QList::append(QList) would splice the pair in flat.
            m_history.append(QVariant(QVariantList{positive(p.at(0)), positive(p.at(1))}));
        }

        const QJsonObject w = d.value("wan").toObject();
        m_wan = QVariantMap{{"ip", clip(w.value("ip"), 40)}, {"gateway", clip(w.value("gateway"), 40)},
                            {"dns1", clip(w.value("dns1"), 40)}, {"dns2", clip(w.value("dns2"), 40)},
                            {"type", clip(w.value("type"), 24)}};
        const QJsonObject p = d.value("perf").toObject();
        m_cpu = p.contains("cpu") ? qBound(0, p.value("cpu").toInt(), 100) : -1;
        m_mem = p.contains("mem") ? qBound(0, p.value("mem").toInt(), 100) : -1;
    }
    emit changed();
}

void Backend::reboot(const QStringList &macs) {
    if (rebooting())
        return;
    if (m_deco.isEmpty()) {
        m_rebootMessage = tr("The deco command is not installed.");
        emit rebootingChanged();
        return;
    }
    m_rebootMessage.clear();
    QStringList args{"reboot"};
    for (const QString &mac : macs)
        args << mac.left(20);
    m_reboot.start(m_deco, args);
    emit rebootingChanged();
}

void Backend::startService() {
    // Only on the user's click: enabling a background service is their call.
    QProcess::startDetached("systemctl", {"--user", "enable", "--now", "deco-monitor.service"});
    QTimer::singleShot(4000, this, &Backend::reload);
}

void Backend::runBlock(const QString &verb, const QString &mac, const QString &name) {
    if (blocking())
        return;
    if (m_deco.isEmpty()) {
        m_blockMessage = tr("The deco command is not installed.");
        emit blockingChanged();
        return;
    }
    m_blockVerb = verb;
    m_blockName = name.left(64);
    m_blockMessage.clear();
    m_block.start(m_deco, {verb, mac.left(20)});
    emit blockingChanged();
}

void Backend::block(const QString &mac, const QString &name) { runBlock("block", mac, name); }
void Backend::unblock(const QString &mac, const QString &name) { runBlock("unblock", mac, name); }

void Backend::copy(const QString &text) {
    if (auto *clipboard = QGuiApplication::clipboard())
        clipboard->setText(text.left(64));
}
