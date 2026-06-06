/****************************************************************************
** Meta object code from reading C++ file 'StreamOptimizeViewModel.h'
**
** Created by: The Qt Meta Object Compiler version 68 (Qt 6.5.3)
**
** WARNING! All changes made in this file will be lost!
*****************************************************************************/

#include "../../../../src/viewmodels/StreamOptimizeViewModel.h"
#include <QtCore/qmetatype.h>

#if __has_include(<QtCore/qtmochelpers.h>)
#include <QtCore/qtmochelpers.h>
#else
QT_BEGIN_MOC_NAMESPACE
#endif


#include <memory>

#if !defined(Q_MOC_OUTPUT_REVISION)
#error "The header file 'StreamOptimizeViewModel.h' doesn't include <QObject>."
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
struct qt_meta_stringdata_CLASSStreamOptimizeViewModelENDCLASS_t {};
static constexpr auto qt_meta_stringdata_CLASSStreamOptimizeViewModelENDCLASS = QtMocHelpers::stringData(
    "StreamOptimizeViewModel",
    "filesChanged",
    "",
    "directoriesChanged",
    "configurationChanged",
    "viewStateChanged",
    "jobProgressUpdated",
    "StreamOptimizeJob*",
    "job"
);
#else  // !QT_MOC_HAS_STRING_DATA
struct qt_meta_stringdata_CLASSStreamOptimizeViewModelENDCLASS_t {
    uint offsetsAndSizes[18];
    char stringdata0[24];
    char stringdata1[13];
    char stringdata2[1];
    char stringdata3[19];
    char stringdata4[21];
    char stringdata5[17];
    char stringdata6[19];
    char stringdata7[19];
    char stringdata8[4];
};
#define QT_MOC_LITERAL(ofs, len) \
    uint(sizeof(qt_meta_stringdata_CLASSStreamOptimizeViewModelENDCLASS_t::offsetsAndSizes) + ofs), len 
Q_CONSTINIT static const qt_meta_stringdata_CLASSStreamOptimizeViewModelENDCLASS_t qt_meta_stringdata_CLASSStreamOptimizeViewModelENDCLASS = {
    {
        QT_MOC_LITERAL(0, 23),  // "StreamOptimizeViewModel"
        QT_MOC_LITERAL(24, 12),  // "filesChanged"
        QT_MOC_LITERAL(37, 0),  // ""
        QT_MOC_LITERAL(38, 18),  // "directoriesChanged"
        QT_MOC_LITERAL(57, 20),  // "configurationChanged"
        QT_MOC_LITERAL(78, 16),  // "viewStateChanged"
        QT_MOC_LITERAL(95, 18),  // "jobProgressUpdated"
        QT_MOC_LITERAL(114, 18),  // "StreamOptimizeJob*"
        QT_MOC_LITERAL(133, 3)   // "job"
    },
    "StreamOptimizeViewModel",
    "filesChanged",
    "",
    "directoriesChanged",
    "configurationChanged",
    "viewStateChanged",
    "jobProgressUpdated",
    "StreamOptimizeJob*",
    "job"
};
#undef QT_MOC_LITERAL
#endif // !QT_MOC_HAS_STRING_DATA
} // unnamed namespace

Q_CONSTINIT static const uint qt_meta_data_CLASSStreamOptimizeViewModelENDCLASS[] = {

 // content:
      11,       // revision
       0,       // classname
       0,    0, // classinfo
       5,   14, // methods
       0,    0, // properties
       0,    0, // enums/sets
       0,    0, // constructors
       0,       // flags
       5,       // signalCount

 // signals: name, argc, parameters, tag, flags, initial metatype offsets
       1,    0,   44,    2, 0x06,    1 /* Public */,
       3,    0,   45,    2, 0x06,    2 /* Public */,
       4,    0,   46,    2, 0x06,    3 /* Public */,
       5,    0,   47,    2, 0x06,    4 /* Public */,
       6,    1,   48,    2, 0x06,    5 /* Public */,

 // signals: parameters
    QMetaType::Void,
    QMetaType::Void,
    QMetaType::Void,
    QMetaType::Void,
    QMetaType::Void, 0x80000000 | 7,    8,

       0        // eod
};

Q_CONSTINIT const QMetaObject StreamOptimizeViewModel::staticMetaObject = { {
    QMetaObject::SuperData::link<QObject::staticMetaObject>(),
    qt_meta_stringdata_CLASSStreamOptimizeViewModelENDCLASS.offsetsAndSizes,
    qt_meta_data_CLASSStreamOptimizeViewModelENDCLASS,
    qt_static_metacall,
    nullptr,
    qt_incomplete_metaTypeArray<qt_meta_stringdata_CLASSStreamOptimizeViewModelENDCLASS_t,
        // Q_OBJECT / Q_GADGET
        QtPrivate::TypeAndForceComplete<StreamOptimizeViewModel, std::true_type>,
        // method 'filesChanged'
        QtPrivate::TypeAndForceComplete<void, std::false_type>,
        // method 'directoriesChanged'
        QtPrivate::TypeAndForceComplete<void, std::false_type>,
        // method 'configurationChanged'
        QtPrivate::TypeAndForceComplete<void, std::false_type>,
        // method 'viewStateChanged'
        QtPrivate::TypeAndForceComplete<void, std::false_type>,
        // method 'jobProgressUpdated'
        QtPrivate::TypeAndForceComplete<void, std::false_type>,
        QtPrivate::TypeAndForceComplete<StreamOptimizeJob *, std::false_type>
    >,
    nullptr
} };

void StreamOptimizeViewModel::qt_static_metacall(QObject *_o, QMetaObject::Call _c, int _id, void **_a)
{
    if (_c == QMetaObject::InvokeMetaMethod) {
        auto *_t = static_cast<StreamOptimizeViewModel *>(_o);
        (void)_t;
        switch (_id) {
        case 0: _t->filesChanged(); break;
        case 1: _t->directoriesChanged(); break;
        case 2: _t->configurationChanged(); break;
        case 3: _t->viewStateChanged(); break;
        case 4: _t->jobProgressUpdated((*reinterpret_cast< std::add_pointer_t<StreamOptimizeJob*>>(_a[1]))); break;
        default: ;
        }
    } else if (_c == QMetaObject::RegisterMethodArgumentMetaType) {
        switch (_id) {
        default: *reinterpret_cast<QMetaType *>(_a[0]) = QMetaType(); break;
        case 4:
            switch (*reinterpret_cast<int*>(_a[1])) {
            default: *reinterpret_cast<QMetaType *>(_a[0]) = QMetaType(); break;
            case 0:
                *reinterpret_cast<QMetaType *>(_a[0]) = QMetaType::fromType< StreamOptimizeJob* >(); break;
            }
            break;
        }
    } else if (_c == QMetaObject::IndexOfMethod) {
        int *result = reinterpret_cast<int *>(_a[0]);
        {
            using _t = void (StreamOptimizeViewModel::*)();
            if (_t _q_method = &StreamOptimizeViewModel::filesChanged; *reinterpret_cast<_t *>(_a[1]) == _q_method) {
                *result = 0;
                return;
            }
        }
        {
            using _t = void (StreamOptimizeViewModel::*)();
            if (_t _q_method = &StreamOptimizeViewModel::directoriesChanged; *reinterpret_cast<_t *>(_a[1]) == _q_method) {
                *result = 1;
                return;
            }
        }
        {
            using _t = void (StreamOptimizeViewModel::*)();
            if (_t _q_method = &StreamOptimizeViewModel::configurationChanged; *reinterpret_cast<_t *>(_a[1]) == _q_method) {
                *result = 2;
                return;
            }
        }
        {
            using _t = void (StreamOptimizeViewModel::*)();
            if (_t _q_method = &StreamOptimizeViewModel::viewStateChanged; *reinterpret_cast<_t *>(_a[1]) == _q_method) {
                *result = 3;
                return;
            }
        }
        {
            using _t = void (StreamOptimizeViewModel::*)(StreamOptimizeJob * );
            if (_t _q_method = &StreamOptimizeViewModel::jobProgressUpdated; *reinterpret_cast<_t *>(_a[1]) == _q_method) {
                *result = 4;
                return;
            }
        }
    }
}

const QMetaObject *StreamOptimizeViewModel::metaObject() const
{
    return QObject::d_ptr->metaObject ? QObject::d_ptr->dynamicMetaObject() : &staticMetaObject;
}

void *StreamOptimizeViewModel::qt_metacast(const char *_clname)
{
    if (!_clname) return nullptr;
    if (!strcmp(_clname, qt_meta_stringdata_CLASSStreamOptimizeViewModelENDCLASS.stringdata0))
        return static_cast<void*>(this);
    return QObject::qt_metacast(_clname);
}

int StreamOptimizeViewModel::qt_metacall(QMetaObject::Call _c, int _id, void **_a)
{
    _id = QObject::qt_metacall(_c, _id, _a);
    if (_id < 0)
        return _id;
    if (_c == QMetaObject::InvokeMetaMethod) {
        if (_id < 5)
            qt_static_metacall(this, _c, _id, _a);
        _id -= 5;
    } else if (_c == QMetaObject::RegisterMethodArgumentMetaType) {
        if (_id < 5)
            qt_static_metacall(this, _c, _id, _a);
        _id -= 5;
    }
    return _id;
}

// SIGNAL 0
void StreamOptimizeViewModel::filesChanged()
{
    QMetaObject::activate(this, &staticMetaObject, 0, nullptr);
}

// SIGNAL 1
void StreamOptimizeViewModel::directoriesChanged()
{
    QMetaObject::activate(this, &staticMetaObject, 1, nullptr);
}

// SIGNAL 2
void StreamOptimizeViewModel::configurationChanged()
{
    QMetaObject::activate(this, &staticMetaObject, 2, nullptr);
}

// SIGNAL 3
void StreamOptimizeViewModel::viewStateChanged()
{
    QMetaObject::activate(this, &staticMetaObject, 3, nullptr);
}

// SIGNAL 4
void StreamOptimizeViewModel::jobProgressUpdated(StreamOptimizeJob * _t1)
{
    void *_a[] = { nullptr, const_cast<void*>(reinterpret_cast<const void*>(std::addressof(_t1))) };
    QMetaObject::activate(this, &staticMetaObject, 4, _a);
}
QT_WARNING_POP
