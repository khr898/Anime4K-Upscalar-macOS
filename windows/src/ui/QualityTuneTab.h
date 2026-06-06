#pragma once

#include <QWidget>
#include <QLabel>
#include <QLineEdit>
#include <QPushButton>
#include <QComboBox>
#include <QSpinBox>
#include <QDoubleSpinBox>
#include <QTableWidget>
#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QGridLayout>
#include <QGroupBox>
#include "../viewmodels/AppViewModel.h"

class QualityTuneTab : public QWidget {
    Q_OBJECT
public:
    explicit QualityTuneTab(AppViewModel* viewModel, QWidget* parent = nullptr);

private slots:
    void updateState();
    void updateCandidates();
    void onStartScanClicked();

private:
    void initUI();

    AppViewModel* m_viewModel;

    QLineEdit* m_inputFileEdit;
    QPushButton* m_inputFileBrowseBtn;

    QComboBox* m_codecCombo;
    QSpinBox* m_rangeStartSpin;
    QSpinBox* m_rangeEndSpin;
    QSpinBox* m_stepSpin;
    QSpinBox* m_sampleSecsSpin;
    QDoubleSpinBox* m_targetSSIMSpin;

    QPushButton* m_startScanBtn;
    QLabel* m_statusLabel;

    QTableWidget* m_candidatesTable;
};
