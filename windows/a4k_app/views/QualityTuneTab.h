#pragma once
#include "views/QualityTuneTab.g.h"
namespace winrt::Anime4KUpscaler::views::implementation {
struct QualityTuneTab : QualityTuneTabT<QualityTuneTab> {
    QualityTuneTab() { InitializeComponent(); }
};
}
namespace winrt::Anime4KUpscaler::views::factory_implementation {
struct QualityTuneTab : QualityTuneTabT<QualityTuneTab, implementation::QualityTuneTab> {};
}
