#include <QDir>
#include <QFile>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QtTest>

#include "backend.h"
#include "theme.h"
#include "translator.h"

class DecomonTests : public QObject {
    Q_OBJECT

private slots:
    void missingFileMeansNoService()
    {
        QTemporaryDir dir;
        Backend backend(dir.filePath("status.json"), "/bin/false");
        QCOMPARE(backend.state(), Backend::NoService);
    }

    void parsesStatus()
    {
        QTemporaryDir dir;
        Backend backend(dir.filePath("status.json"), "/bin/false");
        backend.applyStatus(R"({"ok":true,"time":1000,"interval":3,"down_kbps":1500,"up_kbps":20,
            "clients":[{"name":"Phone","mac":"AA","ip":"192.168.68.5","connection":"5 GHz",
                        "down_kbps":1500,"up_kbps":20,"new":true}],
            "nodes":[{"name":"Living Room","mac":"BB","role":"master","online":true,"internet":false}],
            "history":[[1,2],[3,4]],"perf":{"cpu":12,"mem":60},"wan":{"ip":"1.2.3.4"}})", 1001);
        QCOMPARE(backend.state(), Backend::Ok);
        QCOMPARE(backend.downKbps(), 1500.0);
        QCOMPARE(backend.clients().size(), 1);
        QCOMPARE(backend.clients().first().toMap().value("isNew").toBool(), true);
        QCOMPARE(backend.nodes().first().toMap().value("main").toBool(), true);
        QCOMPARE(backend.nodes().first().toMap().value("internet").toBool(), false);
        // Each history point stays a [down, up] pair rather than being flattened.
        QCOMPARE(backend.history().size(), 2);
        QCOMPARE(backend.history().at(1).toList().at(1).toDouble(), 4.0);
        QCOMPARE(backend.decoCpu(), 12);
        QCOMPARE(backend.wan().value("ip").toString(), QString("1.2.3.4"));
    }

    void failureKeepsLastData()
    {
        QTemporaryDir dir;
        Backend backend(dir.filePath("status.json"), "/bin/false");
        backend.applyStatus(R"({"ok":true,"time":1000,"down_kbps":10,"clients":[{"name":"A"}]})", 1000);
        backend.applyStatus(R"({"ok":false,"time":1003,"error":"cannot reach Deco"})", 1003);
        QCOMPARE(backend.state(), Backend::Failing);
        QCOMPARE(backend.error(), QString("cannot reach Deco"));
        QCOMPARE(backend.clients().size(), 1);
    }

    void oldFileIsStale()
    {
        QTemporaryDir dir;
        Backend backend(dir.filePath("status.json"), "/bin/false");
        backend.applyStatus(R"({"ok":true,"time":1000,"interval":3})", 1000 + 120);
        QCOMPARE(backend.state(), Backend::Stale);
    }

    void ignoresGarbage()
    {
        QTemporaryDir dir;
        Backend backend(dir.filePath("status.json"), "/bin/false");
        QSignalSpy spy(&backend, &Backend::changed);
        backend.applyStatus("{not json", 1000);
        QCOMPARE(spy.count(), 0);
    }

    void longNamesAreClipped()
    {
        QTemporaryDir dir;
        Backend backend(dir.filePath("status.json"), "/bin/false");
        const QByteArray name(500, 'x');
        backend.applyStatus(R"({"ok":true,"time":1,"clients":[{"name":")" + name + R"("}]})", 1);
        QCOMPARE(backend.clients().first().toMap().value("name").toString().size(), 64);
    }

    void rebootReportsFailure()
    {
        QTemporaryDir dir;
        Backend backend(dir.filePath("status.json"), "/bin/false");
        QSignalSpy spy(&backend, &Backend::rebootingChanged);
        backend.reboot({"BB"});
        QTRY_VERIFY(!backend.rebooting());
        QVERIFY(backend.rebootMessage().startsWith("Reboot failed"));
    }

    void parsesBlockedList()
    {
        QTemporaryDir dir;
        Backend backend(dir.filePath("status.json"), "/bin/false");
        backend.applyStatus(R"({"ok":true,"time":1,"blocked_time":1,"blocked":[{"mac":"02-00-00-00-00-01","name":"Laptop","type":"pc"}]})", 1);
        QVERIFY(backend.blockedKnown());
        QCOMPARE(backend.blocked().size(), 1);
        QCOMPARE(backend.blocked().first().toMap().value("name").toString(), QString("Laptop"));
        // A status written before the first blocked-list poll keeps the last list.
        backend.applyStatus(R"({"ok":true,"time":2})", 2);
        QCOMPARE(backend.blocked().size(), 1);
    }

    void blockReportsFailure()
    {
        QTemporaryDir dir;
        Backend backend(dir.filePath("status.json"), "/bin/false");
        backend.block("AA-BB-CC-DD-EE-FF", "Phone");
        QTRY_VERIFY(!backend.blocking());
        QVERIFY(backend.blockMessage().startsWith("Couldn't block Phone"));
    }

    void themeFallsBack()
    {
        QTemporaryDir dir;
        Theme theme(dir.path());
        QCOMPARE(theme.accent(), QString("#FFD60A"));
        QCOMPARE(theme.accentForeground(), QString("black"));
    }

    void themeReadsAccent()
    {
        QTemporaryDir dir;
        QDir(dir.path()).mkpath("theme");
        QFile colors(dir.path() + "/theme/colors.toml");
        QVERIFY(colors.open(QIODevice::WriteOnly));
        colors.write("accent = \"#112233\"\n");
        colors.close();
        Theme theme(dir.path());
        QCOMPARE(theme.accent(), QString("#112233"));
        QCOMPARE(theme.accentForeground(), QString("white"));
    }

    void translatorFallsBackToEnglish()
    {
        QTemporaryDir dir;
        Translator translator(dir.path() + "/language", dir.path());
        QCOMPARE(translator.language(), QString("en"));
        QVERIFY(translator.translate("Main", "Devices").isNull());
    }
};

QTEST_MAIN(DecomonTests)
#include "decomon_tests.moc"
