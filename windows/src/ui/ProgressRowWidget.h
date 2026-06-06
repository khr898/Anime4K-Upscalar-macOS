#pragma once

#include <QWidget>
#include <QLabel>
#include <QProgressBar>
#include <QVBoxLayout>
#include <QHBoxLayout>
#include "../models/Models.h"
#include "../models/CompressModels.h"
#include "../models/StreamOptimizeModels.h"

class ProgressRowWidget : public QWidget {
    Q_OBJECT
public:
    explicit ProgressRowWidget(ProcessingJob* job, QWidget* parent = nullptr);
    explicit ProgressRowWidget(CompressJob* job, QWidget* parent = nullptr);
    explicit ProgressRowWidget(StreamOptimizeJob* job, QWidget* parent = nullptr);

private slots:
    void updateUI();

private:
    void initUI(const QString& fileName, JobState state, double progress, const QString& detailText);

    // Pointers to potential jobs (only one will be set)
    ProcessingJob* m_processingJob = nullptr;
    CompressJob* m_compressJob = nullptr;
    StreamOptimizeJob* m_streamOptimizeJob = nullptr;

    QLabel* m_fileNameLabel;
    QProgressBar* m_progressBar;
    QLabel* m_detailsLabel;
    QLabel* m_statusBadge;
};
