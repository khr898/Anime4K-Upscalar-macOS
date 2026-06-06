#pragma once

#include <QString>
#include <QStringList>
#include <QProcessEnvironment>

class FFmpegLocator {
public:
    static QString ffmpegPath();
    static QString ffprobePath();
    static QString realesrganPath();
    static QString realesrganModelsDirectory();
    static QString shaderDirectory();

    static QStringList validateDependencies();
    static bool isFFmpegExecutable();
    static bool isRealesrganExecutable();

    static QProcessEnvironment processEnvironment();
};
