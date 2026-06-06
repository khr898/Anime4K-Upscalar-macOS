#include "FFmpegLocator.h"
#include <QCoreApplication>
#include <QFileInfo>
#include <QDir>
#include <QStandardPaths>

#include <QtGlobal>

static QString getArchSubdir() {
#if defined(Q_PROCESSOR_ARM_64)
    return "vendor/arm64/";
#elif defined(Q_PROCESSOR_X86_64)
    return "vendor/x64/";
#else
    return "vendor/";
#endif
}

static QString findUpwardFileOrVendor(const QString& filename) {
    QDir dir(QCoreApplication::applicationDirPath());
    QString archSubdir = getArchSubdir();
    for (int i = 0; i < 6; ++i) {
        // Check direct
        if (dir.exists(filename)) {
            return QDir::cleanPath(dir.filePath(filename));
        }
        // Check in arch-specific vendor
        QString archPath = archSubdir + filename;
        if (dir.exists(archPath)) {
            return QDir::cleanPath(dir.filePath(archPath));
        }
        // Check in default vendor
        QString vendorPath = "vendor/" + filename;
        if (dir.exists(vendorPath)) {
            return QDir::cleanPath(dir.filePath(vendorPath));
        }
        // cdUp
        if (!dir.cdUp()) {
            break;
        }
    }
    return QString();
}

static QString findUpwardDir(const QString& dirname) {
    QDir dir(QCoreApplication::applicationDirPath());
    for (int i = 0; i < 6; ++i) {
        QFileInfo fi(dir.filePath(dirname));
        if (fi.exists() && fi.isDir()) {
            return QDir::cleanPath(dir.filePath(dirname));
        }
        if (!dir.cdUp()) {
            break;
        }
    }
    return QString();
}

QString FFmpegLocator::ffmpegPath() {
    // 1. Check system PATH
    QString sysPath = QStandardPaths::findExecutable("ffmpeg");
    if (!sysPath.isEmpty()) {
        return QDir::cleanPath(sysPath);
    }

    // 2. Check upward directories
    QString found = findUpwardFileOrVendor("ffmpeg.exe");
    if (!found.isEmpty()) {
        return found;
    }

    return QDir(QCoreApplication::applicationDirPath()).filePath("ffmpeg.exe"); // Fallback
}

QString FFmpegLocator::ffprobePath() {
    // 1. Check system PATH
    QString sysPath = QStandardPaths::findExecutable("ffprobe");
    if (!sysPath.isEmpty()) {
        return QDir::cleanPath(sysPath);
    }

    // 2. Check upward directories
    QString found = findUpwardFileOrVendor("ffprobe.exe");
    if (!found.isEmpty()) {
        return found;
    }

    return QDir(QCoreApplication::applicationDirPath()).filePath("ffprobe.exe"); // Fallback
}

QString FFmpegLocator::realesrganPath() {
    // 1. Check system PATH
    QString sysPath = QStandardPaths::findExecutable("realesrgan-ncnn-vulkan");
    if (!sysPath.isEmpty()) {
        return QDir::cleanPath(sysPath);
    }

    // 2. Check upward directories
    QString found = findUpwardFileOrVendor("realesrgan-ncnn-vulkan.exe");
    if (!found.isEmpty()) {
        return found;
    }

    return QDir(QCoreApplication::applicationDirPath()).filePath("realesrgan-ncnn-vulkan.exe"); // Fallback
}

QString FFmpegLocator::realesrganModelsDirectory() {
    QString exePath = realesrganPath();
    QFileInfo fi(exePath);
    QDir dir = fi.dir();
    if (dir.exists("models")) {
        return QDir::cleanPath(dir.filePath("models"));
    }
    QDir appDir(QCoreApplication::applicationDirPath());
    if (appDir.exists("models")) {
        return QDir::cleanPath(appDir.filePath("models"));
    }
    // Check in arch subdir
    QString archSubdir = getArchSubdir();
    if (appDir.exists(archSubdir + "models")) {
        return QDir::cleanPath(appDir.filePath(archSubdir + "models"));
    }
    // Check upward directories for models
    QString found = findUpwardDir("models");
    if (!found.isEmpty()) {
        return found;
    }
    return QDir(QCoreApplication::applicationDirPath()).filePath("models");
}

QString FFmpegLocator::shaderDirectory() {
    // Check upward directories
    QString found = findUpwardDir("shaders");
    if (!found.isEmpty()) {
        return found;
    }

    return QDir(QCoreApplication::applicationDirPath()).filePath("shaders"); // Fallback
}

QStringList FFmpegLocator::validateDependencies() {
    QStringList missing;
    if (!QFileInfo::exists(ffmpegPath())) {
        missing.append("ffmpeg.exe");
    }
    if (!QFileInfo::exists(ffprobePath())) {
        missing.append("ffprobe.exe");
    }
    if (!QFileInfo::exists(realesrganPath())) {
        missing.append("realesrgan-ncnn-vulkan.exe");
    }
    QString modelsDir = realesrganModelsDirectory();
    if (!QFileInfo::exists(modelsDir) || !QFileInfo(modelsDir).isDir()) {
        missing.append("models directory (Real-ESRGAN)");
    }
    QString shaderDir = shaderDirectory();
    if (!QFileInfo::exists(shaderDir) || !QFileInfo(shaderDir).isDir()) {
        missing.append("shaders directory");
    }
    return missing;
}

bool FFmpegLocator::isFFmpegExecutable() {
    QFileInfo ffmpeg(ffmpegPath());
    return ffmpeg.exists() && ffmpeg.isFile();
}

bool FFmpegLocator::isRealesrganExecutable() {
    QFileInfo re(realesrganPath());
    return re.exists() && re.isFile();
}

QProcessEnvironment FFmpegLocator::processEnvironment() {
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    // Add app directory to path so FFmpeg can find any bundled DLLs
    QString appDir = QCoreApplication::applicationDirPath();
    env.insert("PATH", appDir + ";" + env.value("PATH"));
    // Prevent FFmpeg from expecting interactive inputs
    env.insert("FFREPORT", "");
    return env;
}
