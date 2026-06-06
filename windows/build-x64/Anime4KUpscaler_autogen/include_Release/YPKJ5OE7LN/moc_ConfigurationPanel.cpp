/****************************************************************************
** Meta object code from reading C++ file 'ConfigurationPanel.h'
**
** Created by: The Qt Meta Object Compiler version 68 (Qt 6.5.3)
**
** WARNING! All changes made in this file will be lost!
*****************************************************************************/

#include "../../../../src/ui/ConfigurationPanel.h"
#include <QtGui/qtextcursor.h>
#include <QtCore/qmetatype.h>

#if __has_include(<QtCore/qtmochelpers.h>)
#include <QtCore/qtmochelpers.h>
#else
QT_BEGIN_MOC_NAMESPACE
#endif


#include <memory>

#if !defined(Q_MOC_OUTPUT_REVISION)
#error "The header file 'ConfigurationPanel.h' doesn't include <QObject>."
#elif Q_MOC_OUTPUT_REVISION != 68
#error "This file was generated using the moc from 6.5.3. It"
#error "cannot be used with the include files from this version of Qt."
#error "(The moc has changed too much.)"
#endif

#ifndef Q_CONSTINIT
#define Q_CONSTINIT
#endif

QT_WARNING_PUSH
QT_WARNING_DISABLE_DEPRECATED
QT_WARNING_DISABLE_GCC("-Wuseless-cast")
namespace {

#ifdef QT_MOC_HAS_STRINGDATA
struct qt_meta_stringdata_CLASSConfigurationPanelENDCLASS_t {};
static constexpr auto qt_meta_stringdata_CLASSConfigurationPanelENDCLASS = QtMocHelpers::stringData(
    "ConfigurationPanel",
    "updateFromViewModel",
    "",
    "onResolutionSelected",
    "id",
    "onCodecChanged",
    "index",
    "onPresetChanged",
    "onQualitySliderChanged",
    "value",
    "onQualitySpinChanged",
    "onBitrateSliderChanged",
    "onBitrateSpinChanged",
    "onLongGOPChanged",
    "state"
);
#else  // !QT_MOC_HAS_STRING_DATA
struct qt_meta_stringdata_CLASSConfigurationPanelENDCLASS_t {
    uint offsetsAndSizes[30];
    char stringdata0[19];
    char stringdata1[20];
    char stringdata2[1];
    char stringdata3[21];
    char stringdata4[3];
    char stringdata5[15];
    char stringdata6[6];
    char stringdata7[16];
    char stringdata8[23];
    char stringdata9[6];
    char stringdata10[21];
    char stringdata11[23];
    char stringdata12[21];
    char stringdata13[17];
    char stringdata14[6];
};
#define QT_MOC_LITERAL(ofs, len) \
    uint(sizeof(qt_meta_stringdata_CLASSConfigurationPanelENDCLASS_t::offsetsAndSizes) + ofs), len 
Q_CONSTINIT static const qt_meta_stringdata_CLASSConfigurationPanelENDCLASS_t qt_meta_stringdata_CLASSConfigurationPanelENDCLASS = {
    {
        QT_MOC_LITERAL(0, 18),  // "ConfigurationPanel"
        QT_MOC_LITERAL(19, 19),  // "updateFromViewModel"
        QT_MOC_LITERAL(39, 0),  // ""
        QT_MOC_LITERAL(40, 20),  // "onResolutionSelected"
        QT_MOC_LITERAL(61, 2),  // "id"
        QT_MOC_LITERAL(64, 14),  // "onCodecChanged"
        QT_MOC_LITERAL(79, 5),  // "index"
        QT_MOC_LITERAL(85, 15),  // "onPresetChanged"
        QT_MOC_LITERAL(101, 22),  // "onQualitySliderChanged"
        QT_MOC_LITERAL(124, 5),  // "value"
        QT_MOC_LITERAL(130, 20),  // "onQualitySpinChanged"
        QT_MOC_LITERAL(151, 22),  // "onBitrateSliderChanged"
        QT_MOC_LITERAL(174, 20),  // "onBitrateSpinChanged"
        QT_MOC_LITERAL(195, 16),  // "onLongGOPChanged"
        QT_MOC_LITERAL(212, 5)   // "state"
    },
    "ConfigurationPanel",
    "updateFromViewModel",
    "",
    "onResolutionSelected",
    "id",
    "onCodecChanged",
    "index",
    "onPresetChanged",
    "onQualitySliderChanged",
    "value",
    "onQualitySpinChanged",
    "onBitrateSliderChanged",
    "onBitrateSpinChanged",
    "onLongGOPChanged",
    "state"
};
#undef QT_MOC_LITERAL
#endif // !QT_MOC_HAS_STRING_DATA
} // unnamed namespace

Q_CONSTINIT static const uint qt_meta_data_CLASSConfigurationPanelENDCLASS[] = {

 // content:
      11,       // revision
       0,       // classname
       0,    0, // classinfo
       9,   14, // methods
       0,    0, // properties
       0,    0, // enums/sets
       0,    0, // constructors
       0,       // flags
       0,       // signalCount

 // slots: name, argc, parameters, tag, flags, initial metatype offsets
       1,    0,   68,    2, 0x08,    1 /* Private */,
       3,    1,   69,    2, 0x08,    2 /* Private */,
       5,    1,   72,    2, 0x08,    4 /* Private */,
       7,    1,   75,    2, 0x08,    6 /* Private */,
       8,    1,   78,    2, 0x08,    8 /* Private */,
      10,    1,   81,    2, 0x08,   10 /* Private */,
      11,    1,   84,    2, 0x08,   12 /* Private */,
      12,    1,   87,    2, 0x08,   14 /* Private */,
      13,    1,   90,    2, 0x08,   16 /* Private */,

 // slots: parameters
    QMetaType::Void,
    QMetaType::Void, QMetaType::Int,    4,
    QMetaType::Void, QMetaType::Int,    6,
    QMetaType::Void, QMetaType::Int,    6,
    QMetaType::Void, QMetaType::Int,    9,
    QMetaType::Void, QMetaType::Int,    9,
    QMetaType::Void, QMetaType::Int,    9,
    QMetaType::Void, QMetaType::Int,    9,
    QMetaType::Void, QMetaType::Int,   14,

       0        // eod
};

Q_CONSTINIT const QMetaObject ConfigurationPanel::staticMetaObject = { {
    QMetaObject::SuperData::link<QWidget::staticMetaObject>(),
    qt_meta_stringdata_CLASSConfigurationPanelENDCLASS.offsetsAndSizes,
    qt_meta_data_CLASSConfigurationPanelENDCLASS,
    qt_static_metacall,
    nullptr,
    qt_incomplete_metaTypeArray<qt_meta_stringdata_CLASSConfigurationPanelENDCLASS_t,
        // Q_OBJECT / Q_GADGET
        QtPrivate::TypeAndForceComplete<ConfigurationPanel, std::true_type>,
        // method 'updateFromViewModel'
        QtPrivate::TypeAndForceComplete<void, std::false_type>,
        // method 'onResolutionSelected'
        QtPrivate::TypeAndForceComplete<void, std::false_type>,
        QtPrivate::TypeAndForceComplete<int, std::false_type>,
        // method 'onCodecChanged'
        QtPrivate::TypeAndForceComplete<void, std::false_type>,
        QtPrivate::TypeAndForceComplete<int, std::false_type>,
        // method 'onPresetChanged'
        QtPrivate::TypeAndForceComplete<void, std::false_type>,
        QtPrivate::TypeAndForceComplete<int, std::false_type>,
        // method 'onQualitySliderChanged'
        QtPrivate::TypeAndForceComplete<void, std::false_type>,
        QtPrivate::TypeAndForceComplete<int, std::false_type>,
        // method 'onQualitySpinChanged'
        QtPrivate::TypeAndForceComplete<void, std::false_type>,
        QtPrivate::TypeAndForceComplete<int, std::false_type>,
        // method 'onBitrateSliderChanged'
        QtPrivate::TypeAndForceComplete<void, std::false_type>,
        QtPrivate::TypeAndForceComplete<int, std::false_type>,
        // method 'onBitrateSpinChanged'
        QtPrivate::TypeAndForceComplete<void, std::false_type>,
        QtPrivate::TypeAndForceComplete<int, std::false_type>,
        // method 'onLongGOPChanged'
        QtPrivate::TypeAndForceComplete<void, std::false_type>,
        QtPrivate::TypeAndForceComplete<int, std::false_type>
    >,
    nullptr
} };

void ConfigurationPanel::qt_static_metacall(QObject *_o, QMetaObject::Call _c, int _id, void **_a)
{
    if (_c == QMetaObject::InvokeMetaMethod) {
        auto *_t = static_cast<ConfigurationPanel *>(_o);
        (void)_t;
        switch (_id) {
        case 0: _t->updateFromViewModel(); break;
        case 1: _t->onResolutionSelected((*reinterpret_cast< std::add_pointer_t<int>>(_a[1]))); break;
        case 2: _t->onCodecChanged((*reinterpret_cast< std::add_pointer_t<int>>(_a[1]))); break;
        case 3: _t->onPresetChanged((*reinterpret_cast< std::add_pointer_t<int>>(_a[1]))); break;
        case 4: _t->onQualitySliderChanged((*reinterpret_cast< std::add_pointer_t<int>>(_a[1]))); break;
        case 5: _t->onQualitySpinChanged((*reinterpret_cast< std::add_pointer_t<int>>(_a[1]))); break;
        case 6: _t->onBitrateSliderChanged((*reinterpret_cast< std::add_pointer_t<int>>(_a[1]))); break;
        case 7: _t->onBitrateSpinChanged((*reinterpret_cast< std::add_pointer_t<int>>(_a[1]))); break;
        case 8: _t->onLongGOPChanged((*reinterpret_cast< std::add_pointer_t<int>>(_a[1]))); break;
        default: ;
        }
    }
}

const QMetaObject *ConfigurationPanel::metaObject() const
{
    return QObject::d_ptr->metaObject ? QObject::d_ptr->dynamicMetaObject() : &staticMetaObject;
}

void *ConfigurationPanel::qt_metacast(const char *_clname)
{
    if (!_clname) return nullptr;
    if (!strcmp(_clname, qt_meta_stringdata_CLASSConfigurationPanelENDCLASS.stringdata0))
        return static_cast<void*>(this);
    return QWidget::qt_metacast(_clname);
}

int ConfigurationPanel::qt_metacall(QMetaObject::Call _c, int _id, void **_a)
{
    _id = QWidget::qt_metacall(_c, _id, _a);
    if (_id < 0)
        return _id;
    if (_c == QMetaObject::InvokeMetaMethod) {
        if (_id < 9)
            qt_static_metacall(this, _c, _id, _a);
        _id -= 9;
    } else if (_c == QMetaObject::RegisterMethodArgumentMetaType) {
        if (_id < 9)
            *reinterpret_cast<QMetaType *>(_a[0]) = QMetaType();
        _id -= 9;
    }
    return _id;
}
QT_WARNING_POP
