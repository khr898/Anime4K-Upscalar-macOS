#pragma once

#include <QWidget>
#include <QListWidget>
#include <QLabel>
#include <QPushButton>
#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QUuid>
#include "../models/Models.h"
#include "../viewmodels/AppViewModel.h"
#include "../viewmodels/CompressViewModel.h"

class FileListPanel : public QWidget {
    Q_OBJECT
public:
    explicit FileListPanel(AppViewModel* viewModel, QWidget* parent = nullptr);
    explicit FileListPanel(CompressViewModel* viewModel, QWidget* parent = nullptr);

signals:
    void filesDropped(const QStringList& paths);

protected:
    void dragEnterEvent(QDragEnterEvent* event) override;
    void dragMoveEvent(QDragMoveEvent* event) override;
    void dropEvent(QDropEvent* event) override;

private slots:
    void refreshList();
    void handleSelectionChanged();
    void onAddClicked();
    void onRemoveClicked();
    void onClearClicked();

private:
    void initUI();
    void updateItemStyles();

    AppViewModel* m_appViewModel = nullptr;
    CompressViewModel* m_compressViewModel = nullptr;

    QLabel* m_headerLabel;
    QListWidget* m_listWidget;
    QPushButton* m_addButton;
    QPushButton* m_removeButton;
    QPushButton* m_clearButton;

    // Track list item IDs
    QVector<QUuid> m_itemIds;
};
