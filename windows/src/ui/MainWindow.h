#pragma once

#include <QMainWindow>
#include <QTabWidget>
#include <QVBoxLayout>
#include <QLabel>
#include <QPushButton>
#include "../viewmodels/AppViewModel.h"
#include "../viewmodels/CompressViewModel.h"
#include "../viewmodels/StreamOptimizeViewModel.h"

class MainWindow : public QMainWindow {
    Q_OBJECT
public:
    explicit MainWindow(QWidget* parent = nullptr);
    ~MainWindow() override = default;

private slots:
    void syncSelectedTab(int index);
    void updateDependencyAlert();

private:
    void initUI();

    // ViewModels
    AppViewModel* m_appViewModel;
    CompressViewModel* m_compressViewModel;
    StreamOptimizeViewModel* m_streamOptimizeViewModel;

    // UI Widgets
    QWidget* m_centralWidget;
    QVBoxLayout* m_mainLayout;

    // Alert Banner
    QWidget* m_alertBanner;
    QLabel* m_alertLabel;
    QPushButton* m_alertDismissBtn;

    QTabWidget* m_tabWidget;
};
