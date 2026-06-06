#include "MainWindow.h"
#include "UpscaleTab.h"
#include "CompressTab.h"
#include "StreamOptimizeTab.h"
#include "QualityTuneTab.h"
#include <QIcon>

MainWindow::MainWindow(QWidget* parent)
    : QMainWindow(parent)
{
    // Initialize all viewmodels
    m_appViewModel = new AppViewModel(this);
    m_compressViewModel = new CompressViewModel(this);
    m_streamOptimizeViewModel = new StreamOptimizeViewModel(this);

    initUI();

    // Listen to dependency alert changes
    connect(m_appViewModel, &AppViewModel::dependencyAlertChanged, this, &MainWindow::updateDependencyAlert);
    updateDependencyAlert();
}

void MainWindow::initUI() {
    setWindowTitle("Anime4K Upscaler & Compressor");
    setWindowIcon(QIcon(":/icons/app_icon.png"));
    resize(1024, 768);

    m_centralWidget = new QWidget(this);
    m_mainLayout = new QVBoxLayout(m_centralWidget);
    m_mainLayout->setContentsMargins(10, 10, 10, 10);
    m_mainLayout->setSpacing(8);

    // Dependency alert banner at the top
    m_alertBanner = new QWidget(this);
    m_alertBanner->setStyleSheet(
        "QWidget {"
        "  background-color: #ffefe5;"
        "  border: 1px solid #ffcfb3;"
        "  border-radius: 6px;"
        "}"
    );
    auto* alertLayout = new QHBoxLayout(m_alertBanner);
    alertLayout->setContentsMargins(12, 8, 12, 8);

    m_alertLabel = new QLabel(this);
    m_alertLabel->setStyleSheet("color: #d15b00; font-weight: 500; border: none; background: transparent;");
    m_alertLabel->setWordWrap(true);

    m_alertDismissBtn = new QPushButton("Dismiss", this);
    m_alertDismissBtn->setStyleSheet(
        "QPushButton {"
        "  background-color: #ffcfb3;"
        "  color: #d15b00;"
        "  border: none;"
        "  font-weight: bold;"
        "  border-radius: 4px;"
        "  padding: 4px 8px;"
        "}"
        "QPushButton:hover {"
        "  background-color: #ffb894;"
        "}"
    );
    
    alertLayout->addWidget(m_alertLabel, 1);
    alertLayout->addWidget(m_alertDismissBtn);

    m_mainLayout->addWidget(m_alertBanner);
    m_alertBanner->setVisible(false);

    // Tab Widget setup
    m_tabWidget = new QTabWidget(this);

    auto* upscaleTab = new UpscaleTab(m_appViewModel, m_tabWidget);
    auto* compressTab = new CompressTab(m_compressViewModel, m_tabWidget);
    auto* streamOptimizeTab = new StreamOptimizeTab(m_streamOptimizeViewModel, m_tabWidget);
    auto* qualityTuneTab = new QualityTuneTab(m_appViewModel, m_tabWidget);

    m_tabWidget->addTab(upscaleTab, QIcon(":/icons/wand.svg"), "Upscale");
    m_tabWidget->addTab(compressTab, QIcon(":/icons/archive.svg"), "Compress");
    m_tabWidget->addTab(streamOptimizeTab, QIcon(":/icons/globe.svg"), "Stream Optimize");
    m_tabWidget->addTab(qualityTuneTab, QIcon(":/icons/sliders.svg"), "Quality Tune");

    m_mainLayout->addWidget(m_tabWidget);
    setCentralWidget(m_centralWidget);

    // Connections
    connect(m_tabWidget, &QTabWidget::currentChanged, this, &MainWindow::syncSelectedTab);
    connect(m_alertDismissBtn, &QPushButton::clicked, this, [this]() {
        m_appViewModel->setShowDependencyAlert(false);
    });
}

void MainWindow::syncSelectedTab(int index) {
    if (index == 0) {
        m_appViewModel->setSelectedMainTab(AppViewModel::MainTab::Upscale);
    } else if (index == 1) {
        m_appViewModel->setSelectedMainTab(AppViewModel::MainTab::Compress);
    } else if (index == 2) {
        m_appViewModel->setSelectedMainTab(AppViewModel::MainTab::StreamOptimize);
    } else if (index == 3) {
        m_appViewModel->setSelectedMainTab(AppViewModel::MainTab::QualityTune);
    }
}

void MainWindow::updateDependencyAlert() {
    bool showAlert = m_appViewModel->showDependencyAlert();
    const auto& errors = m_appViewModel->dependencyErrors();

    if (showAlert && !errors.isEmpty()) {
        m_alertLabel->setText("Dependency Issue: " + errors.join(" "));
        m_alertBanner->setVisible(true);
    } else {
        m_alertBanner->setVisible(false);
    }
}
