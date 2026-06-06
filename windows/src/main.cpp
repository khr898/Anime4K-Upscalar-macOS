#include <QApplication>
#include <QIcon>
#include "ui/MainWindow.h"
#include "ui/StyleSheet.h"

int main(int argc, char *argv[]) {
    QApplication app(argc, argv);
    app.setApplicationName("Anime4K Upscaler");
    app.setApplicationVersion("1.0.0");
    app.setOrganizationName("Anime4K");
    app.setWindowIcon(QIcon(":/icons/app_icon.png"));

    // Apply global modern stylesheet
    app.setStyleSheet(GLOBAL_STYLESHEET);

    MainWindow window;
    window.show();

    return app.exec();
}
