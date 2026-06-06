#pragma once

const char* GLOBAL_STYLESHEET = R"(
    /* Global Background and Fonts */
    QWidget {
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
        font-size: 13px;
        color: #1d1d1f;
    }

    QMainWindow {
        background-color: #f5f5f7;
    }

    /* QTabWidget Style */
    QTabWidget::pane {
        border-top: 1px solid #d2d2d7;
        background-color: #f5f5f7;
    }
    QTabBar::tab {
        background-color: #e8e8ed;
        border: 1px solid #d2d2d7;
        border-bottom-color: none;
        border-top-left-radius: 6px;
        border-top-right-radius: 6px;
        padding: 8px 16px;
        margin-right: 2px;
        color: #515154;
    }
    QTabBar::tab:selected {
        background-color: #ffffff;
        border-color: #d2d2d7;
        border-bottom-color: #ffffff;
        color: #1d1d1f;
        font-weight: bold;
    }
    QTabBar::tab:hover:!selected {
        background-color: #f0f0f5;
    }

    /* Splitter */
    QSplitter::handle {
        background-color: #d2d2d7;
    }

    /* GroupBox Cards */
    QGroupBox {
        background-color: #ffffff;
        border: 1px solid #e2e2e7;
        border-radius: 8px;
        margin-top: 16px;
        padding-top: 16px;
        padding-bottom: 12px;
        padding-left: 12px;
        padding-right: 12px;
    }
    QGroupBox::title {
        subcontrol-origin: margin;
        subcontrol-position: top left;
        left: 12px;
        top: 4px;
        font-weight: bold;
        color: #1d1d1f;
        padding: 0 4px;
    }

    /* Standard Inputs */
    QComboBox {
        background-color: #ffffff;
        border: 1px solid #d2d2d7;
        border-radius: 6px;
        padding: 4px 8px;
        min-width: 120px;
    }
    QComboBox:hover {
        border-color: #007aff;
    }
    QComboBox::drop-down {
        border: none;
        width: 20px;
    }
    QComboBox::down-arrow {
        image: url(:/icons/arrow_down.png);
        width: 10px;
        height: 10px;
    }

    QSpinBox, QDoubleSpinBox {
        background-color: #ffffff;
        border: 1px solid #d2d2d7;
        border-radius: 6px;
        padding: 4px 8px;
    }
    QSpinBox:hover, QDoubleSpinBox:hover {
        border-color: #007aff;
    }

    QLineEdit {
        background-color: #ffffff;
        border: 1px solid #d2d2d7;
        border-radius: 6px;
        padding: 4px 8px;
    }
    QLineEdit:focus {
        border-color: #007aff;
    }

    /* Buttons */
    QPushButton {
        background-color: #ffffff;
        border: 1px solid #d2d2d7;
        border-radius: 6px;
        padding: 6px 12px;
        color: #1d1d1f;
        font-weight: 500;
    }
    QPushButton:hover {
        background-color: #f5f5f7;
        border-color: #86868b;
    }
    QPushButton:pressed {
        background-color: #e8e8ed;
    }
    QPushButton:disabled {
        color: #aeaeb2;
        background-color: #f5f5f7;
        border-color: #e5e5ea;
    }

    /* Primary Accent Button (Blue) */
    QPushButton#primaryButton {
        background-color: #007aff;
        border: 1px solid #0071e3;
        color: #ffffff;
    }
    QPushButton#primaryButton:hover {
        background-color: #0071e3;
    }
    QPushButton#primaryButton:pressed {
        background-color: #0062c3;
    }

    /* Danger Button (Red) */
    QPushButton#dangerButton {
        background-color: #ff3b30;
        border: 1px solid #e02d24;
        color: #ffffff;
    }
    QPushButton#dangerButton:hover {
        background-color: #e02d24;
    }

    /* Checkbox & Radio Buttons */
    QCheckBox::indicator, QRadioButton::indicator {
        width: 16px;
        height: 16px;
    }

    /* List Widgets (Sidebar) */
    QListWidget {
        background-color: #ffffff;
        border: none;
        border-radius: 8px;
        padding: 4px;
    }
    QListWidget::item {
        border-radius: 6px;
        padding: 8px;
        margin-bottom: 2px;
    }
    QListWidget::item:hover {
        background-color: #f5f5f7;
    }
    QListWidget::item:selected {
        background-color: #007aff;
        color: #ffffff;
    }
    QListWidget::item:selected QLabel {
        color: #ffffff;
    }

    /* Progress Bars */
    QProgressBar {
        border: none;
        background-color: #e5e5ea;
        border-radius: 4px;
        text-align: center;
        font-weight: bold;
        height: 8px;
    }
    QProgressBar::chunk {
        background-color: #007aff;
        border-radius: 4px;
    }

    /* Scrollbars */
    QScrollBar:vertical {
        border: none;
        background: transparent;
        width: 8px;
        margin: 0;
    }
    QScrollBar::handle:vertical {
        background: #c1c1c1;
        min-height: 20px;
        border-radius: 4px;
    }
    QScrollBar::handle:vertical:hover {
        background: #a8a8a8;
    }
    QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {
        border: none;
        background: none;
    }

    /* Table Widget (Candidates Table) */
    QTableWidget {
        background-color: #ffffff;
        border: 1px solid #d2d2d7;
        border-radius: 8px;
        gridline-color: #f5f5f7;
    }
    QHeaderView::section {
        background-color: #f5f5f7;
        color: #1d1d1f;
        padding: 6px;
        border: none;
        border-bottom: 1px solid #d2d2d7;
        font-weight: bold;
    }
)";
