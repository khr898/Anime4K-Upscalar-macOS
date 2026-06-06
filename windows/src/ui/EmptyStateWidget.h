#pragma once

#include <QWidget>
#include <QLabel>
#include <QPushButton>
#include <QVBoxLayout>

class EmptyStateWidget : public QWidget {
    Q_OBJECT
public:
    explicit EmptyStateWidget(const QString& title, const QString& description, const QString& buttonText, QWidget* parent = nullptr);

signals:
    void addFilesRequested();
    void filesDropped(const QStringList& paths);

protected:
    void dragEnterEvent(QDragEnterEvent* event) override;
    void dragMoveEvent(QDragMoveEvent* event) override;
    void dropEvent(QDropEvent* event) override;
    void paintEvent(QPaintEvent* event) override;

private:
    QLabel* m_iconLabel;
    QLabel* m_titleLabel;
    QLabel* m_descriptionLabel;
    QPushButton* m_addButton;
};
