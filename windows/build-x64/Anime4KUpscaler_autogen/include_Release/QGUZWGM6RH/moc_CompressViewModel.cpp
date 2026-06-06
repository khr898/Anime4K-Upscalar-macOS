/****************************************************************************
** Meta object code from reading C++ file 'CompressViewModel.h'
**
** Created by: The Qt Meta Object Compiler version 68 (Qt 6.5.3)
**
** WARNING! All changes made in this file will be lost!
*****************************************************************************/

#include "../../../../src/viewmodels/CompressViewModel.h"
#include <QtCore/qmetatype.h>

#if __has_include(<QtCore/qtmochelpers.h>)
#include <QtCore/qtmochelpers.h>
#else
QT_BEGIN_MOC_NAMESPACE
#endif


#include <memory>

#if !defined(Q_MOC_OUTPUT_REVISION)
#error "The header file 'CompressViewModel.h' doesn't include <QObject>."
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
struct qt_meta_stringdata_CLASSCompressViewModelENDCLASS_t {};
static constexpr auto qt_meta_stringdata_CLASSCompressViewModelENDCLASS = QtMocHelpers::stringData(
    "CompressViewModel",
    "filesChanged",
    "",
    "selectedFileChanged",
    "configurationChanged",
    "viewStateChanged",
    "outputDirectoryChanged",
    "jobProgressUpdated",
    "CompressJob*",
    "job"
);
#else  // !QT_MOC_HAS_STRING_DATA
struct qt_meta_stringdata_CLASSCompressViewModelENDCLASS_t {
    uint offsetsAndSizes[20];
    char stringdata0[18];
    char stringdata1[13];
    char stringdata2[1];
    char stringdata3[20];
    char stringdata4[21];
    char stringdata5[17];
    char stringdata6[23];
    char stringdata7[19];
    char stringdata8[13];
    char stringdata9[4];
};
#define QT_MOC_LITERAL(ofs, len) \
    uint(sizeof(qt_meta_stringdata_CLASSCompressViewModelENDCLASS_t::offsetsAndSizes) + ofs), len 
Q_CONSTINIT static const qt_meta_stringdata_CLASSCompressViewModelENDCLASS_t qt_meta_stringdata_CLASSCompressViewModelENDCLASS = {
    {
        QT_MOC_LITERAL(0, 17),  // "CompressViewModel"
        QT_MOC_LITERAL(18, 12),  // "filesChanged"
        QT_MOC_LITERAL(31, 0),  // ""
        QT_MOC_LITERAL(32, 19),  // "selectedFileChanged"
        QT_MOC_LITERAL(52, 20),  // "configurationChanged"
        QT_MOC_LITERAL(73, 16),  // "viewStateChanged"
        QT_MOC_LITERAL(90, 22),  // "outputDirectoryChanged"
        QT_MOC_LITERAL(113, 18),  // "jobProgressUpdated"
        QT_MOC_LITERAL(132, 12),  // "CompressJob*"
        QT_MOC_LITERAL(145, 3)   // "job"
    },
    "CompressViewModel",
    "filesChanged",
    "",
    "selectedFileChanged",
    "configurationChanged",
    "viewStateChanged",
    "outputDirectoryChanged",
    "jobProgressUpdated",
    "CompressJob*",
    "job"
};
#undef QT_MOC_LITERAL
#endif // !QT_MOC_HAS_STRING_DATA
} // unnamed namespace

Q_CONSTINIT static const uint qt_meta_data_CLASSCompressViewModelENDCLASS[] = {

 // content:
      11,       // revision
       0,       // classname
       0,    0, // classinfo
       6,   14, // methods
       0,    0, // properties
       0,    0, // enums/sets
       0,    0, // constructors
       0,       // flags
       6,       // signalCount

 // signals: name, argc, parameters, tag, flags, initial metatype offsets
       1,    0,   50,    2, 0x06,    1 /* Public */,
       3,    0,   51,    2, 0x06,    2 /* Public */,
       4,    0,   52,    2, 0x06,    3 /* Public */,
       5,    0,   53,    2, 0x06,    4 /* Public */,
       6,    0,   54,    2, 0x06,    5 /* Public */,
       7,    1,   55,    2, 0x06,    6 /* Public */,

 // signals: parameters
    QMetaType::Void,
    QMetaType::Void,
    QMetaType::Void,
    QMetaType::Void,
    QMetaType::Void,
    QMetaType::Void, 0x80000000 | 8,    9,

       0        // eod
};

Q_CONSTINIT const QMetaObject CompressViewModel::staticMetaObject = { {
    QMetaObject::SuperData::link<QObject::staticMetaObject>(),
    qt_meta_stringdata_CLASSCompressViewModelENDCLASS.offsetsAndSizes,
    qt_meta_data_CLASSCompressViewModelENDCLASS,
    qt_static_metacall,
    nullptr,
    qt_incomplete_metaTypeArray<qt_meta_stringdata_CLASSCompressViewModelENDCLASS_t,
        // Q_OBJECT / Q_GADGET
        QtPrivate::TypeAndForceComplete<CompressViewModel, std::true_type>,
        // method 'filesChanged'
        QtPrivate::TypeAndForceComplete<void, std::false_type>,
        // method 'selectedFileChanged'
        QtPrivate::TypeAndForceComplete<void, std::false_type>,
        // method 'configurationChanged'
        QtPrivate::TypeAndForceComplete<void, std::false_type>,
        // method 'viewStateChanged'
        QtPrivate::TypeAndForceComplete<void, std::false_type>,
        // method 'outputDirectoryChanged'
        QtPrivate::TypeAndForceComplete<void, std::false_type>,
        // method 'jobProgressUpdated'
        QtPrivate::TypeAndForceComplete<void, std::false_type>,
        QtPrivate::TypeAndForceComplete<CompressJob *, std::false_type>
    >,
    nullptr
} };

void CompressViewModel::qt_static_metacall(QObject *_o, QMetaObject::Call _c, int _id, void **_a)
{
    if (_c == QMetaObject::InvokeMetaMethod) {
        auto *_t = static_cast<CompressViewModel *>(_o);
        (void)_t;
        switch (_id) {
        case 0: _t->filesChanged(); break;
        case 1: _t->selectedFileChanged(); break;
        case 2: _t->configurationChanged(); break;
        case 3: _t->viewStateChanged(); break;
        case 4: _t->outputDirectoryChanged(); break;
        case 5: _t->jobProgressUpdated((*reinterpret_cast< std::add_pointer_t<CompressJob*>>(_a[1]))); break;
        default: ;
        }
    } else if (_c == QMetaObject::RegisterMethodArgumentMetaType) {
        switch (_id) {
        default: *reinterpret_cast<QMetaType *>(_a[0]) = QMetaType(); break;
        case 5:
            switch (*reinterpret_cast<int*>(_a[1])) {
            default: *reinterpret_cast<QMetaType *>(_a[0]) = QMetaType(); break;
            case 0:
                *reinterpret_cast<QMetaType *>(_a[0]) = QMetaType::fromType< CompressJob* >(); break;
            }
            break;
        }
    } else if (_c == QMetaObject::IndexOfMethod) {
        int *result = reinterpret_cast<int *>(_a[0]);
        {
            using _t = void (CompressViewModel::*)();
            if (_t _q_method = &CompressViewModel::filesChanged; *reinterpret_cast<_t *>(_a[1]) == _q_method) {
                *result = 0;
                return;
            }
        }
        {
            using _t = void (CompressViewModel::*)();
            if (_t _q_method = &CompressViewModel::selectedFileChanged; *reinterpret_cast<_t *>(_a[1]) == _q_method) {
                *result = 1;
                return;
            }
        }
        {
            using _t = void (CompressViewModel::*)();
            if (_t _q_method = &CompressViewModel::configurationChanged; *reinterpret_cast<_t *>(_a[1]) == _q_method) {
                *result = 2;
                return;
            }
        }
        {
            using _t = void (CompressViewModel::*)();
            if (_t _q_method = &CompressViewModel::viewStateChanged; *reinterpret_cast<_t *>(_a[1]) == _q_method) {
                *result = 3;
                return;
            }
        }
        {
            using _t = void (CompressViewModel::*)();
            if (_t _q_method = &CompressViewModel::outputDirectoryChanged; *reinterpret_cast<_t *>(_a[1]) == _q_method) {
                *result = 4;
                return;
            }
        }
        {
            using _t = void (CompressViewModel::*)(CompressJob * );
            if (_t _q_method = &CompressViewModel::jobProgressUpdated; *reinterpret_cast<_t *>(_a[1]) == _q_method) {
                *result = 5;
                return;
            }
        }
    }
}

const QMetaObject *CompressViewModel::metaObject() const
{
    return QObject::d_ptr->metaObject ? QObject::d_ptr->dynamicMetaObject() : &staticMetaObject;
}

void *CompressViewModel::qt_metacast(const char *_clname)
{
    if (!_clname) return nullptr;
    if (!strcmp(_clname, qt_meta_stringdata_CLASSCompressViewModelENDCLASS.stringdata0))
        return static_cast<void*>(this);
    return QObject::qt_metacast(_clname);
}

int CompressViewModel::qt_metacall(QMetaObject::Call _c, int _id, void **_a)
{
    _id = QObject::qt_metacall(_c, _id, _a);
    if (_id < 0)
        return _id;
    if (_c == QMetaObject::InvokeMetaMethod) {
        if (_id < 6)
            qt_static_metacall(this, _c, _id, _a);
        _id -= 6;
    } else if (_c == QMetaObject::RegisterMethodArgumentMetaType) {
        if (_id < 6)
            qt_static_metacall(this, _c, _id, _a);
        _id -= 6;
    }
    return _id;
}

// SIGNAL 0
void CompressViewModel::filesChanged()
{
    QMetaObject::activate(this, &staticMetaObject, 0, nullptr);
}

// SIGNAL 1
void CompressViewModel::selectedFileChanged()
{
    QMetaObject::activate(this, &staticMetaObject, 1, nullptr);
}

// SIGNAL 2
void CompressViewModel::configurationChanged()
{
    QMetaObject::activate(this, &staticMetaObject, 2, nullptr);
}

// SIGNAL 3
void CompressViewModel::viewStateChanged()
{
    QMetaObject::activate(this, &staticMetaObject, 3, nullptr);
}

// SIGNAL 4
void CompressViewModel::outputDirectoryChanged()
{
    QMetaObject::activate(this, &staticMetaObject, 4, nullptr);
}

// SIGNAL 5
void CompressViewModel::jobProgressUpdated(CompressJob * _t1)
{
    void *_a[] = { nullptr, const_cast<void*>(reinterpret_cast<const void*>(std::addressof(_t1))) };
    QMetaObject::activate(this, &staticMetaObject, 5, _a);
}
QT_WARNING_POP
