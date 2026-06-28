#pragma once
#include <QString>
#include <QStringList>
#include <functional>

class IPickerService {
public:
    virtual ~IPickerService() = default;
    virtual void pickFiles(const QString& title, const QString& filter,
                           std::function<void(QStringList)> done) = 0;
    virtual void pickDirectory(const QString& title, const QString& startDir,
                               std::function<void(QString)> done) = 0;
};
