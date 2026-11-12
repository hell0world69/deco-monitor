#pragma once

#include <QFileSystemWatcher>
#include <QObject>
#include <QProcess>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

// Reads the status file the deco-monitor service writes, and runs `deco` for
// the one thing the app changes on the network: rebooting Deco units. The app
// never logs in to the Deco itself, because the Deco allows a single local
// session and the service already holds it.
class Backend : public QObject {
    Q_OBJECT
    Q_PROPERTY(State state READ state NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
    Q_PROPERTY(double downKbps READ downKbps NOTIFY changed)
    Q_PROPERTY(double upKbps READ upKbps NOTIFY changed)
    Q_PROPERTY(QVariantList clients READ clients NOTIFY changed)
    Q_PROPERTY(QVariantList nodes READ nodes NOTIFY changed)
    Q_PROPERTY(QVariantList history READ history NOTIFY changed)
    Q_PROPERTY(QVariantMap wan READ wan NOTIFY changed)
    Q_PROPERTY(int decoCpu READ decoCpu NOTIFY changed)
    Q_PROPERTY(int decoMem READ decoMem NOTIFY changed)
    Q_PROPERTY(qint64 updated READ updated NOTIFY changed)
    Q_PROPERTY(double interval READ interval NOTIFY changed)
    Q_PROPERTY(bool rebooting READ rebooting NOTIFY rebootingChanged)
    Q_PROPERTY(QString rebootMessage READ rebootMessage NOTIFY rebootingChanged)

public:
    enum State { NoService, Ok, Failing, Stale };
    Q_ENUM(State)

    explicit Backend(const QString &statusPath = {}, const QString &decoCommand = {}, QObject *parent = nullptr);

    State state() const { return m_state; }
    QString error() const { return m_error; }
    double downKbps() const { return m_down; }
    double upKbps() const { return m_up; }
    QVariantList clients() const { return m_clients; }
    QVariantList nodes() const { return m_nodes; }
    QVariantList history() const { return m_history; }
    QVariantMap wan() const { return m_wan; }
    int decoCpu() const { return m_cpu; }
    int decoMem() const { return m_mem; }
    qint64 updated() const { return m_updated; }
    double interval() const { return m_interval; }
    bool rebooting() const { return m_reboot.state() != QProcess::NotRunning; }
    QString rebootMessage() const { return m_rebootMessage; }

    // Parses one status document; public so tests can feed it directly.
    void applyStatus(const QByteArray &json, qint64 nowSeconds);

    Q_INVOKABLE void reload();
    Q_INVOKABLE void reboot(const QStringList &macs);
    Q_INVOKABLE void startService();

signals:
    void changed();
    void rebootingChanged();

private:
    void watch();

    QString m_path;
    QString m_deco;
    QFileSystemWatcher m_watcher;
    QTimer m_poll;
    QProcess m_reboot;

    State m_state = NoService;
    QString m_error;
    double m_down = 0, m_up = 0, m_interval = 3;
    QVariantList m_clients, m_nodes, m_history;
    QVariantMap m_wan;
    int m_cpu = -1, m_mem = -1;
    qint64 m_updated = 0;
    QString m_rebootMessage;
};
