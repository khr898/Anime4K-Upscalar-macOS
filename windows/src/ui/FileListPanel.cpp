#include "FileListPanel.h"
#include <QDragEnterEvent>
#include <QDropEvent>
#include <QMimeData>
#include <QUrl>
#include <QIcon>
#include <QHBoxLayout>

class FileListItemWidget : public QWidget {
public:
    QLabel* nameLabel;
    QLabel* infoLabel;
    QLabel* iconLabel;

    FileListItemWidget(const VideoFile& file, QWidget* parent = nullptr) : QWidget(parent) {
        auto* mainLayout = new QHBoxLayout(this);
        mainLayout->setContentsMargins(4, 4, 4, 4);
        mainLayout->setSpacing(8);

        iconLabel = new QLabel(this);
        iconLabel->setPixmap(QIcon(":/icons/video.svg").pixmap(16, 16));
        mainLayout->addWidget(iconLabel);

        auto* textLayout = new QVBoxLayout();
        textLayout->setSpacing(2);

        nameLabel = new QLabel(file.fileName, this);
        nameLabel->setStyleSheet("font-weight: bold; font-size: 13px; color: #1d1d1f;");

        QString duration = file.durationSeconds.has_value() ? file.formattedDuration() : "00:00:00";
        infoLabel = new QLabel(QString("%1 • %2 • %3")
            .arg(file.formattedFileSize())
            .arg(duration)
            .arg(file.resolutionString()), this);
        infoLabel->setStyleSheet("font-size: 11px; color: #86868b;");

        textLayout->addWidget(nameLabel);
        textLayout->addWidget(infoLabel);
        mainLayout->addLayout(textLayout, 1);

        setAutoFillBackground(false);
        setStyleSheet("background: transparent;");
    }

    void setSelected(bool selected) {
        if (selected) {
            nameLabel->setStyleSheet("font-weight: bold; font-size: 13px; color: #ffffff;");
            infoLabel->setStyleSheet("font-size: 11px; color: #e5e5ea;");
        } else {
            nameLabel->setStyleSheet("font-weight: bold; font-size: 13px; color: #1d1d1f;");
            infoLabel->setStyleSheet("font-size: 11px; color: #86868b;");
        }
    }
};

FileListPanel::FileListPanel(AppViewModel* viewModel, QWidget* parent)
    : QWidget(parent)
    , m_appViewModel(viewModel)
{
    initUI();
    connect(m_appViewModel, &AppViewModel::filesChanged, this, &FileListPanel::refreshList);
    connect(m_appViewModel, &AppViewModel::selectedFileChanged, this, &FileListPanel::refreshList);
    refreshList();
}

FileListPanel::FileListPanel(CompressViewModel* viewModel, QWidget* parent)
    : QWidget(parent)
    , m_compressViewModel(viewModel)
{
    initUI();
    connect(m_compressViewModel, &CompressViewModel::filesChanged, this, &FileListPanel::refreshList);
    connect(m_compressViewModel, &CompressViewModel::selectedFileChanged, this, &FileListPanel::refreshList);
    refreshList();
}

void FileListPanel::initUI() {
    setAcceptDrops(true);
    setMinimumWidth(260);

    auto* layout = new QVBoxLayout(this);
    layout->setContentsMargins(12, 12, 12, 12);
    layout->setSpacing(8);

    m_headerLabel = new QLabel("Video Files (0)", this);
    m_headerLabel->setStyleSheet("font-weight: bold; font-size: 14px; color: #1d1d1f;");
    layout->addWidget(m_headerLabel);

    m_listWidget = new QListWidget(this);
    m_listWidget->setSelectionMode(QAbstractItemView::SingleSelection);
    layout->addWidget(m_listWidget);

    connect(m_listWidget, &QListWidget::itemSelectionChanged, this, &FileListPanel::handleSelectionChanged);

    // Footer Buttons layout
    auto* buttonLayout = new QHBoxLayout();
    buttonLayout->setSpacing(6);

    m_addButton = new QPushButton("Add", this);
    m_addButton->setIcon(QIcon(":/icons/plus.svg"));
    m_removeButton = new QPushButton("Remove", this);
    m_removeButton->setIcon(QIcon(":/icons/trash.svg"));
    m_clearButton = new QPushButton("Clear", this);
    m_clearButton->setIcon(QIcon(":/icons/broom.svg"));

    buttonLayout->addWidget(m_addButton);
    buttonLayout->addWidget(m_removeButton);
    buttonLayout->addWidget(m_clearButton);

    layout->addLayout(buttonLayout);

    connect(m_addButton, &QPushButton::clicked, this, &FileListPanel::onAddClicked);
    connect(m_removeButton, &QPushButton::clicked, this, &FileListPanel::onRemoveClicked);
    connect(m_clearButton, &QPushButton::clicked, this, &FileListPanel::onClearClicked);
}

void FileListPanel::refreshList() {
    // Temporarily block signals to avoid recursion while rebuilding
    m_listWidget->blockSignals(true);
    m_listWidget->clear();
    m_itemIds.clear();

    const QVector<VideoFile>& files = m_appViewModel ? m_appViewModel->files() : m_compressViewModel->files();
    QUuid selectedId = m_appViewModel ? m_appViewModel->selectedFileID() : m_compressViewModel->selectedFileID();

    m_headerLabel->setText(QString("Video Files (%1)").arg(files.size()));

    int selectedRow = -1;
    for (int i = 0; i < files.size(); ++i) {
        const auto& file = files[i];
        m_itemIds.append(file.id);

        auto* item = new QListWidgetItem(m_listWidget);
        item->setSizeHint(QSize(0, 56));
        m_listWidget->addItem(item);

        auto* widget = new FileListItemWidget(file, m_listWidget);
        m_listWidget->setItemWidget(item, widget);

        if (file.id == selectedId) {
            selectedRow = i;
        }
    }

    if (selectedRow >= 0) {
        m_listWidget->setCurrentRow(selectedRow);
    } else if (m_listWidget->count() > 0) {
        m_listWidget->setCurrentRow(0);
    }

    updateItemStyles();
    m_listWidget->blockSignals(false);
}

void FileListPanel::handleSelectionChanged() {
    int row = m_listWidget->currentRow();
    if (row >= 0 && row < m_itemIds.size()) {
        QUuid id = m_itemIds[row];
        if (m_appViewModel) {
            m_appViewModel->setSelectedFileID(id);
        } else if (m_compressViewModel) {
            m_compressViewModel->setSelectedFileID(id);
        }
    }
    updateItemStyles();
}

void FileListPanel::updateItemStyles() {
    for (int i = 0; i < m_listWidget->count(); ++i) {
        QListWidgetItem* item = m_listWidget->item(i);
        auto* widget = static_cast<FileListItemWidget*>(m_listWidget->itemWidget(item));
        if (widget) {
            widget->setSelected(item->isSelected());
        }
    }
}

void FileListPanel::onAddClicked() {
    if (m_appViewModel) {
        m_appViewModel->addFiles();
    } else if (m_compressViewModel) {
        m_compressViewModel->addFiles();
    }
}

void FileListPanel::onRemoveClicked() {
    if (m_appViewModel) {
        m_appViewModel->removeSelectedFile();
    } else if (m_compressViewModel) {
        int row = m_listWidget->currentRow();
        if (row >= 0 && row < m_itemIds.size()) {
            m_compressViewModel->removeFile(m_itemIds[row]);
        }
    }
}

void FileListPanel::onClearClicked() {
    if (m_appViewModel) {
        m_appViewModel->removeAllFiles();
    } else if (m_compressViewModel) {
        m_compressViewModel->removeAllFiles();
    }
}

void FileListPanel::dragEnterEvent(QDragEnterEvent* event) {
    if (event->mimeData()->hasUrls()) {
        event->acceptProposedAction();
    }
}

void FileListPanel::dragMoveEvent(QDragMoveEvent* event) {
    if (event->mimeData()->hasUrls()) {
        event->acceptProposedAction();
    }
}

void FileListPanel::dropEvent(QDropEvent* event) {
    if (event->mimeData()->hasUrls()) {
        QStringList paths;
        for (const QUrl& url : event->mimeData()->urls()) {
            if (url.isLocalFile()) {
                paths.append(url.toLocalFile());
            }
        }
        if (!paths.isEmpty()) {
            if (m_appViewModel) {
                m_appViewModel->addFilesFromDrop(paths);
            } else if (m_compressViewModel) {
                m_compressViewModel->addFilesFromDrop(paths);
            }
        }
        event->acceptProposedAction();
    }
}
