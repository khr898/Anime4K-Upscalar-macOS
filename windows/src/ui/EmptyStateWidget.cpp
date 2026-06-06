#include "EmptyStateWidget.h"
#include <QDragEnterEvent>
#include <QDropEvent>
#include <QMimeData>
#include <QPainter>
#include <QPen>
#include <QUrl>
#include <QIcon>

EmptyStateWidget::EmptyStateWidget(const QString& title, const QString& description, const QString& buttonText, QWidget* parent)
    : QWidget(parent)
{
    setAcceptDrops(true);

    auto* layout = new QVBoxLayout(this);
    layout->setContentsMargins(40, 40, 40, 40);
    layout->setSpacing(16);
    layout->setAlignment(Qt::AlignCenter);

    m_iconLabel = new QLabel(this);
    m_iconLabel->setPixmap(QIcon(":/icons/inbox.svg").pixmap(48, 48));
    m_iconLabel->setAlignment(Qt::AlignCenter);

    m_titleLabel = new QLabel(title, this);
    m_titleLabel->setAlignment(Qt::AlignCenter);
    m_titleLabel->setStyleSheet("font-size: 16px; font-weight: bold; color: #1d1d1f;");

    m_descriptionLabel = new QLabel(description, this);
    m_descriptionLabel->setAlignment(Qt::AlignCenter);
    m_descriptionLabel->setWordWrap(true);
    m_descriptionLabel->setStyleSheet("font-size: 13px; color: #86868b;");

    m_addButton = new QPushButton(buttonText, this);
    m_addButton->setStyleSheet(
        "QPushButton {"
        "  background-color: #007aff;"
        "  border: 1px solid #0071e3;"
        "  color: #ffffff;"
        "  font-weight: bold;"
        "  padding: 8px 16px;"
        "  border-radius: 6px;"
        "}"
        "QPushButton:hover {"
        "  background-color: #0071e3;"
        "}"
        "QPushButton:pressed {"
        "  background-color: #0062c3;"
        "}"
    );

    layout->addWidget(m_iconLabel);
    layout->addWidget(m_titleLabel);
    layout->addWidget(m_descriptionLabel);
    layout->addWidget(m_addButton);

    connect(m_addButton, &QPushButton::clicked, this, &EmptyStateWidget::addFilesRequested);
}

void EmptyStateWidget::dragEnterEvent(QDragEnterEvent* event) {
    if (event->mimeData()->hasUrls()) {
        event->acceptProposedAction();
    }
}

void EmptyStateWidget::dragMoveEvent(QDragMoveEvent* event) {
    if (event->mimeData()->hasUrls()) {
        event->acceptProposedAction();
    }
}

void EmptyStateWidget::dropEvent(QDropEvent* event) {
    if (event->mimeData()->hasUrls()) {
        QStringList paths;
        for (const QUrl& url : event->mimeData()->urls()) {
            if (url.isLocalFile()) {
                paths.append(url.toLocalFile());
            }
        }
        if (!paths.isEmpty()) {
            emit filesDropped(paths);
        }
        event->acceptProposedAction();
    }
}

void EmptyStateWidget::paintEvent(QPaintEvent* event) {
    QWidget::paintEvent(event);
    QPainter painter(this);
    painter.setRenderHint(QPainter::Antialiasing);

    QPen pen(QColor("#d2d2d7"), 2, Qt::DashLine);
    painter.setPen(pen);
    painter.setBrush(Qt::NoBrush);

    // Draw dashed round rect inside margins
    QRect drawRect = rect().adjusted(10, 10, -10, -10);
    painter.drawRoundedRect(drawRect, 12, 12);
}
