#include "ModePickerWidget.h"

class ModeItemWidget : public QWidget {
public:
    QLabel* nameLabel;
    QLabel* subLabel;

    ModeItemWidget(Anime4KMode mode, QWidget* parent = nullptr) : QWidget(parent) {
        auto* layout = new QVBoxLayout(this);
        layout->setContentsMargins(8, 6, 8, 6);
        layout->setSpacing(2);

        nameLabel = new QLabel(displayName(mode), this);
        nameLabel->setStyleSheet("font-weight: bold; font-size: 13px; color: #1d1d1f;");

        subLabel = new QLabel(subtitle(mode), this);
        subLabel->setStyleSheet("font-size: 11px; color: #86868b;");

        layout->addWidget(nameLabel);
        layout->addWidget(subLabel);

        setAutoFillBackground(false);
        setStyleSheet("background: transparent;");
    }

    void setSelected(bool selected) {
        if (selected) {
            nameLabel->setStyleSheet("font-weight: bold; font-size: 13px; color: #ffffff;");
            subLabel->setStyleSheet("font-size: 11px; color: #e5e5ea;");
        } else {
            nameLabel->setStyleSheet("font-weight: bold; font-size: 13px; color: #1d1d1f;");
            subLabel->setStyleSheet("font-size: 11px; color: #86868b;");
        }
    }
};

ModePickerWidget::ModePickerWidget(AppViewModel* viewModel, QWidget* parent)
    : QWidget(parent)
    , m_viewModel(viewModel)
{
    initUI();
    connect(m_viewModel, &AppViewModel::configurationChanged, this, &ModePickerWidget::updateFromViewModel);
    updateFromViewModel();
}

void ModePickerWidget::initUI() {
    auto* layout = new QVBoxLayout(this);
    layout->setContentsMargins(0, 0, 0, 0);
    layout->setSpacing(8);

    auto* pickerTitle = new QLabel("Processing Mode", this);
    pickerTitle->setStyleSheet("font-weight: bold; font-size: 14px; color: #1d1d1f;");
    layout->addWidget(pickerTitle);

    // Segment Control Layout
    auto* segmentWidget = new QWidget(this);
    segmentWidget->setStyleSheet("background-color: #e8e8ed; border-radius: 6px; padding: 2px;");
    auto* segmentLayout = new QHBoxLayout(segmentWidget);
    segmentLayout->setContentsMargins(0, 0, 0, 0);
    segmentLayout->setSpacing(2);

    m_hqButton = new QPushButton("Anime4K (HQ)", this);
    m_fastButton = new QPushButton("Anime4K (Fast)", this);
    m_noUpButton = new QPushButton("No Upscale", this);
    m_neuralButton = new QPushButton("Neural SR", this);
    m_specialButton = new QPushButton("⚡ Special", this);
    m_specialButton->setEnabled(true);

    QString segmentStyle = 
        "QPushButton {"
        "  background-color: transparent;"
        "  border: none;"
        "  border-radius: 4px;"
        "  padding: 6px 12px;"
        "  color: #515154;"
        "  font-weight: 500;"
        "}"
        "QPushButton:checked {"
        "  background-color: #ffffff;"
        "  color: #1d1d1f;"
        "  font-weight: bold;"
        "}"
        "QPushButton:hover:!checked {"
        "  background-color: #f0f0f5;"
        "}";

    m_hqButton->setStyleSheet(segmentStyle);
    m_fastButton->setStyleSheet(segmentStyle);
    m_noUpButton->setStyleSheet(segmentStyle);
    m_neuralButton->setStyleSheet(segmentStyle);
    m_specialButton->setStyleSheet(segmentStyle);

    m_hqButton->setCheckable(true);
    m_fastButton->setCheckable(true);
    m_noUpButton->setCheckable(true);
    m_neuralButton->setCheckable(true);
    m_specialButton->setCheckable(true);

    m_categoryButtonGroup = new QButtonGroup(this);
    m_categoryButtonGroup->addButton(m_hqButton, 0);
    m_categoryButtonGroup->addButton(m_fastButton, 1);
    m_categoryButtonGroup->addButton(m_noUpButton, 2);
    m_categoryButtonGroup->addButton(m_neuralButton, 3);
    m_categoryButtonGroup->addButton(m_specialButton, 4);
    m_categoryButtonGroup->setExclusive(true);

    segmentLayout->addWidget(m_hqButton);
    segmentLayout->addWidget(m_fastButton);
    segmentLayout->addWidget(m_noUpButton);
    segmentLayout->addWidget(m_neuralButton);
    segmentLayout->addWidget(m_specialButton);

    layout->addWidget(segmentWidget);

    // List of Modes
    m_modeListWidget = new QListWidget(this);
    m_modeListWidget->setSelectionMode(QAbstractItemView::SingleSelection);
    m_modeListWidget->setMinimumHeight(150);
    layout->addWidget(m_modeListWidget);

    connect(m_categoryButtonGroup, &QButtonGroup::idClicked, this, [this](int id) {
        if (id == 0) m_currentCategory = ModeCategory::HQ;
        else if (id == 1) m_currentCategory = ModeCategory::Fast;
        else if (id == 2) m_currentCategory = ModeCategory::NoUpscale;
        else if (id == 3) m_currentCategory = ModeCategory::NeuralSR;
        else m_currentCategory = ModeCategory::Special;
        refreshCategoryModes();
    });

    connect(m_modeListWidget, &QListWidget::currentRowChanged, this, &ModePickerWidget::selectMode);
}

void ModePickerWidget::refreshCategoryModes() {
    m_modeListWidget->blockSignals(true);
    m_modeListWidget->clear();
    m_displayedModes.clear();

    m_displayedModes = modesForCategory(m_currentCategory);
    Anime4KMode currentConfigMode = m_viewModel->configuration().mode;

    int selectRow = -1;
    for (int i = 0; i < m_displayedModes.size(); ++i) {
        Anime4KMode mode = m_displayedModes[i];
        auto* item = new QListWidgetItem(m_modeListWidget);
        item->setSizeHint(QSize(0, 56));
        m_modeListWidget->addItem(item);

        auto* widget = new ModeItemWidget(mode, m_modeListWidget);
        m_modeListWidget->setItemWidget(item, widget);

        if (mode == currentConfigMode) {
            selectRow = i;
        }
    }

    if (selectRow >= 0) {
        m_modeListWidget->setCurrentRow(selectRow);
    } else if (m_modeListWidget->count() > 0) {
        // If config mode is not in this category, do not highlight
        m_modeListWidget->setCurrentRow(-1);
    }

    // Refresh selected text colors
    for (int i = 0; i < m_modeListWidget->count(); ++i) {
        QListWidgetItem* item = m_modeListWidget->item(i);
        auto* widget = static_cast<ModeItemWidget*>(m_modeListWidget->itemWidget(item));
        if (widget) {
            widget->setSelected(item->isSelected());
        }
    }

    m_modeListWidget->blockSignals(false);
}

void ModePickerWidget::selectMode(int index) {
    if (index >= 0 && index < m_displayedModes.size()) {
        Anime4KMode selectedMode = m_displayedModes[index];
        m_viewModel->configurationRef().mode = selectedMode;
        emit m_viewModel->configurationChanged();
    }
}

void ModePickerWidget::updateFromViewModel() {
    Anime4KMode currentMode = m_viewModel->configuration().mode;
    m_currentCategory = category(currentMode);

    m_modeListWidget->blockSignals(true);
    if (m_currentCategory == ModeCategory::HQ) m_hqButton->setChecked(true);
    else if (m_currentCategory == ModeCategory::Fast) m_fastButton->setChecked(true);
    else if (m_currentCategory == ModeCategory::NoUpscale) m_noUpButton->setChecked(true);
    else if (m_currentCategory == ModeCategory::NeuralSR) m_neuralButton->setChecked(true);
    else m_specialButton->setChecked(true);
    m_modeListWidget->blockSignals(false);

    refreshCategoryModes();
}
