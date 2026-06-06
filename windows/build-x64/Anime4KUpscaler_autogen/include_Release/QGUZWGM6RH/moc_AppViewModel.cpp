/****************************************************************************
** Meta object code from reading C++ file 'AppViewModel.h'
**
** Created by: The Qt Meta Object Compiler version 68 (Qt 6.5.3)
**
** WARNING! All changes made in this file will be lost!
*****************************************************************************/

#include "../../../../src/viewmodels/AppViewModel.h"
#include <QtCore/qmetatype.h>

#if __has_include(<QtCore/qtmochelpers.h>)
#include <QtCore/qtmochelpers.h>
#else
QT_BEGIN_MOC_NAMESPACE
#endif


#include <memory>

#if !defined(Q_MOC_OUTPUT_REVISION)
#error "The header file 'AppViewModel.h' doesn't include <QObject>."
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
struct qt_meta_stringdata_CLASSAppViewModelENDCLASS_t {};
static constexpr auto qt_meta_stringdata_CLASSAppViewModelENDCLASS = QtMocHelpers::stringData(
    "AppViewModel",
    "filesChanged",
    "",
    "selectedFileChanged",
    "configurationChanged",
    "viewStateChanged",
    "dependencyAlertChanged",
    "outputDirectoryChanged",
    "qualityTuneStateChanged",
    "qualityTuneCandidatesChanged"
);
#else  // !QT_MOC_HAS_STRING_DATA
struct qt_meta_stringdata_CLASSAppViewModelENDCLASS_t {
    uint offsetsAndSizes[20];
    char stringdata0[13];
    char stringdata1[13];
    char stringdata2[1];
    char stringdata3[20];
    char stringdata4[21];
    char stringdata5[17];
    char stringdata6[23];
    char stringdata7[23];
    char stringdata8[24];
    char stringdata9[29];
};
#define QT_MOC_LITERAL(ofs, len) \
    uint(sizeof(qt_meta_stringdata_CLASSAppViewModelENDCLASS_t::offsetsAndSizes) + ofs), len 
Q_CONSTINIT static const qt_meta_stringdata_CLASSAppViewModelENDCLASS_t qt_meta_stringdata_CLASSAppViewModelENDCLASS = {
    {
        QT_MOC_LITERAL(0, 12),  // "AppViewModel"
        QT_MOC_LITERAL(13, 12),  // "filesChanged"
        QT_MOC_LITERAL(26, 0),  // ""
        QT_MOC_LITERAL(27, 19),  // "selectedFileChanged"
        QT_MOC_LITERAL(47, 20),  // "configurationChanged"
        QT_MOC_LITERAL(68, 16),  // "viewStateChanged"
        QT_MOC_LITERAL(85, 22),  // "dependencyAlertChanged"
        QT_MOC_LITERAL(108, 22),  // "outputDirectoryChanged"
        QT_MOC_LITERAL(131, 23),  // "qualityTuneStateChanged"
        QT_MOC_LITERAL(155, 28)   // "qualityTuneCandidatesChanged"
    },
    "AppViewModel",
    "filesChanged",
    "",
    "selectedFileChanged",
    "configurationChanged",
    "viewStateChanged",
    "dependencyAlertChanged",
    "outputDirectoryChanged",
    "qualityTuneStateChanged",
    "qualityTuneCandidatesChanged"
};
#undef QT_MOC_LITERAL
#endif // !QT_MOC_HAS_STRING_DATA
} // unnamed namespace

Q_CONSTINIT static const uint qt_meta_data_CLASSAppViewModelENDCLASS[] = {

 // content:
      11,       // revision
       0,       // classname
       0,    0, // classinfo
       8,   14, // methods
       0,    0, // properties
       0,    0, // enums/sets
       0,    0, // constructors
       0,       // flags
       8,       // signalCount

 // signals: name, argc, parameters, tag, flags, initial metatype offsets
       1,    0,   62,    2, 0x06,    1 /* Public */,
       3,    0,   63,    2, 0x06,    2 /* Public */,
       4,    0,   64,    2, 0x06,    3 /* Public */,
       5,    0,   65,    2, 0x06,    4 /* Public */,
       6,    0,   66,    2, 0x06,    5 /* Public */,
       7,    0,   67,    2, 0x06,    6 /* Public */,
       8,    0,   68,    2, 0x06,    7 /* Public */,
       9,    0,   69,    2, 0x06,    8 /* Public */,

 // signals: parameters
    QMetaType::Void,
    QMetaType::Void,
    QMetaType::Void,
    QMetaType::Void,
    QMetaType::Void,
    QMetaType::Void,
    QMetaType::Void,
    QMetaType::Void,

       0        // eod
};

Q_CONSTINIT const QMetaObject AppViewModel::staticMetaObject = { {
    QMetaObject::SuperData::link<QObject::staticMetaObject>(),
    qt_meta_stringdata_CLASSAppViewModelENDCLASS.offsetsAndSizes,
    qt_meta_data_CLASSAppViewModelENDCLASS,
    qt_static_metacall,
    nullptr,
    qt_incomplete_metaTypeArray<qt_meta_stringdata_CLASSAppViewModelENDCLASS_t,
        // Q_OBJECT / Q_GADGET
        QtPrivate::TypeAndForceComplete<AppViewModel, std::true_type>,
        // method 'filesChanged'
        QtPrivate::TypeAndForceComplete<void, std::false_type>,
        // method 'selectedFileChanged'
        QtPrivate::TypeAndForceComplete<void, std::false_type>,
        // method 'configurationChanged'
        QtPrivate::TypeAndForceComplete<void, std::false_type>,
        // method 'viewStateChanged'
        QtPrivate::TypeAndForceComplete<void, std::false_type>,
        // method 'dependencyAlertChanged'
        QtPrivate::TypeAndForceComplete<void, std::false_type>,
        // method 'outputDirectoryChanged'
        QtPrivate::TypeAndForceComplete<void, std::false_type>,
        // method 'qualityTuneStateChanged'
        QtPrivate::TypeAndForceComplete<void, std::false_type>,
        // method 'qualityTuneCandidatesChanged'
        QtPrivate::TypeAndForceComplete<void, std::false_type>
    >,
    nullptr
} };

void AppViewModel::qt_static_metacall(QObject *_o, QMetaObject::Call _c, int _id, void **_a)
{
    if (_c == QMetaObject::InvokeMetaMethod) {
        auto *_t = static_cast<AppViewModel *>(_o);
        (void)_t;
        switch (_id) {
        case 0: _t->filesChanged(); break;
        case 1: _t->selectedFileChanged(); break;
        case 2: _t->configurationChanged(); break;
        case 3: _t->viewStateChanged(); break;
        case 4: _t->dependencyAlertChanged(); break;
        case 5: _t->outputDirectoryChanged(); break;
        case 6: _t->qualityTuneStateChanged(); break;
        case 7: _t->qualityTuneCandidatesChanged(); break;
        default: ;
        }
    } else if (_c == QMetaObject::IndexOfMethod) {
        int *result = reinterpret_cast<int *>(_a[0]);
        {
            using _t = void (AppViewModel::*)();
            if (_t _q_method = &AppViewModel::filesChanged; *reinterpret_cast<_t *>(_a[1]) == _q_method) {
                *result = 0;
                return;
            }
        }
        {
            using _t = void (AppViewModel::*)();
            if (_t _q_method = &AppViewModel::selectedFileChanged; *reinterpret_cast<_t *>(_a[1]) == _q_method) {
                *result = 1;
                return;
            }
        }
        {
            using _t = void (AppViewModel::*)();
            if (_t _q_method = &AppViewModel::configurationChanged; *reinterpret_cast<_t *>(_a[1]) == _q_method) {
                *result = 2;
                return;
            }
        }
        {
            using _t = void (AppViewModel::*)();
            if (_t _q_method = &AppViewModel::viewStateChanged; *reinterpret_cast<_t *>(_a[1]) == _q_method) {
                *result = 3;
                return;
            }
        }
        {
            using _t = void (AppViewModel::*)();
            if (_t _q_method = &AppViewModel::dependencyAlertChanged; *reinterpret_cast<_t *>(_a[1]) == _q_method) {
                *result = 4;
                return;
            }
        }
        {
            using _t = void (AppViewModel::*)();
            if (_t _q_method = &AppViewModel::outputDirectoryChanged; *reinterpret_cast<_t *>(_a[1]) == _q_method) {
                *result = 5;
                return;
            }
        }
        {
            using _t = void (AppViewModel::*)();
            if (_t _q_method = &AppViewModel::qualityTuneStateChanged; *reinterpret_cast<_t *>(_a[1]) == _q_method) {
                *result = 6;
                return;
            }
        }
        {
            using _t = void (AppViewModel::*)();
            if (_t _q_method = &AppViewModel::qualityTuneCandidatesChanged; *reinterpret_cast<_t *>(_a[1]) == _q_method) {
                *result = 7;
                return;
            }
        }
    }
    (void)_a;
}

const QMetaObject *AppViewModel::metaObject() const
{
    return QObject::d_ptr->metaObject ? QObject::d_ptr->dynamicMetaObject() : &staticMetaObject;
}

void *AppViewModel::qt_metacast(const char *_clname)
{
    if (!_clname) return nullptr;
    if (!strcmp(_clname, qt_meta_stringdata_CLASSAppViewModelENDCLASS.stringdata0))
        return static_cast<void*>(this);
    return QObject::qt_metacast(_clname);
}

int AppViewModel::qt_metacall(QMetaObject::Call _c, int _id, void **_a)
{
    _id = QObject::qt_metacall(_c, _id, _a);
    if (_id < 0)
        return _id;
    if (_c == QMetaObject::InvokeMetaMethod) {
        if (_id < 8)
            qt_static_metacall(this, _c, _id, _a);
        _id -= 8;
    } else if (_c == QMetaObject::RegisterMethodArgumentMetaType) {
        if (_id < 8)
            *reinterpret_cast<QMetaType *>(_a[0]) = QMetaType();
        _id -= 8;
    }
    return _id;
}

// SIGNAL 0
void AppViewModel::filesChanged()
{
    QMetaObject::activate(this, &staticMetaObject, 0, nullptr);
}

// SIGNAL 1
void AppViewModel::selectedFileChanged()
{
    QMetaObject::activate(this, &staticMetaObject, 1, nullptr);
}

// SIGNAL 2
void AppViewModel::configurationChanged()
{
    QMetaObject::activate(this, &staticMetaObject, 2, nullptr);
}

// SIGNAL 3
void AppViewModel::viewStateChanged()
{
    QMetaObject::activate(this, &staticMetaObject, 3, nullptr);
}

// SIGNAL 4
void AppViewModel::dependencyAlertChanged()
{
    QMetaObject::activate(this, &staticMetaObject, 4, nullptr);
}

// SIGNAL 5
void AppViewModel::outputDirectoryChanged()
{
    QMetaObject::activate(this, &staticMetaObject, 5, nullptr);
}

// SIGNAL 6
void AppViewModel::qualityTuneStateChanged()
{
    QMetaObject::activate(this, &staticMetaObject, 6, nullptr);
}

// SIGNAL 7
void AppViewModel::qualityTuneCandidatesChanged()
{
    QMetaObject::activate(this, &staticMetaObject, 7, nullptr);
}
QT_WARNING_POP
